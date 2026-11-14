defmodule AshTemplateWeb.McpAgentTest do
  # The hosted MCP server at /mcp says who is calling as the agent access spec
  # (4.3) sets out, through this site's own endpoint, router and actions:
  # - every request carries an agent's signature or a connected app's token, never
  #   both, and a signature the sign-in service refuses is refused;
  # - an agent's signed call runs rooms_post as that agent;
  # - a query string, a page from another site, a batch, a body that is not JSON
  #   and any other method or address are refused before any signature is
  #   checked;
  # - each refusal keeps its HTTP status and answers in JSON-RPC with the
  #   request's id, the site's code, message and hint as the error's data; a
  #   notification gets the status alone;
  # - a pairing that ends while a call runs turns a tool call's answer into a
  #   tool result with isError, and any other request's into a refusal;
  # - input a tool cannot take gets the code HTTP gives it;
  # - a post past the allowance is refused as HTTP refuses it, too_many_requests,
  #   with the seconds to wait;
  # - one address gets the API's 120 requests a minute, refused before its body
  #   is read with the rate-limit headers;
  # - an operation_id reused through /mcp answers as it does over HTTP, whichever
  #   of the two each call comes through.
  # A connected app's own calls are in AshTemplateWeb.ClaudeConnectorTest. The
  # sign-in service is stubbed: it vouches for the wallet a request names when the
  # request carries the fixture proof. Each test calls from its own address, so it
  # spends its own rate budgets, not the rest of the suite's.
  use ExUnit.Case, async: false
  use ExUnitProperties

  import Phoenix.ConnTest, only: [assert_error_sent: 2]
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
          error: %{
            code: "http_signature_invalid",
            message: "Signature invalid",
            hint: "Sign again"
          }
        })
      end
    end)

    %{from: {10, :rand.uniform(250), :rand.uniform(250), :rand.uniform(250)}}
  end

  test "a signature and a token together are refused, and a token alone while connecting apps is off",
       %{from: from} do
    both =
      mcp(call("rooms_messages", %{room: "general"}),
        from: from,
        proof: wallet(),
        token: "a-token"
      )

    assert both.status == 401
    assert refusal(both)["code"] == "ambiguous_credentials"
    assert posts() == []

    token = mcp(call("rooms_messages", %{room: "general"}), from: from, token: "a-token")
    assert token.status == 401
    assert refusal(token)["code"] == "delegated_access_not_enabled"
  end

  test "a signature the sign-in service refuses is refused, even for a read", %{from: from} do
    refused =
      mcp(call("rooms_messages", %{room: "general"}),
        from: from,
        proof: wallet(),
        signature: "forged"
      )

    assert refused.status == 401
    assert refusal(refused)["code"] == "http_signature_invalid"
  end

  test "an agent's signed call posts in a room as that agent, and never as anyone else", %{
    from: from
  } do
    agent = wallet()
    key = Ecto.UUID.generate()

    posted =
      mcp(call("rooms_post", %{room: "general", body: "Hello", operation_id: key}),
        from: from,
        proof: agent
      )

    assert posted.status == 200
    assert get_resp_header(posted, "cache-control") == ["private, no-store"]
    assert %{"isError" => false, "structuredContent" => answer} = result(posted)
    assert %{"replayed" => false, "message" => %{"id" => id}} = answer

    assert [%Message{id: ^id, body: "Hello"} = message] = posts()

    assert AshTemplate.Agents.get_agent!(message.agent_id, actor: %System{}).wallet_address ==
             agent
  end

  test "every request needs a signature or a token, from the first one on", %{from: from} do
    initialize = %{
      "jsonrpc" => "2.0",
      "id" => 1,
      "method" => "initialize",
      "params" => %{
        "protocolVersion" => "2025-06-18",
        "capabilities" => %{},
        "clientInfo" => %{"name" => "t", "version" => "1"}
      }
    }

    for body <- [initialize, rpc("tools/list"), call("rooms_messages", %{room: "general"})] do
      refused = mcp(body, from: from)
      assert refused.status == 401
      assert refusal(refused)["code"] == "agent_auth_required"
      assert get_resp_header(refused, "www-authenticate") == []
    end

    listed = mcp(rpc("tools/list"), from: from, proof: wallet())

    assert Enum.map(result(listed)["tools"], & &1["name"]) ==
             ["messages_leave", "rooms_messages", "rooms_post"]

    read = mcp(call("rooms_messages", %{room: "general"}), from: from, proof: wallet())
    assert %{"isError" => false, "structuredContent" => %{"messages" => _}} = result(read)
  end

  test "a refusal answers with the request's own id, none when it can't be read, and a notification with no body",
       %{from: from} do
    read = call("rooms_messages", %{room: "general"})

    for id <- ["call-7", 42, 0] do
      refused = mcp(%{read | "id" => id}, from: from)
      assert refused.status == 401
      assert refusal(refused, id)["code"] == "agent_auth_required"
      assert Jason.decode!(refused.resp_body)["error"]["code"] == -31_000
    end

    for id <- [nil, 1.5, %{"n" => 1}] do
      refused = mcp(%{read | "id" => id}, from: from)
      assert refused.status == 401
      assert refusal(refused, nil)["code"] == "agent_auth_required"
    end

    notification = mcp(%{"jsonrpc" => "2.0", "method" => "notifications/initialized"}, from: from)
    assert notification.status == 401
    assert notification.resp_body == ""

    forged =
      mcp(%{"jsonrpc" => "2.0", "method" => "notifications/initialized"},
        from: from,
        proof: wallet(),
        signature: "forged"
      )

    assert forged.status == 401
    assert forged.resp_body == ""
  end

  test "a refusal's visit line names the site's code", %{from: from} do
    # Visit lines are info; the suite's logger keeps warnings and above.
    Logger.put_module_level(AshTemplateWeb.VisitLog, :info)
    :ok = :logger.add_handler(:mcp_agent_test_visits, __MODULE__, %{config: %{test: self()}})

    on_exit(fn ->
      :logger.remove_handler(:mcp_agent_test_visits)
      Logger.delete_module_level(AshTemplateWeb.VisitLog)
    end)

    mcp(rpc("tools/list"), from: from, proof: wallet(), signature: "forged")

    assert_receive {:visit, %{name: "tool.call", outcome: "http_signature_invalid"}}
  end

  test "a pairing that ends while the call runs: a tool call answers a tool result with isError, any other request a refusal",
       %{from: from} do
    handler = "mcp-agent-test-unpair"
    :ok = :telemetry.attach(handler, [:ash_template, :mcp, :auth], &__MODULE__.unpair/4, nil)
    on_exit(fn -> :telemetry.detach(handler) end)

    {agent, pairing, did} = pair()
    Process.put(:unpair_when_accepted, {pairing, did})
    read = mcp(call("rooms_messages", %{room: "general"}), from: from, proof: agent)

    assert read.status == 200

    assert %{
             "jsonrpc" => "2.0",
             "id" => 1,
             "result" => %{
               "isError" => true,
               "content" => [%{"type" => "text", "text" => text}],
               "resultType" => "complete"
             }
           } = Jason.decode!(read.resp_body)

    assert Jason.decode!(text)["error"]["code"] == "agent_not_paired"

    {agent, pairing, did} = pair()
    Process.put(:unpair_when_accepted, {pairing, did})
    listed = mcp(rpc("tools/list"), from: from, proof: agent)

    assert listed.status == 403
    assert refusal(listed)["code"] == "agent_not_paired"
    assert get_resp_header(listed, "cache-control") == ["private, no-store"]

    {agent, _pairing, _did} = pair()
    kept = mcp(call("rooms_messages", %{room: "general"}), from: from, proof: agent)
    assert %{"isError" => false, "structuredContent" => %{"messages" => _}} = result(kept)
  end

  test "a query string is refused for every caller before anything else runs", %{from: from} do
    post =
      call("rooms_post", %{room: "general", body: "Hello", operation_id: Ecto.UUID.generate()})

    for opts <- [
          [],
          [proof: wallet()],
          [proof: wallet(), signature: "forged"],
          [token: "a-token"]
        ] do
      refused = mcp(post, [from: from, query: "room=general"] ++ opts)
      assert refused.status == 400
      assert refusal(refused)["code"] == "unsupported_query"
    end

    assert posts() == []
  end

  test "a page from another site is refused before any signature is checked", %{from: from} do
    read = call("rooms_messages", %{room: "general"})

    for origin <- ["https://evil.example", "null"] do
      refused = mcp(read, from: from, origin: origin, proof: wallet(), signature: "forged")
      assert refused.status == 403
      assert refusal(refused)["code"] == "origin_not_allowed"
    end

    own = mcp(read, from: from, origin: AshTemplateWeb.PublicDocuments.url(""), proof: wallet())
    assert %{"isError" => false} = result(own)

    none = mcp(read, from: from, proof: wallet())
    assert %{"isError" => false} = result(none)
  end

  test "one call a request: a batch is refused, and the 2026-07-28 profile reads and posts", %{
    from: from
  } do
    agent = wallet()

    post =
      call("rooms_post", %{room: "general", body: "Hello", operation_id: Ecto.UUID.generate()})

    batch =
      mcp([call("rooms_messages", %{room: "general"}), post],
        from: from,
        proof: agent
      )

    assert batch.status == 400
    assert refusal(batch, nil)["code"] == "batch_not_supported"
    assert posts() == []

    read =
      mcp(profile(call("rooms_messages", %{room: "general"})),
        from: from,
        proof: agent,
        profile: "rooms_messages"
      )

    assert %{"isError" => false, "structuredContent" => %{"messages" => _}} = result(read)

    posted = mcp(profile(post), from: from, proof: agent, profile: "rooms_post")
    assert %{"isError" => false, "structuredContent" => %{"replayed" => false}} = result(posted)
    assert [%Message{body: "Hello"}] = posts()
  end

  test "input a tool cannot take is refused with the HTTP code, never a placeholder", %{
    from: from
  } do
    agent = wallet()

    for {name, input, code} <- [
          {"rooms_messages", %{room: "general", limit: 0}, "invalid_limit"},
          {"rooms_messages", %{room: "general", limit: 51}, "invalid_limit"},
          {"rooms_messages", %{room: "general", author_kind: "robot"}, "invalid_author_kind"},
          {"rooms_post",
           %{
             room: "general",
             body: String.duplicate("a", 2001),
             operation_id: Ecto.UUID.generate()
           }, "invalid_message"},
          {"rooms_post", %{room: "general", body: "Hello", operation_id: "not-a-uuid"},
           "invalid_message"},
          {"rooms_post", %{room: "general", body: "Hello"}, "invalid_message"},
          {"rooms_messages", %{room: "general", after: 5}, "invalid_cursor"},
          {"rooms_messages", %{room: "general", foo: 1}, "invalid_input"},
          {"rooms_messages", "general", "invalid_input"},
          {"rooms_messages", %{}, "room_not_found"}
        ] do
      assert %{"isError" => true, "content" => [%{"text" => text}]} =
               result(mcp(call(name, input), from: from, proof: agent))

      refute text =~ "%{"
      assert Jason.decode!(text)["error"]["code"] == code
    end

    assert posts() == []
  end

  test "a post past the allowance says too many requests and the seconds to wait", %{
    from: from
  } do
    wallet = wallet()
    agent = AshTemplate.Agents.sign_in_agent!(wallet, actor: %System{})
    limit = Application.fetch_env!(:ash_template, :limits)[:room_post][:limit]
    for _ <- 1..limit, do: :ok = AshTemplate.Limits.spend(:room_post, {:agent, agent.id})

    post =
      call("rooms_post", %{room: "general", body: "Hello", operation_id: Ecto.UUID.generate()})

    assert %{"isError" => true, "content" => [%{"text" => text}]} =
             result(mcp(post, from: from, proof: wallet))

    assert %{"error" => %{"code" => "too_many_requests", "retry_after" => seconds}} =
             Jason.decode!(text)

    assert seconds in 1..60
    assert posts() == []
  end

  test "only POST /mcp is served; anything else is refused in JSON-RPC", %{from: from} do
    for {method, path} <- [
          {:options, "/mcp"},
          {:put, "/mcp"},
          {:get, "/mcp"},
          {:post, "/mcp/anything"}
        ] do
      conn =
        conn(method, path, "{}")
        |> Map.put(:remote_ip, from)
        |> put_req_header("content-type", "application/json")
        |> put_req_header("accept", "application/json")
        |> @endpoint.call([])

      assert conn.status in [404, 405]
      assert %{"code" => _, "message" => _, "hint" => _} = refusal(conn, nil)
    end

    slash =
      conn(:post, "/mcp/", Jason.encode!(rpc("tools/list")))
      |> Map.put(:remote_ip, from)
      |> put_req_header("content-type", "application/json")
      |> @endpoint.call([])

    assert slash.status == 404
    assert %{"code" => "not_found"} = refusal(slash, nil)

    form =
      conn(:post, "/mcp", "jsonrpc=2.0&id=7&method=tools%2Flist")
      |> Map.put(:remote_ip, from)
      |> put_req_header("content-type", "application/x-www-form-urlencoded")
      |> put_req_header("accept", "application/json")
      |> put_req_header("x-siwa-signature", "fixture-proof")
      |> put_req_header("x-agent-wallet-address", wallet())
      |> @endpoint.call([])

    assert form.status == 415
    assert %{"code" => _, "hint" => hint} = refusal(form, nil)
    assert hint =~ AshTemplateWeb.PublicDocuments.url("/docs")

    {413, _headers, body} =
      assert_error_sent(413, fn ->
        conn(:post, "/mcp", Jason.encode!(%{"padding" => String.duplicate("a", 1_100_000)}))
        |> Map.put(:remote_ip, from)
        |> put_req_header("content-type", "application/json")
        |> put_req_header("accept", "application/json")
        |> @endpoint.call([])
      end)

    assert %{"jsonrpc" => "2.0", "error" => %{"data" => %{"hint" => hint}}} = answer = Jason.decode!(body)
    refute is_map_key(answer, "id")
    assert hint =~ AshTemplateWeb.PublicDocuments.url("/docs")

    {400, _headers, body} =
      assert_error_sent(400, fn ->
        conn(:post, "/mcp", ~s({"jsonrpc": "2.0", "id": 1, "method": ))
        |> Map.put(:remote_ip, from)
        |> put_req_header("content-type", "application/json")
        |> @endpoint.call([])
      end)

    assert %{"jsonrpc" => "2.0", "error" => %{"code" => -32_700}} = answer = Jason.decode!(body)
    refute is_map_key(answer, "id")
  end

  test "a GET for an event stream is answered 405, and a body that is not JSON 415, whatever it accepts",
       %{from: from} do
    stream =
      conn(:get, "/mcp")
      |> Map.put(:remote_ip, from)
      |> put_req_header("accept", "text/event-stream")
      |> @endpoint.call([])

    assert stream.status == 405
    assert get_resp_header(stream, "allow") == ["POST"]
    assert %{"code" => "method_not_allowed"} = refusal(stream, nil)

    form =
      conn(:post, "/mcp", "jsonrpc=2.0&method=tools%2Flist")
      |> Map.put(:remote_ip, from)
      |> put_req_header("content-type", "application/x-www-form-urlencoded")
      |> put_req_header("accept", "text/event-stream")
      |> @endpoint.call([])

    assert form.status == 415
    assert %{"code" => "unsupported_media_type"} = refusal(form, nil)
  end

  test "one address gets 120 requests a minute here, as on the API, refused before the body is read",
       %{from: from} do
    answers = for _ <- 1..121, do: mcp(rpc("tools/list"), from: from)
    assert answers |> Enum.take(120) |> Enum.map(& &1.status) |> Enum.uniq() == [401]

    limited = List.last(answers)
    assert limited.status == 429
    assert [seconds] = get_resp_header(limited, "retry-after")
    assert [~s("mcp_address";q=120;w=60)] = get_resp_header(limited, "ratelimit-policy")
    assert [~s("mcp_address";r=0;) <> _] = get_resp_header(limited, "ratelimit")

    assert %{"code" => "too_many_requests", "retry_after" => retry_after} =
             refusal(limited, nil)

    assert Integer.to_string(retry_after) == seconds
  end

  test "a token that isn't checked spends the same 120 from its address, each request once",
       %{from: from} do
    statuses =
      for n <- 1..121,
          do:
            mcp(rpc("tools/list"), from: from, token: if(rem(n, 2) == 0, do: "not-a-token")).status

    assert Enum.take(statuses, 120) |> Enum.uniq() == [401]
    assert List.last(statuses) == 429
  end

  property "an operation_id reused through /mcp answers as it does over HTTP, whichever way each call comes",
           %{from: from} do
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
      conn(
        :post,
        "/api/v1/rooms/general/messages",
        Jason.encode!(%{body: text, operation_id: key})
      )
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
    conn =
      mcp(call("rooms_post", %{room: "general", body: text, operation_id: key}),
        from: from,
        proof: agent
      )

    case result(conn) do
      %{
        "isError" => false,
        "structuredContent" => %{"replayed" => false, "message" => %{"id" => id}}
      } ->
        {:posted, id}

      %{
        "isError" => false,
        "structuredContent" => %{"replayed" => true, "message" => %{"id" => id}}
      } ->
        {:replayed, id}

      %{"isError" => true, "content" => [%{"text" => text}]} ->
        {:refused, Jason.decode!(text)["error"]["code"]}
    end
  end

  defp mcp(body, opts) do
    path = if opts[:query], do: "/mcp?" <> opts[:query], else: "/mcp"

    conn(:post, path, Jason.encode!(body))
    |> Map.put(:remote_ip, Keyword.fetch!(opts, :from))
    |> then(&if(opts[:origin], do: put_req_header(&1, "origin", opts[:origin]), else: &1))
    |> then(&if(opts[:profile], do: profile_headers(&1, body, opts[:profile]), else: &1))
    |> put_req_header("content-type", "application/json")
    |> put_req_header("accept", "application/json, text/event-stream")
    |> then(
      &if(opts[:proof],
        do: signed(&1, opts[:proof], opts[:signature] || "fixture-proof"),
        else: &1
      )
    )
    |> then(
      &if(opts[:token],
        do: put_req_header(&1, "authorization", "Bearer " <> opts[:token]),
        else: &1
      )
    )
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

  defp rpc(method), do: %{"jsonrpc" => "2.0", "id" => 1, "method" => method}

  # A call as the 2026-07-28 profile sends it: its version and capabilities in
  # `_meta`, and the same version, method and tool in the headers.
  defp profile(%{"params" => params} = call) do
    meta = %{
      "io.modelcontextprotocol/protocolVersion" => "2026-07-28",
      "io.modelcontextprotocol/clientCapabilities" => %{}
    }

    %{call | "params" => Map.put(params, "_meta", meta)}
  end

  defp profile_headers(conn, %{"method" => method}, name) do
    conn
    |> put_req_header("mcp-protocol-version", "2026-07-28")
    |> put_req_header("mcp-method", method)
    |> put_req_header("mcp-name", name)
  end

  defp result(conn), do: Jason.decode!(conn.resp_body)["result"]

  # The site's refusal: the `data` of the JSON-RPC error that answered, with the
  # request's `id`, or none when `id` is nil.
  defp refusal(conn, id \\ 1) do
    assert %{"jsonrpc" => "2.0", "error" => %{"message" => message, "data" => data}} =
             answer = Jason.decode!(conn.resp_body)

    assert Map.fetch(answer, "id") == if(is_nil(id), do: :error, else: {:ok, id})
    assert message == data["message"]
    data
  end

  defp posts, do: Ash.read!(Message, authorize?: false)

  # An agent's wallet, paired with a person's account here.
  defp paired_wallet, do: elem(pair(), 0)

  defp pair do
    did = "did:privy:mcp-" <> Ecto.UUID.generate()
    person = wallet()
    agent = wallet()
    Accounts.register_verified!(did, person, [person], actor: %System{})
    code = RegentAgents.issue_pairing_code!(actor: %RegentAgents.Person{privy_user_id: did})

    pairing =
      RegentAgents.pair_agent!(code.code, "Agent", :codex,
        actor: %RegentAgents.Agent{wallet: agent}
      )

    {agent, pairing, did}
  end

  # Ends the pairing the test put in the process, once, as the call it signed is
  # let in; the request runs in the test's process.
  def unpair(_event, _measurements, %{outcome: :accepted}, _config) do
    with {pairing, did} <- Process.delete(:unpair_when_accepted),
         do: :ok = RegentAgents.unpair_agent(pairing, actor: %RegentAgents.Person{privy_user_id: did})
  end

  def unpair(_event, _measurements, _metadata, _config), do: :ok

  # A logger handler that sends each visit line to the test that added it.
  def log(%{meta: %{event: event}}, %{config: %{test: test}}), do: send(test, {:visit, event})
  def log(_event, _config), do: :ok

  defp wallet, do: "0x" <> Base.encode16(:crypto.strong_rand_bytes(20), case: :lower)
end
