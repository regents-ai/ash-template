defmodule AshTemplateWeb.MessagesApiTest do
  # An agent leaving a message for the site's team over signed HTTP
  # (`POST /api/v1/messages/{topic}`) and the hosted MCP tool `messages_leave`:
  # - a signed agent leaves one and gets its receipt, 201, as itself whatever
  #   the body says about the sender;
  # - its operation_id answers 200 with the first receipt, through either door,
  #   and 409 idempotency_conflict for other text;
  # - an unsigned request leaves nothing;
  # - input the action cannot take is 422 invalid_message with details, through
  #   either door;
  # - past the agent's allowance, 429 too_many_requests with the seconds to wait,
  #   through either door, and nothing is left.
  # The sign-in service is stubbed: it vouches for the wallet a request names when
  # the request carries the fixture proof. Each test calls from its own address.
  use ExUnit.Case, async: false

  import Plug.Conn
  import Plug.Test

  alias AshTemplate.Actors.System
  alias AshTemplate.Messages.Message
  alias AshTemplate.Repo

  @endpoint AshTemplateWeb.Endpoint

  setup do
    owner = Ecto.Adapters.SQL.Sandbox.start_owner!(Repo, shared: true)
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(owner) end)

    old = Application.fetch_env(:regent_agents, :req_options)
    Application.put_env(:regent_agents, :req_options, plug: {Req.Test, RegentAgents.Broker})

    on_exit(fn ->
      case old do
        {:ok, opts} -> Application.put_env(:regent_agents, :req_options, opts)
        :error -> Application.delete_env(:regent_agents, :req_options)
      end
    end)

    Req.Test.stub(RegentAgents.Broker, fn conn ->
      {:ok, body, conn} = read_body(conn)
      headers = Jason.decode!(body)["headers"]
      wallet = headers["x-agent-wallet-address"]

      if headers["x-siwa-signature"] == "fixture-proof" do
        Req.Test.json(conn, %{
          code: "http_envelope_valid",
          data: %{
            verified: true,
            walletAddress: wallet,
            agentBook: nil,
            agentRegistration: nil,
            principal: %{
              kind: "wallet",
              wallet_address: wallet,
              chain_id: 8453,
              audience: "ash-template"
            }
          }
        })
      else
        conn
        |> put_status(401)
        |> Req.Test.json(%{error: %{code: "http_signature_invalid", message: "No", hint: "Sign"}})
      end
    end)

    %{from: {10, :rand.uniform(250), :rand.uniform(250), :rand.uniform(250)}, agent: wallet()}
  end

  test "a signed agent leaves a message as itself, and its operation_id answers it again",
       %{from: from, agent: agent} do
    key = Ecto.UUID.generate()

    body = %{
      body: "Hello team",
      reply_to: "agent@example.com",
      operation_id: key,
      agent_id: Ecto.UUID.generate(),
      sender_name: "Someone else"
    }

    left = http(from, agent, "agents", body)
    assert left.status == 201
    assert %{"receipt" => %{"id" => id, "topic" => "agents", "inserted_at" => _}} = json(left)

    message = Ash.get!(Message, id, authorize?: false)
    assert {message.body, message.reply_to} == {"Hello team", "agent@example.com"}
    assert AshTemplate.Agents.get_agent!(message.agent_id, actor: %System{}).wallet_address == agent
    assert Message.sender(message) == %{name: nil, wallet: agent, ens_name: nil}

    again = http(from, agent, "agents", body)
    assert again.status == 200
    assert json(again)["receipt"]["id"] == id

    through_mcp = mcp(from, agent, %{topic: "agents", body: "Hello team", reply_to: "agent@example.com", operation_id: key})
    assert %{"isError" => false, "structuredContent" => %{"replayed" => true, "receipt" => %{"id" => ^id}}} = through_mcp

    other = http(from, agent, "agents", %{body: "Other text", operation_id: key})
    assert other.status == 409
    assert json(other)["error"]["code"] == "idempotency_conflict"
  end

  test "the hosted tool leaves a message, and refuses input the action cannot take with HTTP's code",
       %{from: from, agent: agent} do
    assert %{"isError" => false, "structuredContent" => %{"replayed" => false, "receipt" => %{"id" => id}}} =
             mcp(from, agent, %{topic: "watchdog", body: "From MCP", operation_id: Ecto.UUID.generate()})

    assert %Message{topic: "watchdog", body: "From MCP"} = Ash.get!(Message, id, authorize?: false)

    too_long = %{topic: "agents", body: String.duplicate("a", 2001), operation_id: Ecto.UUID.generate()}
    assert %{"isError" => true, "content" => [%{"text" => text}]} = mcp(from, agent, too_long)
    assert %{"code" => "invalid_message", "details" => [%{"field" => "body"}]} = Jason.decode!(text)["error"]

    refused = http(from, agent, "agents", too_long |> Map.delete(:topic))
    assert refused.status == 422
    assert %{"code" => "invalid_message", "details" => [%{"field" => "body"}]} = json(refused)["error"]
  end

  test "past its allowance an agent is told the seconds to wait, and leaves nothing",
       %{from: from, agent: agent} do
    left = http(from, agent, "agents", %{body: "First", operation_id: Ecto.UUID.generate()})
    assert left.status == 201
    agent_id = Ash.get!(Message, json(left)["receipt"]["id"], authorize?: false).agent_id
    limit = Application.fetch_env!(:ash_template, :limits)[:message][:limit]
    for _ <- 2..limit, do: :ok = AshTemplate.Limits.spend(:message, {:agent, agent_id})
    count = length(Ash.read!(Message, authorize?: false))

    refused = http(from, agent, "agents", %{body: "Too soon", operation_id: Ecto.UUID.generate()})
    assert refused.status == 429
    assert json(refused)["error"]["code"] == "too_many_requests"
    assert [seconds] = get_resp_header(refused, "retry-after")
    assert String.to_integer(seconds) in 1..3600

    too_soon = %{topic: "agents", body: "Too soon", operation_id: Ecto.UUID.generate()}
    assert %{"isError" => true, "content" => [%{"text" => text}]} = mcp(from, agent, too_soon)
    assert %{"code" => "too_many_requests", "retry_after" => seconds} = Jason.decode!(text)["error"]
    assert seconds in 1..3600

    assert length(Ash.read!(Message, authorize?: false)) == count
  end

  test "an unsigned or forged request leaves nothing", %{from: from, agent: agent} do
    body = %{body: "Hi", operation_id: Ecto.UUID.generate()}
    count = length(Ash.read!(Message, authorize?: false))

    unsigned =
      conn(:post, "/api/v1/messages/agents", Jason.encode!(body))
      |> Map.put(:remote_ip, from)
      |> put_req_header("content-type", "application/json")
      |> @endpoint.call([])

    assert unsigned.status == 401
    assert http(from, agent, "agents", body, "forged").status == 401
    assert length(Ash.read!(Message, authorize?: false)) == count
  end

  defp http(from, wallet, topic, body, signature \\ "fixture-proof") do
    conn(:post, "/api/v1/messages/#{topic}", Jason.encode!(body))
    |> Map.put(:remote_ip, from)
    |> put_req_header("content-type", "application/json")
    |> put_req_header("x-siwa-signature", signature)
    |> put_req_header("x-agent-wallet-address", wallet)
    |> @endpoint.call([])
  end

  defp mcp(from, wallet, input) do
    call = %{
      "jsonrpc" => "2.0",
      "id" => 1,
      "method" => "tools/call",
      "params" => %{"name" => "messages_leave", "arguments" => %{"input" => input}}
    }

    conn(:post, "/mcp", Jason.encode!(call))
    |> Map.put(:remote_ip, from)
    |> put_req_header("content-type", "application/json")
    |> put_req_header("accept", "application/json, text/event-stream")
    |> put_req_header("x-siwa-signature", "fixture-proof")
    |> put_req_header("x-agent-wallet-address", wallet)
    |> @endpoint.call([])
    |> json()
    |> Map.fetch!("result")
  end

  defp json(conn), do: Jason.decode!(conn.resp_body)
  defp wallet, do: "0x" <> Base.encode16(:crypto.strong_rand_bytes(20), case: :lower)
end
