defmodule AshTemplateWeb.McpAgentTest do
  # The hosted MCP server at /mcp says who is calling as the agent access spec
  # (4.3) sets out, through this site's own endpoint, router and actions:
  # - an agent's signature and a connected app's token together are refused;
  # - a signature the sign-in service refuses is refused, never run as anyone;
  # - an agent's signed call runs rooms_post as that agent;
  # - anyone may read a room, and a call to a tool that needs a sign-in is refused;
  # - an operation_id reused through /mcp answers as it does over HTTP, whichever
  #   of the two each call comes through.
  # A connected app's own calls are in AshTemplateWeb.ClaudeConnectorTest. The
  # sign-in service is stubbed: it vouches for the wallet a request names when the
  # request carries the fixture proof. Each test calls from its own address, so it
  # spends its own rate budgets, not the rest of the suite's.
  use ExUnit.Case, async: false
  use ExUnitProperties

  import Plug.Conn
  import Plug.Test

  alias AshTemplate.{Accounts, Repo}
  alias AshTemplate.Actors.System
  alias AshTemplate.Rooms.Message

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

      if headers["x-siwa-signature"] == "fixture-proof" do
        wallet = headers["x-agent-wallet-address"]

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
        |> Req.Test.json(%{
          error: %{code: "http_signature_invalid", message: "Signature invalid", hint: "Sign again"}
        })
      end
    end)

    %{from: {10, :rand.uniform(250), :rand.uniform(250), :rand.uniform(250)}}
  end

  test "a signature and a token together are refused, and a token alone while connecting apps is off", %{from: from} do
    both = mcp(call("rooms_messages", %{room: "general"}), from: from, proof: wallet(), token: "a-token")
    assert both.status == 401
    assert error(both)["code"] == "ambiguous_credentials"
    assert posts() == []

    token = mcp(call("rooms_messages", %{room: "general"}), from: from, token: "a-token")
    assert token.status == 401
    assert error(token)["code"] == "delegated_access_not_enabled"
  end

  test "a signature the sign-in service refuses is refused, even for a public tool", %{from: from} do
    refused = mcp(call("rooms_messages", %{room: "general"}), from: from, proof: wallet(), signature: "forged")
    assert refused.status == 401
    assert error(refused)["code"] == "http_signature_invalid"
  end

  test "an agent's signed call posts in a room as that agent, and never as anyone else", %{from: from} do
    agent = wallet()
    key = Ecto.UUID.generate()
    posted = mcp(call("rooms_post", %{room: "general", body: "Hello", operation_id: key}), from: from, proof: agent)

    assert posted.status == 200
    assert get_resp_header(posted, "cache-control") == ["private, no-store"]
    assert %{"isError" => false, "structuredContent" => answer} = result(posted)
    assert %{"replayed" => false, "message" => %{"id" => id}} = answer

    assert [%Message{id: ^id, body: "Hello"} = message] = posts()
    assert AshTemplate.Agents.get_agent!(message.agent_id, actor: %System{}).wallet_address == agent
  end

  test "anyone may read a room, and a call to a tool that needs a sign-in is refused", %{from: from} do
    listed = mcp(%{"jsonrpc" => "2.0", "id" => 1, "method" => "tools/list"}, from: from)
    assert Enum.map(result(listed)["tools"], & &1["name"]) == ["rooms_messages"]

    read = mcp(call("rooms_messages", %{room: "general"}), from: from)
    assert read.status == 200
    assert get_resp_header(read, "cache-control") == ["private, no-store"]
    assert %{"isError" => false, "structuredContent" => %{"messages" => _}} = result(read)

    post = call("rooms_post", %{room: "general", body: "Hello", operation_id: Ecto.UUID.generate()})
    refused = mcp(post, from: from)
    assert refused.status == 401
    assert error(refused)["code"] == "agent_auth_required"

    batch = mcp(%{"_json" => [call("rooms_messages", %{room: "general"}), post]}, from: from)
    assert batch.status == 401
    assert posts() == []
  end

  property "an operation_id reused through /mcp answers as it does over HTTP, whichever way each call comes", %{from: from} do
    check all(
            text <- string(:alphanumeric, min_length: 1, max_length: 40),
            first_way <- member_of([:mcp, :http]),
            calls <-
              list_of(tuple({member_of([:mcp, :http]), member_of([:same, :other])}),
                min_length: 1,
                max_length: 5
              ),
            max_runs: 8
          ) do
      agent = paired_wallet()
      key = Ecto.UUID.generate()

      [first | answers] =
        for {way, body} <- [{first_way, :same} | calls] do
          post(way, from, agent, if(body == :same, do: text, else: text <> "x"), key)
        end

      assert {:posted, id} = first

      # The same text answers the first post; other text is refused, either way.
      for {{_way, body}, answer} <- Enum.zip(calls, answers) do
        assert answer ==
                 if(body == :same, do: {:replayed, id}, else: {:refused, "idempotency_conflict"})
      end
    end
  end

  # One post with `key`, through `way` from the address `from`, as the answer's meaning: posted, the
  # earlier post answered again, or refused with its code.
  defp post(:http, from, agent, text, key) do
    conn =
      conn(:post, "/api/v1/rooms/general/messages", Jason.encode!(%{body: text, operation_id: key}))
      |> Map.put(:remote_ip, from)
      |> put_req_header("content-type", "application/json")
      |> signed(agent, "fixture-proof")
      |> @endpoint.call([])

    case {conn.status, Jason.decode!(conn.resp_body)} do
      {201, %{"message" => %{"id" => id}}} -> {:posted, id}
      {200, %{"message" => %{"id" => id}}} -> {:replayed, id}
      {_status, %{"error" => %{"code" => code}}} -> {:refused, code}
    end
  end

  defp post(:mcp, from, agent, text, key) do
    conn = mcp(call("rooms_post", %{room: "general", body: text, operation_id: key}), from: from, proof: agent)

    case result(conn) do
      %{"isError" => false, "structuredContent" => %{"replayed" => false, "message" => %{"id" => id}}} ->
        {:posted, id}

      %{"isError" => false, "structuredContent" => %{"replayed" => true, "message" => %{"id" => id}}} ->
        {:replayed, id}

      %{"isError" => true, "content" => [%{"text" => text}]} ->
        {:refused, Jason.decode!(text)["error"]["code"]}
    end
  end

  defp mcp(body, opts) do
    conn(:post, "/mcp", Jason.encode!(body))
    |> Map.put(:remote_ip, Keyword.fetch!(opts, :from))
    |> put_req_header("content-type", "application/json")
    |> put_req_header("accept", "application/json, text/event-stream")
    |> then(&if(opts[:proof], do: signed(&1, opts[:proof], opts[:signature] || "fixture-proof"), else: &1))
    |> then(&if(opts[:token], do: put_req_header(&1, "authorization", "Bearer " <> opts[:token]), else: &1))
    |> @endpoint.call([])
  end

  defp signed(conn, wallet, signature) do
    conn
    |> put_req_header("x-siwa-signature", signature)
    |> put_req_header("x-agent-wallet-address", wallet)
  end

  defp call(name, input),
    do: %{
      "jsonrpc" => "2.0",
      "id" => 1,
      "method" => "tools/call",
      "params" => %{"name" => name, "arguments" => %{"input" => input}}
    }

  defp result(conn), do: Jason.decode!(conn.resp_body)["result"]
  defp error(conn), do: Jason.decode!(conn.resp_body)["error"]

  defp posts, do: Ash.read!(Message, authorize?: false)

  # An agent's wallet, paired with a person's account here.
  defp paired_wallet do
    did = "did:privy:mcp-" <> Ecto.UUID.generate()
    person = wallet()
    agent = wallet()
    Accounts.register_verified!(did, person, [person], actor: %System{})
    code = RegentAgents.issue_pairing_code!(actor: %RegentAgents.Person{privy_user_id: did})
    RegentAgents.pair_agent!(code.code, "Agent", :codex, actor: %RegentAgents.Agent{wallet: agent})
    agent
  end

  defp wallet, do: "0x" <> Base.encode16(:crypto.strong_rand_bytes(20), case: :lower)
end
