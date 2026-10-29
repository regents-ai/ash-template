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
  # - each notes tool answers and refuses as HTTP does; a UUID already another
  #   note's id, and a note saved after the agent's pairing ended, are refused
  #   the same way on both;
  # - each rooms and mutes tool answers and refuses as HTTP does, and over HTTP the
  #   address alone names the room, message or mute: a body never chooses another,
  #   and a removal takes no body at all;
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
  alias AshTemplate.Agents.NotPaired
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

    assert Enum.map(result(listed)["tools"], & &1["name"]) ==
             Enum.sort(Enum.map(AshTemplateWeb.Capabilities.hosted_tools(), &Atom.to_string/1)) --
               ~w(register_identity get_identity pair_identity check_in)

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
      mcp([call("rooms_messages", %{room: "general"}), post],
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

  test "requests with a token share 600 a minute from one address, Claude's servers among them",
       %{from: from} do
    statuses =
      for _ <- 1..601, do: mcp(rpc("tools/list"), from: from, token: "not-a-token").status

    assert Enum.take(statuses, 600) |> Enum.uniq() == [401]
    assert List.last(statuses) == 429
    assert mcp(rpc("tools/list"), from: from).status == 401
  end

  test "each read answers through /mcp exactly as over HTTP, from the same action", %{from: from} do
    agent = paired_wallet()
    other = paired_wallet()

    assert {:posted, id} =
             post(:http, from, agent, "Hello from the parity walk", Ecto.UUID.generate())

    assert {:posted, muted} = post(:http, from, other, "Someone to mute", Ecto.UUID.generate())
    assert http(:post, "/api/v1/mutes", %{message_id: muted}, from, agent).status == 200

    %{"message" => %{"via_agent" => %{"id" => agent_id}}} =
      Jason.decode!(http(:get, "/api/v1/rooms/general/messages/#{id}", nil, from, nil).resp_body)

    for {name, input, method, path, body, signer} <- [
          {"health", %{}, :get, "/api/v1/health", nil, nil},
          {"about", %{}, :get, "/api/v1/about", nil, nil},
          {"docs", %{}, :get, "/api/v1/docs", nil, nil},
          {"siwa_help", %{}, :get, "/api/v1/siwa/help", nil, nil},
          {"rooms_list", %{}, :get, "/api/v1/rooms", nil, nil},
          {"rooms_message", %{room: "general", id: id}, :get,
           "/api/v1/rooms/general/messages/#{id}", nil, nil},
          {"agents_get", %{id: agent_id}, :get, "/api/v1/agents/#{agent_id}", nil, nil},
          {"agents_profile", %{}, :get, "/api/v1/agents/me", nil, agent},
          {"rooms_search", %{text: "parity walk"}, :post, "/api/v1/rooms/search",
           %{text: "parity walk"}, agent},
          {"mutes_list", %{}, :get, "/api/v1/mutes", nil, agent},
          {"account_balances", %{}, :get, "/api/v1/account/balances", nil, agent},
          {"account_credits_history", %{}, :post, "/api/v1/account/credits/history", %{}, agent},
          {"account_points", %{}, :get, "/api/v1/account/points", nil, agent},
          {"activity_list", %{}, :post, "/api/v1/activity", %{}, agent}
        ] do
      over_http = http(method, path, body, from, signer)
      assert over_http.status == 200, "#{name} over HTTP answered #{over_http.resp_body}"

      assert %{"isError" => false, "structuredContent" => answer} =
               result(mcp(call(name, input), from: from, proof: signer || agent))

      assert answer == Jason.decode!(over_http.resp_body), name
    end

    assert %{"mutes" => [%{"name" => _}]} =
             Jason.decode!(http(:get, "/api/v1/mutes", nil, from, agent).resp_body)
  end

  test "each read refuses through /mcp with the code and words HTTP gives", %{from: from} do
    unpaired = wallet()
    agent = paired_wallet()
    missing = Ecto.UUID.generate()

    for {name, input, method, path, body, signer} <- [
          {"mutes_list", %{}, :get, "/api/v1/mutes", nil, unpaired},
          {"account_balances", %{}, :get, "/api/v1/account/balances", nil, unpaired},
          {"account_points", %{}, :get, "/api/v1/account/points", nil, unpaired},
          {"activity_list", %{}, :post, "/api/v1/activity", %{}, unpaired},
          {"rooms_search", %{text: "hello"}, :post, "/api/v1/rooms/search", %{text: "hello"},
           unpaired},
          {"rooms_search", %{text: "a"}, :post, "/api/v1/rooms/search", %{text: "a"}, agent},
          {"agents_get", %{id: missing}, :get, "/api/v1/agents/#{missing}", nil, agent},
          {"rooms_message", %{room: "general", id: missing}, :get,
           "/api/v1/rooms/general/messages/#{missing}", nil, agent},
          {"rooms_message", %{room: "nowhere", id: missing}, :get,
           "/api/v1/rooms/nowhere/messages/#{missing}", nil, agent},
          {"sites_tools", %{site: "nowhere"}, :get, "/api/v1/sites/nowhere/tools", nil, agent},
          {"activity_list", %{after: "not-a-cursor"}, :post, "/api/v1/activity",
           %{after: "not-a-cursor"}, agent},
          {"activity_list", %{after: 5}, :post, "/api/v1/activity", %{after: 5}, agent},
          {"account_credits_history", %{after: "not-a-cursor"}, :post,
           "/api/v1/account/credits/history", %{after: "not-a-cursor"}, agent}
        ] do
      %{"error" => over_http} = Jason.decode!(http(method, path, body, from, signer).resp_body)

      assert %{"isError" => true, "content" => [%{"text" => text}]} =
               result(mcp(call(name, input), from: from, proof: signer))

      assert Jason.decode!(text)["error"] == over_http, "#{name} #{inspect(input)}"
    end

    # Input sent to a read that takes none is refused as the browser tools refuse it.
    assert %{"isError" => true, "content" => [%{"text" => text}]} =
             result(mcp(call("mutes_list", %{everyone: true}), from: from, proof: agent))

    assert Jason.decode!(text)["error"]["code"] == "invalid_request"
  end

  test "each notes tool answers through /mcp as HTTP answers, and HTTP reads back what it changed",
       %{from: from} do
    agent = paired_wallet()

    # A new note, then the same operation_id again over HTTP: the first note, saved once.
    key = Ecto.UUID.generate()

    assert %{"isError" => false, "structuredContent" => %{"replayed" => false, "note" => made}} =
             result(
               mcp(call("notes_create", %{title: "Parity", body: "A walk", operation_id: key}),
                 from: from,
                 proof: agent
               )
             )

    assert made["id"] == key
    assert read_note(from, agent, key) == made

    again =
      http(
        :post,
        "/api/v1/notes",
        %{title: "Parity", body: "A walk", operation_id: key},
        from,
        agent
      )

    assert again.status == 200
    assert Jason.decode!(again.resp_body) == %{"note" => made}

    # Reads: the same answer both ways.
    for {name, input, method, path, body} <- [
          {"notes_list", %{}, :get, "/api/v1/notes", nil},
          {"notes_get", %{id: key}, :get, "/api/v1/notes/#{key}", nil},
          {"notes_search", %{text: "walk"}, :post, "/api/v1/notes/search", %{text: "walk"}},
          {"notes_pin_price", %{id: key}, :get, "/api/v1/notes/#{key}/pin-price", nil}
        ] do
      over_http = http(method, path, body, from, agent)
      assert over_http.status == 200, "#{name} over HTTP answered #{over_http.resp_body}"

      assert %{"isError" => false, "structuredContent" => answer} =
               result(mcp(call(name, input), from: from, proof: agent))

      assert answer == Jason.decode!(over_http.resp_body), name
    end

    # A chosen label rated through /mcp; HTTP reads the rating on the note.
    label = label(key, :answered)

    assert %{"isError" => false, "structuredContent" => rated} =
             result(
               mcp(call("notes_rate_label", %{id: label, report: "fits"}),
                 from: from,
                 proof: agent
               )
             )

    assert rated == %{"label" => %{"id" => label, "rating" => "fits"}}
    assert read_note(from, agent, key)["label"]["rating"] == "fits"

    # The address names the label: an id in the body never chooses another.
    second = Ecto.UUID.generate()

    assert http(:post, "/api/v1/notes", %{title: "Second", operation_id: second}, from, agent).status ==
             201

    unrated = label(second, :answered)

    rerated =
      http(
        :post,
        "/api/v1/note-labels/#{unrated}/report",
        %{id: label, report: "does_not_fit"},
        from,
        agent
      )

    assert Jason.decode!(rerated.resp_body) == %{
             "label" => %{"id" => unrated, "rating" => "does_not_fit"}
           },
           rerated.resp_body

    # Changes: each answers the note HTTP then reads.
    for {name, input} <- [
          {"notes_archive", %{id: key}},
          {"notes_unarchive", %{id: key}},
          {"notes_unpin", %{id: key}},
          {"notes_edit", %{id: key, title: "Parity, edited"}}
        ] do
      assert %{"isError" => false, "structuredContent" => %{"note" => note}} =
               result(mcp(call(name, input), from: from, proof: agent))

      assert note == read_note(from, agent, key), name
    end

    assert %{"title" => "Parity, edited", "body" => "A walk"} = read_note(from, agent, key)

    # Text sent empty clears it, either way; an id in the body never chooses another note.
    assert %{"isError" => false, "structuredContent" => %{"note" => %{"body" => nil}}} =
             result(mcp(call("notes_edit", %{id: key, body: nil}), from: from, proof: agent))

    elsewhere = Ecto.UUID.generate()

    assert http(
             :post,
             "/api/v1/notes",
             %{title: "Elsewhere", operation_id: elsewhere},
             from,
             agent
           ).status ==
             201

    cleared =
      http(
        :patch,
        "/api/v1/notes/#{key}",
        %{id: elsewhere, title: "Parity", body: nil},
        from,
        agent
      )

    assert cleared.status == 200, cleared.resp_body

    assert %{"id" => ^key, "title" => "Parity", "body" => nil} =
             Jason.decode!(cleared.resp_body)["note"]

    assert %{"title" => "Elsewhere"} = read_note(from, agent, elsewhere)

    # Deleting answers the same way both ways, and the note is gone.
    other = Ecto.UUID.generate()

    assert http(:post, "/api/v1/notes", %{title: "Other", operation_id: other}, from, agent).status ==
             201

    assert %{"isError" => false, "structuredContent" => deleted} =
             result(mcp(call("notes_delete", %{id: key}), from: from, proof: agent))

    over_http = http(:delete, "/api/v1/notes/#{other}", nil, from, agent)
    assert deleted == %{"deleted" => true, "id" => key}
    assert Jason.decode!(over_http.resp_body) == %{"deleted" => true, "id" => other}
    assert http(:get, "/api/v1/notes/#{key}", nil, from, agent).status == 404
  end

  test "each notes tool refuses through /mcp with the code and words HTTP gives", %{from: from} do
    unpaired = wallet()
    agent = paired_wallet()
    missing = Ecto.UUID.generate()
    key = Ecto.UUID.generate()

    assert http(:post, "/api/v1/notes", %{title: "Mine", operation_id: key}, from, agent).status ==
             201

    pending = label(key, :pending)
    saved = saved(key)

    for {name, input, method, path, body, signer} <- [
          {"notes_list", %{}, :get, "/api/v1/notes", nil, unpaired},
          {"notes_get", %{id: key}, :get, "/api/v1/notes/#{key}", nil, unpaired},
          {"notes_get", %{id: missing}, :get, "/api/v1/notes/#{missing}", nil, agent},
          {"notes_get", %{id: "not-a-uuid"}, :get, "/api/v1/notes/not-a-uuid", nil, agent},
          {"notes_search", %{text: "a"}, :post, "/api/v1/notes/search", %{text: "a"}, agent},
          {"notes_create", %{title: "", operation_id: Ecto.UUID.generate()}, :post,
           "/api/v1/notes", %{title: "", operation_id: Ecto.UUID.generate()}, agent},
          {"notes_create", %{title: "No key"}, :post, "/api/v1/notes", %{title: "No key"}, agent},
          {"notes_edit", %{id: key, title: String.duplicate("a", 121)}, :patch,
           "/api/v1/notes/#{key}", %{title: String.duplicate("a", 121)}, agent},
          {"notes_edit", %{id: key}, :patch, "/api/v1/notes/#{key}", %{}, agent},
          {"notes_edit", %{id: missing, title: "Gone"}, :patch, "/api/v1/notes/#{missing}",
           %{title: "Gone"}, agent},
          {"notes_delete", %{id: missing}, :delete, "/api/v1/notes/#{missing}", nil, agent},
          {"notes_pin_price", %{id: missing}, :get, "/api/v1/notes/#{missing}/pin-price", nil,
           agent},
          {"notes_unpin", %{id: missing}, :post, "/api/v1/notes/#{missing}/unpin", %{}, agent},
          {"notes_archive", %{id: missing}, :post, "/api/v1/notes/#{missing}/archive", %{},
           agent},
          {"notes_unarchive", %{id: missing}, :post, "/api/v1/notes/#{missing}/unarchive", %{},
           agent},
          {"notes_rate_label", %{id: missing, report: "fits"}, :post,
           "/api/v1/note-labels/#{missing}/report", %{report: "fits"}, agent},
          {"notes_rate_label", %{id: pending, report: "fits"}, :post,
           "/api/v1/note-labels/#{pending}/report", %{report: "fits"}, agent},
          {"notes_rate_label", %{id: pending, report: "maybe"}, :post,
           "/api/v1/note-labels/#{pending}/report", %{report: "maybe"}, agent}
        ] do
      over_http = http(method, path, body, from, signer)
      %{"error" => refused} = Jason.decode!(over_http.resp_body)

      assert %{"isError" => true, "content" => [%{"text" => text}]} =
               result(mcp(call(name, input), from: from, proof: signer))

      assert Jason.decode!(text)["error"] == refused, "#{name} #{inspect(input)}"
    end

    # No refused edit saved the note again.
    assert saved(key) == saved

    # A reused operation_id: other text is a conflict, and after a delete the note is named gone.
    assert {409, %{"code" => "idempotency_conflict"}} =
             refused_both_ways(from, agent, "Other", key)

    assert http(:delete, "/api/v1/notes/#{key}", nil, from, agent).status == 200

    assert {410, %{"code" => "note_removed", "id" => ^key}} =
             refused_both_ways(from, agent, "Mine", key)
  end

  test "a UUID that is already another note's id is refused as a reused operation_id, saying nothing of that note",
       %{from: from} do
    [agent, same_person] = paired_wallets(2)
    key = Ecto.UUID.generate()

    assert http(:post, "/api/v1/notes", %{title: "First", operation_id: key}, from, agent).status ==
             201

    # Another agent of the same person, and an agent of another person, send the key.
    for other <- [same_person, paired_wallet()] do
      assert {409, refused} = refused_both_ways(from, other, "First", key)
      assert Map.keys(refused) == ["code", "hint", "message"]
      assert refused["code"] == "idempotency_conflict"
    end

    assert [%{id: ^key}] = Ash.read!(AshTemplate.Notes.Note, authorize?: false) |> mine(key)

    assert [_first] =
             AshTemplate.Agents.Operation
             |> Ash.read!(authorize?: false)
             |> Enum.filter(&(&1.operation_key == key))
  end

  test "a note an agent saves after its pairing ended is refused as agent_not_paired, in the words HTTP gives",
       %{from: from} do
    did = "did:privy:mcp-" <> Ecto.UUID.generate()
    person = wallet()
    account = Accounts.register_verified!(did, person, [person], actor: %System{})
    owner = %RegentAgents.Person{privy_user_id: did}
    agent = wallet()

    pairing =
      RegentAgents.pair_agent!(
        RegentAgents.issue_pairing_code!(actor: owner).code,
        "Agent",
        :codex,
        actor: %RegentAgents.Agent{wallet: agent}
      )

    # The agent as its signed request was let in, then the person unpairs it.
    {:ok, active} = RegentAgents.Authority.resolve(Repo, agent)

    let_in =
      AshTemplate.Actors.Agent.paired(
        AshTemplate.Agents.sign_in_agent!(agent, actor: %System{}),
        account,
        active
      )

    assert :ok = RegentAgents.unpair_agent(pairing, actor: owner)
    key = Ecto.UUID.generate()

    assert {:error,
            %Ash.Error.Forbidden{errors: [%NotPaired{code: "agent_not_paired"} = refused]}} =
             AshTemplate.Notes.notes_create(%{title: "Late", operation_id: key}, actor: let_in)

    assert Ash.read!(AshTemplate.Notes.Note, authorize?: false) |> mine(key) == []

    # Each surface answers it as an agent no person paired.
    %{"error" => over_http} =
      Jason.decode!(http(:get, "/api/v1/notes", nil, from, wallet()).resp_body)

    assert over_http["code"] == "agent_not_paired"
    assert Jason.decode!(AshAi.ToToolError.to_tool_error(refused))["error"] == over_http
  end

  test "each rooms and mutes tool answers through /mcp as HTTP answers, and the address alone names the record",
       %{from: from} do
    agent = paired_wallet()
    name = "Parity #{:erlang.unique_integer([:positive])}"

    # A new room, then its name again over HTTP: the same room, started once.
    assert %{"isError" => false, "structuredContent" => %{"replayed" => false, "room" => room}} =
             result(
               mcp(call("rooms_create", %{name: name, topic: "First"}), from: from, proof: agent)
             )

    slug = room["slug"]
    again = http(:post, "/api/v1/rooms", %{name: name, topic: "First"}, from, agent)
    assert again.status == 200
    assert Jason.decode!(again.resp_body) == %{"room" => room}

    # The topic through /mcp; over HTTP a room in the body never chooses another.
    general = listed_room(from, "general")

    assert %{
             "isError" => false,
             "structuredContent" => %{"room" => %{"topic" => "Second"} = topped}
           } =
             result(
               mcp(call("rooms_topic", %{room: slug, topic: "Second"}), from: from, proof: agent)
             )

    assert listed_room(from, slug) == topped

    retopped =
      http(:patch, "/api/v1/rooms/#{slug}", %{room: "general", topic: "Third"}, from, agent)

    assert Jason.decode!(retopped.resp_body) == %{"room" => %{topped | "topic" => "Third"}}
    assert listed_room(from, "general") == general

    mine = said(from, agent, slug, "Mine")
    kept = said(from, agent, slug, "Kept")
    theirs = said(from, paired_wallet(), slug, "Theirs")

    # An edit through /mcp reads back over HTTP; an id in the body never chooses another message.
    assert %{"isError" => false, "structuredContent" => %{"message" => edited}} =
             result(
               mcp(call("rooms_edit", %{room: slug, id: mine, body: "Mine, edited"}),
                 from: from,
                 proof: agent
               )
             )

    assert %{"body" => "Mine, edited"} = edited
    assert read_message(from, slug, mine) == edited

    reedited =
      http(
        :patch,
        "/api/v1/rooms/#{slug}/messages/#{mine}",
        %{room: "general", id: kept, body: "Again"},
        from,
        agent
      )

    assert %{"message" => %{"id" => ^mine, "body" => "Again"}} = Jason.decode!(reedited.resp_body)
    assert %{"body" => "Kept"} = read_message(from, slug, kept)

    # A like and a like taken back answer the same both ways; a like's body never chooses
    # another message.
    for {name, method, body, liked} <- [
          {"rooms_like", :post, %{room: "general", id: kept}, true},
          {"rooms_unlike", :delete, nil, false}
        ] do
      assert %{"isError" => false, "structuredContent" => answer} =
               result(mcp(call(name, %{room: slug, id: theirs}), from: from, proof: agent))

      assert %{"liked" => ^liked, "message" => %{"id" => ^theirs}} = answer
      over_http = http(method, "/api/v1/rooms/#{slug}/messages/#{theirs}/like", body, from, agent)
      assert Jason.decode!(over_http.resp_body) == answer, name
    end

    assert %{"like_count" => 0} = read_message(from, slug, kept)

    # A report through /mcp; reporting again over HTTP answers the first, whatever the body names.
    assert %{"isError" => false, "structuredContent" => %{"report" => report}} =
             result(
               mcp(call("rooms_report", %{room: slug, id: theirs, reason: "spam"}),
                 from: from,
                 proof: agent
               )
             )

    rereported =
      http(
        :post,
        "/api/v1/rooms/#{slug}/messages/#{theirs}/report",
        %{room: "general", id: kept, reason: "abuse"},
        from,
        agent
      )

    assert Jason.decode!(rereported.resp_body) == %{"report" => report}
    assert %{"reason" => "spam"} = report

    # A mute through /mcp is listed over HTTP, and muting again keeps it.
    assert %{"isError" => false, "structuredContent" => %{"mute" => mute}} =
             result(mcp(call("mutes_add", %{message_id: theirs}), from: from, proof: agent))

    assert mutes(from, agent) == [mute]
    remuted = http(:post, "/api/v1/mutes", %{message_id: theirs}, from, agent)
    assert Jason.decode!(remuted.resp_body) == %{"mute" => mute}

    # Lifted through /mcp; HTTP then finds no such mute.
    assert %{"isError" => false, "structuredContent" => lifted} =
             result(mcp(call("mutes_remove", %{id: mute["id"]}), from: from, proof: agent))

    assert lifted == %{"removed" => true, "id" => mute["id"]}
    relifted = http(:delete, "/api/v1/mutes/#{mute["id"]}", nil, from, agent)

    assert {relifted.status, Jason.decode!(relifted.resp_body)["error"]["code"]} ==
             {404, "mute_not_found"}

    # Deleting answers the same both ways.
    assert %{"isError" => false, "structuredContent" => deleted} =
             result(mcp(call("rooms_delete", %{room: slug, id: mine}), from: from, proof: agent))

    assert deleted == %{"deleted" => true, "id" => mine}
    assert http(:get, "/api/v1/rooms/#{slug}/messages/#{mine}", nil, from, nil).status == 404
    other = said(from, agent, slug, "Other")
    redeleted = http(:delete, "/api/v1/rooms/#{slug}/messages/#{other}", nil, from, agent)
    assert Jason.decode!(redeleted.resp_body) == %{"deleted" => true, "id" => other}

    # A removal never carries a body: each refuses one before anything runs, and nothing goes.
    assert http(:post, "/api/v1/rooms/#{slug}/messages/#{kept}/like", nil, from, agent).status ==
             200

    assert %{"mute" => kept_mute} =
             Jason.decode!(
               http(:post, "/api/v1/mutes", %{message_id: theirs}, from, agent).resp_body
             )

    for path <- [
          "/api/v1/rooms/#{slug}/messages/#{kept}/like",
          "/api/v1/rooms/#{slug}/messages/#{kept}",
          "/api/v1/mutes/#{kept_mute["id"]}"
        ] do
      refused = http(:delete, path, %{room: slug, id: other}, from, agent)

      assert {refused.status, Jason.decode!(refused.resp_body)["error"]["code"]} ==
               {401, "missing_signed_body"},
             path
    end

    assert %{"body" => "Kept", "like_count" => 1} = read_message(from, slug, kept)
    assert mutes(from, agent) == [kept_mute]
  end

  test "each rooms and mutes tool refuses through /mcp with the code and words HTTP gives",
       %{from: from} do
    unpaired = wallet()
    [agent, same_person] = paired_wallets(2)
    stranger = paired_wallet()

    slug =
      Jason.decode!(
        http(
          :post,
          "/api/v1/rooms",
          %{name: "Refusals #{:erlang.unique_integer([:positive])}", topic: "Here"},
          from,
          agent
        ).resp_body
      )["room"]["slug"]

    mine = said(from, agent, slug, "Mine")
    theirs = said(from, stranger, slug, "Theirs")
    missing = Ecto.UUID.generate()
    too_long = String.duplicate("a", 201)

    codes =
      for {name, input, method, path, body, signer} <- [
            {"rooms_create", %{name: "Unpaired", topic: "No"}, :post, "/api/v1/rooms",
             %{name: "Unpaired", topic: "No"}, unpaired},
            {"rooms_create", %{name: "!!!", topic: "No letters"}, :post, "/api/v1/rooms",
             %{name: "!!!", topic: "No letters"}, agent},
            {"rooms_create", %{name: "General", topic: "Taken"}, :post, "/api/v1/rooms",
             %{name: "General", topic: "Taken"}, agent},
            {"rooms_topic", %{room: "general", topic: "Mine now"}, :patch,
             "/api/v1/rooms/general", %{topic: "Mine now"}, agent},
            {"rooms_topic", %{room: "no-such-room", topic: "Here"}, :patch,
             "/api/v1/rooms/no-such-room", %{topic: "Here"}, agent},
            {"rooms_topic", %{room: slug, topic: too_long}, :patch, "/api/v1/rooms/#{slug}",
             %{topic: too_long}, agent},
            {"rooms_edit", %{room: slug, id: theirs, body: "Not mine"}, :patch,
             "/api/v1/rooms/#{slug}/messages/#{theirs}", %{body: "Not mine"}, agent},
            {"rooms_edit", %{room: slug, id: mine, body: ""}, :patch,
             "/api/v1/rooms/#{slug}/messages/#{mine}", %{body: ""}, agent},
            {"rooms_edit", %{room: slug, id: "not-a-uuid", body: "Hi"}, :patch,
             "/api/v1/rooms/#{slug}/messages/not-a-uuid", %{body: "Hi"}, agent},
            {"rooms_edit", %{room: slug, id: mine, body: "Hi", pinned: true}, :patch,
             "/api/v1/rooms/#{slug}/messages/#{mine}", %{body: "Hi", pinned: true}, agent},
            {"rooms_delete", %{room: slug, id: theirs}, :delete,
             "/api/v1/rooms/#{slug}/messages/#{theirs}", nil, agent},
            {"rooms_delete", %{room: "general", id: mine}, :delete,
             "/api/v1/rooms/general/messages/#{mine}", nil, same_person},
            {"rooms_like", %{room: slug, id: missing}, :post,
             "/api/v1/rooms/#{slug}/messages/#{missing}/like", nil, agent},
            {"rooms_unlike", %{room: "no-such-room", id: theirs}, :delete,
             "/api/v1/rooms/no-such-room/messages/#{theirs}/like", nil, agent},
            {"rooms_report", %{room: slug, id: theirs, reason: "rude"}, :post,
             "/api/v1/rooms/#{slug}/messages/#{theirs}/report", %{reason: "rude"}, agent},
            {"rooms_report", %{room: slug, id: mine, reason: "spam"}, :post,
             "/api/v1/rooms/#{slug}/messages/#{mine}/report", %{reason: "spam"}, same_person},
            {"rooms_report", %{room: slug, id: missing, reason: "spam"}, :post,
             "/api/v1/rooms/#{slug}/messages/#{missing}/report", %{reason: "spam"}, agent},
            {"mutes_add", %{message_id: mine}, :post, "/api/v1/mutes", %{message_id: mine},
             agent},
            {"mutes_add", %{message_id: theirs}, :post, "/api/v1/mutes", %{message_id: theirs},
             unpaired},
            {"mutes_remove", %{id: missing}, :delete, "/api/v1/mutes/#{missing}", nil, agent},
            {"mutes_remove", %{id: "not-a-uuid"}, :delete, "/api/v1/mutes/not-a-uuid", nil, agent}
          ] do
        over_http = http(method, path, body, from, signer)
        %{"error" => refused} = Jason.decode!(over_http.resp_body)

        assert %{"isError" => true, "content" => [%{"text" => text}]} =
                 result(mcp(call(name, input), from: from, proof: signer))

        assert Jason.decode!(text)["error"] == refused, "#{name} #{inspect(input)}"
        {over_http.status, refused["code"]}
      end

    assert codes == [
             {403, "agent_not_paired"},
             {422, "invalid_room"},
             {409, "room_name_taken"},
             {403, "not_room_maker"},
             {404, "room_not_found"},
             {422, "invalid_room"},
             {404, "message_not_found"},
             {422, "invalid_message"},
             {404, "message_not_found"},
             {422, "invalid_message"},
             {404, "message_not_found"},
             {404, "message_not_found"},
             {404, "public_message_not_found"},
             {404, "room_not_found"},
             {422, "invalid_report"},
             {422, "invalid_report"},
             {404, "public_message_not_found"},
             {422, "invalid_mute"},
             {403, "agent_not_paired"},
             {404, "mute_not_found"},
             {404, "mute_not_found"}
           ]

    # Nothing refused changed a message or a room.
    assert %{"body" => "Mine"} = read_message(from, slug, mine)
    assert %{"body" => "Theirs"} = read_message(from, slug, theirs)
    assert listed_room(from, "general")["topic"] != "Mine now"
  end

  test "a room's name again answers the room only with its topic, both ways", %{from: from} do
    agent = paired_wallet()
    name = "Design #{:erlang.unique_integer([:positive])}"

    assert %{"isError" => false, "structuredContent" => %{"replayed" => false, "room" => room}} =
             result(
               mcp(call("rooms_create", %{name: name, topic: "A"}), from: from, proof: agent)
             )

    # Another topic under the name is refused, and the room keeps its topic.
    over_http = http(:post, "/api/v1/rooms", %{name: name, topic: "B"}, from, agent)
    %{"error" => refused} = Jason.decode!(over_http.resp_body)
    assert {over_http.status, refused["code"]} == {409, "room_name_taken"}

    assert %{"isError" => true, "content" => [%{"text" => text}]} =
             result(
               mcp(call("rooms_create", %{name: name, topic: "B"}), from: from, proof: agent)
             )

    assert Jason.decode!(text)["error"] == refused
    assert %{"topic" => "A"} = listed_room(from, room["slug"])

    # The same name and topic answers the room, started once.
    assert %{"isError" => false, "structuredContent" => %{"replayed" => true, "room" => ^room}} =
             result(
               mcp(call("rooms_create", %{name: name, topic: "A"}), from: from, proof: agent)
             )

    again = http(:post, "/api/v1/rooms", %{name: name, topic: "A"}, from, agent)
    assert {again.status, Jason.decode!(again.resp_body)} == {200, %{"room" => room}}
  end

  test "two starts of one room at once leave one room, and both answer it", %{from: from} do
    for ways <- [[:http, :http], [:mcp, :mcp], [:http, :mcp], [:mcp, :http]], _ <- 1..5 do
      agent = paired_wallet()
      name = "Race #{:erlang.unique_integer([:positive])}"

      answers =
        ways
        |> Enum.map(fn way -> Task.async(fn -> start_room(way, from, agent, name) end) end)
        |> Task.await_many()

      assert [%{"slug" => slug} = room, room] = Enum.map(answers, &elem(&1, 1))
      assert answers |> Enum.map(&elem(&1, 0)) |> Enum.sort() == [false, true]
      rooms = Jason.decode!(http(:get, "/api/v1/rooms", nil, from, nil).resp_body)["rooms"]
      assert Enum.filter(rooms, &(&1["slug"] == slug)) == [room]
    end
  end

  test "two removals of one mute at once: one removes it, the other finds no mute, both ways",
       %{from: from} do
    for ways <- [[:http, :http], [:mcp, :mcp], [:http, :mcp]], _ <- 1..3 do
      agent = paired_wallet()
      theirs = said(from, paired_wallet(), "general", "Mute me")

      %{"mute" => %{"id" => id}} =
        Jason.decode!(http(:post, "/api/v1/mutes", %{message_id: theirs}, from, agent).resp_body)

      answers =
        ways
        |> Enum.map(fn way -> Task.async(fn -> remove_mute(way, from, agent, id) end) end)
        |> Task.await_many()

      assert Enum.sort(answers) == [{:refused, "mute_not_found"}, {:removed, id}], inspect(ways)
      assert mutes(from, agent) == []
    end
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

  # `agent` starting the room `name` through `way`: whether it was replayed, and the room.
  defp start_room(:http, from, agent, name) do
    conn = http(:post, "/api/v1/rooms", %{name: name, topic: "Race"}, from, agent)
    assert conn.status in [200, 201], conn.resp_body
    {conn.status == 200, Jason.decode!(conn.resp_body)["room"]}
  end

  defp start_room(:mcp, from, agent, name) do
    assert %{"isError" => false, "structuredContent" => %{"replayed" => replayed, "room" => room}} =
             result(
               mcp(call("rooms_create", %{name: name, topic: "Race"}), from: from, proof: agent)
             )

    {replayed, room}
  end

  # `agent` lifting the mute `id` through `way`: removed, or refused with its code (404 over HTTP).
  defp remove_mute(:http, from, agent, id) do
    conn = http(:delete, "/api/v1/mutes/#{id}", nil, from, agent)

    case {conn.status, Jason.decode!(conn.resp_body)} do
      {200, %{"removed" => true, "id" => ^id}} -> {:removed, id}
      {404, %{"error" => %{"code" => code}}} -> {:refused, code}
    end
  end

  defp remove_mute(:mcp, from, agent, id) do
    case result(mcp(call("mutes_remove", %{id: id}), from: from, proof: agent)) do
      %{"isError" => false, "structuredContent" => %{"removed" => true, "id" => ^id}} ->
        {:removed, id}

      %{"isError" => true, "content" => [%{"text" => text}]} ->
        {:refused, Jason.decode!(text)["error"]["code"]}
    end
  end

  # A new message by `agent` in the room `slug`, posted over HTTP: its id.
  defp said(from, agent, slug, text) do
    conn =
      http(
        :post,
        "/api/v1/rooms/#{slug}/messages",
        %{body: text, operation_id: Ecto.UUID.generate()},
        from,
        agent
      )

    assert conn.status == 201, conn.resp_body
    Jason.decode!(conn.resp_body)["message"]["id"]
  end

  # The message `id` in the room `slug`, as anyone reads it over HTTP.
  defp read_message(from, slug, id) do
    conn = http(:get, "/api/v1/rooms/#{slug}/messages/#{id}", nil, from, nil)
    assert conn.status == 200, conn.resp_body
    Jason.decode!(conn.resp_body)["message"]
  end

  # `agent`'s person's mutes, as HTTP lists them.
  defp mutes(from, agent),
    do: Jason.decode!(http(:get, "/api/v1/mutes", nil, from, agent).resp_body)["mutes"]

  # The room `slug` as the room list shows it.
  defp listed_room(from, slug) do
    Jason.decode!(http(:get, "/api/v1/rooms", nil, from, nil).resp_body)["rooms"]
    |> Enum.find(&(&1["slug"] == slug))
  end

  # The note `id` as HTTP reads it for `agent`'s person.
  defp read_note(from, agent, id) do
    conn = http(:get, "/api/v1/notes/#{id}", nil, from, agent)
    assert conn.status == 200, conn.resp_body
    Jason.decode!(conn.resp_body)["note"]
  end

  # A label on the note `id`, as the labelling service leaves it in `state`: its id.
  defp label(id, state) do
    note = Ash.get!(AshTemplate.Notes.Note, id, authorize?: false)
    keys = AshTemplate.Notes.Labels.keys()

    Ash.Seed.seed!(AshTemplate.Notes.Decision, %{
      note_id: id,
      human_account_id: note.human_account_id,
      question: "Which fits?",
      choices: keys,
      state: state,
      choice: if(state == :answered, do: hd(keys)),
      confidence: if(state == :answered, do: 0.9)
    }).id
  end

  # A new note with `key`, refused the same way over HTTP and through /mcp: HTTP's
  # status and error.
  defp refused_both_ways(from, agent, title, key) do
    input = %{title: title, operation_id: key}
    over_http = http(:post, "/api/v1/notes", input, from, agent)
    %{"error" => refused} = Jason.decode!(over_http.resp_body)

    assert %{"isError" => true, "content" => [%{"text" => text}]} =
             result(mcp(call("notes_create", input), from: from, proof: agent))

    assert Jason.decode!(text)["error"] == refused
    {over_http.status, refused}
  end

  # The note `id`'s saved revision and who saved it, as the database holds them.
  defp saved(id) do
    AshTemplate.Notes.Note
    |> Ash.get!(id, authorize?: false)
    |> Map.take([:revision, :changed_by_agent_id, :updated_at])
  end

  defp mine(notes, id), do: Enum.filter(notes, &(&1.id == id))

  # One request to the HTTP API, signed by `signer`'s wallet when there is one.
  defp http(method, path, body, from, signer) do
    conn(method, path, body && Jason.encode!(body))
    |> Map.put(:remote_ip, from)
    |> put_req_header("content-type", "application/json")
    |> put_req_header("accept", "application/json")
    |> then(&if(signer, do: signed(&1, signer, "fixture-proof"), else: &1))
    |> @endpoint.call([])
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
  defp paired_wallet, do: hd(paired_wallets(1))

  # `count` agents' wallets, each paired with the same new person's account here.
  defp paired_wallets(count) do
    did = "did:privy:mcp-" <> Ecto.UUID.generate()
    person = wallet()
    Accounts.register_verified!(did, person, [person], actor: %System{})

    for _agent <- 1..count do
      agent = wallet()
      code = RegentAgents.issue_pairing_code!(actor: %RegentAgents.Person{privy_user_id: did})

      RegentAgents.pair_agent!(code.code, "Agent", :codex,
        actor: %RegentAgents.Agent{wallet: agent}
      )

      agent
    end
  end

  defp wallet, do: "0x" <> Base.encode16(:crypto.strong_rand_bytes(20), case: :lower)
end
