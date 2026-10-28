defmodule AshTemplateWeb.McpAgentTest do
  # The hosted MCP server at /mcp says who is calling as the agent access spec
  # (4.3) sets out, through this site's own endpoint, router and actions:
  # - every request carries an agent's signature or a connected app's token, never
  #   both, and a signature the sign-in service refuses is refused;
  # - an agent's signed call runs rooms_post as that agent;
  # - a query string, a page from another site, a batch, a body that is not JSON
  #   and any other method or address are refused in the site's shape, before
  #   any signature is checked;
  # - input a tool cannot take gets the code HTTP gives it;
  # - one address gets the API's 120 requests a minute;
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
    assert error(both)["code"] == "ambiguous_credentials"
    assert posts() == []

    token = mcp(call("rooms_messages", %{room: "general"}), from: from, token: "a-token")
    assert token.status == 401
    assert error(token)["code"] == "delegated_access_not_enabled"
  end

  test "a signature the sign-in service refuses is refused, even for a read", %{from: from} do
    refused =
      mcp(call("rooms_messages", %{room: "general"}),
        from: from,
        proof: wallet(),
        signature: "forged"
      )

    assert refused.status == 401
    assert error(refused)["code"] == "http_signature_invalid"
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
      assert error(refused)["code"] == "agent_auth_required"
      assert get_resp_header(refused, "www-authenticate") == []
    end

    listed = mcp(rpc("tools/list"), from: from, proof: wallet())
    assert Enum.map(result(listed)["tools"], & &1["name"]) == ["rooms_messages", "rooms_post"]

    read = mcp(call("rooms_messages", %{room: "general"}), from: from, proof: wallet())
    assert %{"isError" => false, "structuredContent" => %{"messages" => _}} = result(read)
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
      assert error(refused)["code"] == "unsupported_query"
    end

    assert posts() == []
  end

  test "a page from another site is refused before any signature is checked", %{from: from} do
    read = call("rooms_messages", %{room: "general"})

    for origin <- ["https://evil.example", "null"] do
      refused = mcp(read, from: from, origin: origin, proof: wallet(), signature: "forged")
      assert refused.status == 403
      assert error(refused)["code"] == "origin_not_allowed"
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
      mcp(%{"_json" => [call("rooms_messages", %{room: "general"}), post]},
        from: from,
        proof: agent
      )

    assert batch.status == 400
    assert error(batch)["code"] == "batch_not_supported"
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
          {"rooms_post", %{room: "general", body: "Hello"}, "invalid_message"}
        ] do
      assert %{"isError" => true, "content" => [%{"text" => text}]} =
               result(mcp(call(name, input), from: from, proof: agent))

      refute text =~ "%{"
      assert Jason.decode!(text)["error"]["code"] == code
    end

    assert posts() == []
  end

  test "only POST /mcp is served; anything else answers in the site's shape", %{from: from} do
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
      assert %{"code" => _, "message" => _, "hint" => _} = error(conn)
    end

    form =
      conn(:post, "/mcp", "jsonrpc=2.0&method=tools%2Flist")
      |> Map.put(:remote_ip, from)
      |> put_req_header("content-type", "application/x-www-form-urlencoded")
      |> put_req_header("accept", "application/json")
      |> put_req_header("x-siwa-signature", "fixture-proof")
      |> put_req_header("x-agent-wallet-address", wallet())
      |> @endpoint.call([])

    assert form.status == 415
    assert %{"code" => _, "hint" => hint} = error(form)
    assert hint =~ AshTemplateWeb.PublicDocuments.url("/docs")

    {413, _headers, body} =
      assert_error_sent(413, fn ->
        conn(:post, "/mcp", Jason.encode!(%{"padding" => String.duplicate("a", 1_100_000)}))
        |> Map.put(:remote_ip, from)
        |> put_req_header("content-type", "application/json")
        |> put_req_header("accept", "application/json")
        |> @endpoint.call([])
      end)

    assert Jason.decode!(body)["error"]["hint"] =~ AshTemplateWeb.PublicDocuments.url("/docs")
  end

  test "one address gets 120 requests a minute here, as on the API", %{from: from} do
    statuses = for _ <- 1..121, do: mcp(rpc("tools/list"), from: from).status
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
  defp error(conn), do: Jason.decode!(conn.resp_body)["error"]

  defp posts, do: Ash.read!(Message, authorize?: false)

  # An agent's wallet, paired with a person's account here.
  defp paired_wallet do
    did = "did:privy:mcp-" <> Ecto.UUID.generate()
    person = wallet()
    agent = wallet()
    Accounts.register_verified!(did, person, [person], actor: %System{})
    code = RegentAgents.issue_pairing_code!(actor: %RegentAgents.Person{privy_user_id: did})

    RegentAgents.pair_agent!(code.code, "Agent", :codex,
      actor: %RegentAgents.Agent{wallet: agent}
    )

    agent
  end

  defp wallet, do: "0x" <> Base.encode16(:crypto.strong_rand_bytes(20), case: :lower)
end
