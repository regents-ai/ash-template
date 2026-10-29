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
  # - each direct-messages tool answers and refuses as HTTP does, over HTTP the
  #   address alone names the conversation, a message's operation_id answers
  #   only the same words in the same conversation, and two sends with one key at
  #   once send one message;
  # - each chat tool answers and refuses as HTTP does, over HTTP the address
  #   alone names the chat a page is read from, a message's operation_id answers
  #   only the same words in the same chat, and two sends with one key at once
  #   send one message;
  # - each polls tool answers and refuses as HTTP does, over HTTP the address
  #   alone names the poll a vote is for, a start's operation_id answers only the
  #   same question, choices and minutes, and two starts with one key at once
  #   start one poll;
  # - an agent's change to its own profile and its marking its person's activity
  #   read answer and refuse as HTTP does, and marking read after the pairing
  #   ended marks nothing;
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

  test "a public read takes over HTTP just the input its hosted tool takes, refused in its words",
       %{from: from} do
    agent = paired_wallet()

    for {name, input, path} <- [
          {"health", %{foo: "1"}, "/api/v1/health?foo=1"},
          {"docs", %{foo: "1"}, "/api/v1/docs?foo=1"},
          {"rooms_list", %{foo: "1"}, "/api/v1/rooms?foo=1"},
          {"polls_list", %{foo: "1"}, "/api/v1/polls?foo=1"},
          {"sites_tools", %{site: "regents", foo: "1"}, "/api/v1/sites/regents/tools?foo=1"},
          {"rooms_messages", %{room: "general", foo: "1"}, "/api/v1/rooms/general/messages?foo=1"},
          {"rooms_messages", %{room: "general", foo: "1", limit: "x"},
           "/api/v1/rooms/general/messages?foo=1&limit=x"},
          {"rooms_message", %{room: "general", id: "x"}, "/api/v1/rooms/general/messages/x"},
          {"agents_get", %{id: "x"}, "/api/v1/agents/x"},
          {"polls_show", %{poll: "x", foo: "1"}, "/api/v1/polls/x?foo=1"}
        ] do
      over_http = http(:get, path, nil, from, nil)
      %{"error" => refused} = Jason.decode!(over_http.resp_body)

      assert %{"isError" => true, "content" => [%{"text" => text}]} =
               result(mcp(call(name, input), from: from, proof: agent))

      assert over_http.status in [404, 422], path
      assert Jason.decode!(text)["error"] == refused, path
    end
  end

  test "a browser tool's answer to input it cannot send is the hosted tool's", %{from: from} do
    agent = paired_wallet()

    manifest =
      Application.app_dir(:ash_template, "priv/tool_manifest.json")
      |> File.read!()
      |> Jason.decode!()

    for %{"authentication" => "public", "name" => name, "route" => route} = tool <-
          manifest["tools"] do
      fields = Regex.scan(~r/\{(\w+)\}/, route, capture: :all_but_first) |> List.flatten()
      assert Map.keys(tool["refusals"]) |> Enum.sort() == Enum.sort(["input" | fields]), name

      for {field, refusal} <- tool["refusals"] do
        input = if field == "input", do: "x", else: Map.new(fields -- [field], &{&1, "a"})

        assert %{"isError" => true, "content" => [%{"text" => text}]} =
                 result(mcp(call(name, input), from: from, proof: agent))

        assert Jason.decode!(text)["error"] == refusal, "#{name} #{field}"
      end
    end
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

  test "each direct-messages tool answers through /mcp as HTTP answers, and the address alone names the conversation",
       %{from: from} do
    [agent, other, third] = for _person <- 1..3, do: paired_wallet()
    theirs = said(from, other, "general", "Write to me")

    # Opened through /mcp; opening it again over HTTP answers the same conversation.
    assert %{"isError" => false, "structuredContent" => %{"conversation" => opened}} =
             result(mcp(call("dms_open", %{message_id: theirs}), from: from, proof: agent))

    assert %{"id" => id, "blocked" => false, "last_message" => nil} = opened
    reopened = http(:post, "/api/v1/dms", %{message_id: theirs}, from, agent)
    assert Jason.decode!(reopened.resp_body) == %{"conversation" => opened}
    elsewhere = conversation(from, agent, third)

    # Sent through /mcp; its retry over HTTP answers the same message.
    key = Ecto.UUID.generate()

    assert %{"isError" => false, "structuredContent" => %{"replayed" => false, "message" => sent}} =
             result(
               mcp(call("dms_send", %{conversation: id, body: "Hi", operation_id: key}),
                 from: from,
                 proof: agent
               )
             )

    assert %{"id" => ^key, "conversation_id" => ^id, "body" => "Hi", "mine" => true} = sent
    again = http(:post, "/api/v1/dms/#{id}/messages", %{body: "Hi", operation_id: key}, from, agent)
    assert {again.status, Jason.decode!(again.resp_body)} == {200, %{"message" => sent}}

    # Over HTTP a conversation in the body never chooses another.
    here =
      http(
        :post,
        "/api/v1/dms/#{id}/messages",
        %{conversation: elsewhere, body: "Here", operation_id: Ecto.UUID.generate()},
        from,
        agent
      )

    assert here.status == 201
    assert %{"message" => %{"conversation_id" => ^id}} = Jason.decode!(here.resp_body)

    # Read the same both ways; the other person reads both, written for this one.
    assert %{"isError" => false, "structuredContent" => read} =
             result(mcp(call("dms_read", %{conversation: id}), from: from, proof: agent))

    assert %{
             "messages" => [%{"body" => "Here"}, ^sent],
             "pagination" => %{"has_more" => false, "next_cursor" => nil}
           } = read

    reread = http(:post, "/api/v1/dms/#{id}/history", %{conversation: elsewhere}, from, agent)
    assert Jason.decode!(reread.resp_body) == read

    assert [%{"body" => "Here", "mine" => false}, %{"id" => ^key, "mine" => false}] =
             history(from, other, id)

    # Listed the same both ways, newest message first.
    assert %{"isError" => false, "structuredContent" => listed} =
             result(mcp(call("dms_list", %{}), from: from, proof: agent))

    assert %{"conversations" => [%{"id" => ^id, "last_message" => "Here"}, %{"id" => ^elsewhere}]} =
             listed

    assert Jason.decode!(http(:get, "/api/v1/dms", nil, from, agent).resp_body) == listed

    # Blocked through /mcp, it is on the blocked list both ways; unblocked over HTTP
    # (whatever the body names), then through /mcp, it is back.
    assert %{
             "isError" => false,
             "structuredContent" => %{"conversation" => %{"id" => ^id, "blocked" => true} = blocked}
           } = result(mcp(call("dms_block", %{conversation: id}), from: from, proof: agent))

    assert %{"isError" => false, "structuredContent" => %{"conversations" => [^blocked]}} =
             result(mcp(call("dms_blocked", %{}), from: from, proof: agent))

    assert Jason.decode!(http(:get, "/api/v1/dms/blocked", nil, from, agent).resp_body) ==
             %{"conversations" => [blocked]}

    unblocked = http(:post, "/api/v1/dms/#{id}/unblock", %{conversation: elsewhere}, from, agent)
    assert %{"conversation" => %{"id" => ^id, "blocked" => false} = back} =
             Jason.decode!(unblocked.resp_body)

    assert %{"isError" => false, "structuredContent" => %{"conversation" => ^back}} =
             result(mcp(call("dms_unblock", %{conversation: id}), from: from, proof: agent))

    assert %{"conversations" => [%{"id" => ^id, "blocked" => false}, %{"id" => ^elsewhere}]} =
             Jason.decode!(http(:get, "/api/v1/dms", nil, from, agent).resp_body)
  end

  test "each direct-messages tool refuses through /mcp with the code and words HTTP gives",
       %{from: from} do
    unpaired = wallet()
    [agent, same_person] = paired_wallets(2)
    [other, third] = for _person <- 1..2, do: paired_wallet()
    mine = said(from, agent, "general", "Mine")
    id = conversation(from, agent, other)
    strangers = conversation(from, third, other)

    # A message the other side sent: its id is a key no agent of this person spent.
    %{"message" => %{"id" => taken}} =
      Jason.decode!(
        http(
          :post,
          "/api/v1/dms/#{id}/messages",
          %{body: "Theirs", operation_id: Ecto.UUID.generate()},
          from,
          other
        ).resp_body
      )

    key = Ecto.UUID.generate()

    assert http(:post, "/api/v1/dms/#{id}/messages", %{body: "First", operation_id: key}, from, agent).status ==
             201

    missing = Ecto.UUID.generate()
    history = "/api/v1/dms/#{id}/history"
    messages = "/api/v1/dms/#{id}/messages"

    codes =
      for {name, input, method, path, body, signer} <- [
            {"dms_list", %{}, :get, "/api/v1/dms", nil, unpaired},
            {"dms_open", %{message_id: mine}, :post, "/api/v1/dms", %{message_id: mine},
             same_person},
            {"dms_open", %{message_id: missing}, :post, "/api/v1/dms", %{message_id: missing},
             agent},
            {"dms_open", %{message_id: "not-a-uuid"}, :post, "/api/v1/dms",
             %{message_id: "not-a-uuid"}, agent},
            {"dms_read", %{conversation: missing}, :post, "/api/v1/dms/#{missing}/history", %{},
             agent},
            {"dms_read", %{conversation: strangers}, :post, "/api/v1/dms/#{strangers}/history",
             %{}, agent},
            {"dms_read", %{conversation: id, after: "not-a-cursor"}, :post, history,
             %{after: "not-a-cursor"}, agent},
            {"dms_read", %{conversation: id, after: 5}, :post, history, %{after: 5}, agent},
            {"dms_read", %{conversation: id, limit: 5}, :post, history, %{limit: 5}, agent},
            {"dms_send", %{conversation: id, body: "", operation_id: missing}, :post, messages,
             %{body: "", operation_id: missing}, agent},
            {"dms_send", %{conversation: id, body: "No key"}, :post, messages,
             %{body: "No key"}, agent},
            {"dms_send", %{conversation: id, body: "Hi", operation_id: missing, pinned: true},
             :post, messages, %{body: "Hi", operation_id: missing, pinned: true}, agent},
            {"dms_send", %{conversation: "not-a-uuid", body: "Hi", operation_id: missing}, :post,
             "/api/v1/dms/not-a-uuid/messages", %{body: "Hi", operation_id: missing}, agent},
            {"dms_send", %{conversation: strangers, body: "Hi", operation_id: missing}, :post,
             "/api/v1/dms/#{strangers}/messages", %{body: "Hi", operation_id: missing}, agent},
            {"dms_send", %{conversation: id, body: "Other words", operation_id: key}, :post,
             messages, %{body: "Other words", operation_id: key}, agent},
            {"dms_send", %{conversation: id, body: "Theirs", operation_id: taken}, :post,
             messages, %{body: "Theirs", operation_id: taken}, agent},
            {"dms_block", %{conversation: missing}, :post, "/api/v1/dms/#{missing}/block", nil,
             agent},
            {"dms_unblock", %{conversation: "not-a-uuid"}, :post,
             "/api/v1/dms/not-a-uuid/unblock", nil, agent}
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
             {422, "invalid_open"},
             {422, "invalid_open"},
             {422, "invalid_open"},
             {404, "conversation_not_found"},
             {404, "conversation_not_found"},
             {422, "invalid_cursor"},
             {422, "invalid_cursor"},
             {422, "invalid_cursor"},
             {422, "invalid_message"},
             {422, "invalid_message"},
             {422, "invalid_message"},
             {404, "conversation_not_found"},
             {404, "conversation_not_found"},
             {409, "idempotency_conflict"},
             {409, "idempotency_conflict"},
             {404, "conversation_not_found"},
             {404, "conversation_not_found"}
           ]

    # Nothing refused sent a message or opened a conversation.
    assert [%{"body" => "First"}, %{"id" => ^taken}] = history(from, agent, id)
    assert history(from, third, strangers) == []

    assert [%{"id" => ^id}] =
             Jason.decode!(http(:get, "/api/v1/dms", nil, from, agent).resp_body)["conversations"]
  end

  test "an operation_id answers only the same words in the same conversation, whichever way each call comes",
       %{from: from} do
    agent = paired_wallet()
    id = conversation(from, agent, paired_wallet())
    elsewhere = conversation(from, agent, paired_wallet())

    for first <- [:http, :mcp], again <- [:http, :mcp] do
      key = Ecto.UUID.generate()
      assert dm(first, from, agent, id, "Same", key) == {:sent, key}
      assert dm(again, from, agent, id, "Same", key) == {:replayed, key}
      assert dm(again, from, agent, id, "Other", key) == {:refused, "idempotency_conflict"}
      assert dm(again, from, agent, elsewhere, "Same", key) == {:refused, "idempotency_conflict"}
    end

    assert length(history(from, agent, id)) == 4
    assert history(from, agent, elsewhere) == []
  end

  test "two sends with one operation_id at once send one message, and both answer it",
       %{from: from} do
    for ways <- [[:http, :http], [:mcp, :mcp], [:http, :mcp], [:mcp, :http]], _ <- 1..3 do
      agent = paired_wallet()
      id = conversation(from, agent, paired_wallet())
      key = Ecto.UUID.generate()

      answers =
        ways
        |> Enum.map(fn way -> Task.async(fn -> dm(way, from, agent, id, "Once", key) end) end)
        |> Task.await_many()

      assert Enum.sort(answers) == [{:replayed, key}, {:sent, key}], inspect(ways)
      assert [%{"id" => ^key}] = history(from, agent, id)
    end
  end

  test "a direct-messages action after the agent's pairing ended is refused as agent_not_paired",
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

    id = conversation(from, agent, paired_wallet())

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

    for call <- [
          fn -> AshTemplate.Dms.dms_list(actor: let_in) end,
          fn -> AshTemplate.Dms.dms_read(id, %{}, actor: let_in) end,
          fn -> AshTemplate.Dms.dms_send(id, %{body: "Late", operation_id: key}, actor: let_in) end,
          fn -> AshTemplate.Dms.dms_block(id, actor: let_in) end
        ] do
      assert {:error, %Ash.Error.Forbidden{errors: [%NotPaired{code: "agent_not_paired"}]}} =
               call.()
    end

    assert AshTemplate.Dms.Message |> Ash.read!(authorize?: false) |> mine(key) == []

    refute Ash.get!(AshTemplate.Dms.Conversation, id, authorize?: false).blocked_by_a or
             Ash.get!(AshTemplate.Dms.Conversation, id, authorize?: false).blocked_by_b
  end

  test "each chat tool answers through /mcp as HTTP answers, and the address alone names the chat",
       %{from: from} do
    agent = paired_wallet()

    # Started through /mcp; its retry over HTTP answers the same message.
    key = Ecto.UUID.generate()

    assert %{"isError" => false, "structuredContent" => %{"replayed" => false, "message" => sent}} =
             result(mcp(call("chat_send", %{text: "Hi", operation_id: key}), from: from, proof: agent))

    assert %{"id" => ^key, "conversation_id" => id, "from" => "person", "text" => "Hi"} = sent
    again = http(:post, "/api/v1/chat/messages", %{text: "Hi", operation_id: key}, from, agent)
    assert {again.status, Jason.decode!(again.resp_body)} == {200, %{"message" => sent}}

    # Continued over HTTP; another chat started over HTTP.
    assert {:sent, _} = chat(:http, from, agent, id, "More", Ecto.UUID.generate())
    elsewhere = new_chat(from, agent)

    # Read the same both ways; a chat in the body of a page never chooses another.
    assert %{"isError" => false, "structuredContent" => read} =
             result(mcp(call("chat_read", %{conversation: id}), from: from, proof: agent))

    assert %{
             "messages" => [%{"text" => "More"}, ^sent],
             "pagination" => %{"has_more" => false, "next_cursor" => nil}
           } = read

    reread = http(:post, "/api/v1/chat/#{id}/history", %{conversation: elsewhere}, from, agent)
    assert Jason.decode!(reread.resp_body) == read

    # Listed the same both ways, newest first.
    assert %{"isError" => false, "structuredContent" => listed} =
             result(mcp(call("chat_list", %{}), from: from, proof: agent))

    assert %{"conversations" => [%{"id" => ^elsewhere}, %{"id" => ^id}]} = listed
    assert Jason.decode!(http(:get, "/api/v1/chat", nil, from, agent).resp_body) == listed
  end

  test "each chat tool refuses through /mcp with the code and words HTTP gives", %{from: from} do
    unpaired = wallet()
    agent = paired_wallet()
    stranger = paired_wallet()
    id = new_chat(from, agent)
    strangers = new_chat(from, stranger)
    [%{"id" => taken}] = chat_history(from, stranger, strangers)
    key = Ecto.UUID.generate()
    assert chat(:http, from, agent, id, "First", key) == {:sent, key}
    missing = Ecto.UUID.generate()
    history = "/api/v1/chat/#{id}/history"
    send = "/api/v1/chat/messages"

    codes =
      for {name, input, method, path, body, signer} <- [
            {"chat_list", %{}, :get, "/api/v1/chat", nil, unpaired},
            {"chat_read", %{conversation: missing}, :post, "/api/v1/chat/#{missing}/history", %{},
             agent},
            {"chat_read", %{conversation: strangers}, :post, "/api/v1/chat/#{strangers}/history",
             %{}, agent},
            {"chat_read", %{conversation: "not-a-uuid"}, :post, "/api/v1/chat/not-a-uuid/history",
             %{}, agent},
            {"chat_read", %{conversation: id, after: "not-a-cursor"}, :post, history,
             %{after: "not-a-cursor"}, agent},
            {"chat_read", %{conversation: id, after: 5}, :post, history, %{after: 5}, agent},
            {"chat_read", %{conversation: id, limit: 5}, :post, history, %{limit: 5}, agent},
            {"chat_send", %{conversation_id: id, text: " ", operation_id: missing}, :post, send,
             %{conversation_id: id, text: " ", operation_id: missing}, agent},
            {"chat_send", %{conversation_id: id, text: "No key"}, :post, send,
             %{conversation_id: id, text: "No key"}, agent},
            {"chat_send", %{conversation_id: id, text: "Hi", operation_id: missing, title: "T"},
             :post, send, %{conversation_id: id, text: "Hi", operation_id: missing, title: "T"},
             agent},
            {"chat_send", %{conversation_id: "not-a-uuid", text: "Hi", operation_id: missing},
             :post, send, %{conversation_id: "not-a-uuid", text: "Hi", operation_id: missing},
             agent},
            {"chat_send", %{conversation_id: strangers, text: "Hi", operation_id: missing}, :post,
             send, %{conversation_id: strangers, text: "Hi", operation_id: missing}, agent},
            {"chat_send", %{conversation_id: id, text: "Other words", operation_id: key}, :post,
             send, %{conversation_id: id, text: "Other words", operation_id: key}, agent},
            {"chat_send", %{conversation_id: id, text: "Theirs", operation_id: taken}, :post,
             send, %{conversation_id: id, text: "Theirs", operation_id: taken}, agent}
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
             {404, "chat_not_found"},
             {404, "chat_not_found"},
             {404, "chat_not_found"},
             {422, "invalid_cursor"},
             {422, "invalid_cursor"},
             {422, "invalid_cursor"},
             {422, "invalid_message"},
             {422, "invalid_message"},
             {422, "invalid_message"},
             {404, "chat_not_found"},
             {404, "chat_not_found"},
             {409, "idempotency_conflict"},
             {409, "idempotency_conflict"}
           ]

    # Nothing refused sent a message or started a chat.
    assert [%{"text" => "First"}, %{"text" => "Opening"}] = chat_history(from, agent, id)
    assert [%{"id" => ^taken}] = chat_history(from, stranger, strangers)

    assert [%{"id" => ^id}] =
             Jason.decode!(http(:get, "/api/v1/chat", nil, from, agent).resp_body)["conversations"]
  end

  test "a chat operation_id answers only the same words in the same chat, whichever way each call comes",
       %{from: from} do
    agent = paired_wallet()
    id = new_chat(from, agent)
    elsewhere = new_chat(from, agent)

    for first <- [:http, :mcp], again <- [:http, :mcp] do
      key = Ecto.UUID.generate()
      assert chat(first, from, agent, id, "Same", key) == {:sent, key}
      assert chat(again, from, agent, id, "Same", key) == {:replayed, key}
      assert chat(again, from, agent, id, "Other", key) == {:refused, "idempotency_conflict"}
      assert chat(again, from, agent, elsewhere, "Same", key) == {:refused, "idempotency_conflict"}
      assert chat(again, from, agent, nil, "Same", key) == {:refused, "idempotency_conflict"}
    end

    # A new chat's retry names no chat again.
    key = Ecto.UUID.generate()
    assert chat(:mcp, from, agent, nil, "New", key) == {:sent, key}
    assert chat(:http, from, agent, nil, "New", key) == {:replayed, key}

    assert length(chat_history(from, agent, id)) == 5
    assert [%{"text" => "Opening"}] = chat_history(from, agent, elsewhere)
    assert length(Jason.decode!(http(:get, "/api/v1/chat", nil, from, agent).resp_body)["conversations"]) == 3
  end

  test "two chat sends with one operation_id at once send one message in one new chat, and both answer it",
       %{from: from} do
    for ways <- [[:http, :http], [:mcp, :mcp], [:http, :mcp], [:mcp, :http]], _ <- 1..3 do
      agent = paired_wallet()
      key = Ecto.UUID.generate()

      answers =
        ways
        |> Enum.map(fn way -> Task.async(fn -> chat(way, from, agent, nil, "Once", key) end) end)
        |> Task.await_many()

      assert Enum.sort(answers) == [{:replayed, key}, {:sent, key}], inspect(ways)

      assert [%{"id" => id}] =
               Jason.decode!(http(:get, "/api/v1/chat", nil, from, agent).resp_body)["conversations"]

      assert [%{"id" => ^key}] = chat_history(from, agent, id)
    end
  end

  test "a chat action after the agent's pairing ended is refused as agent_not_paired",
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

    id = new_chat(from, agent)

    # The agent as its signed request was let in, then the person unpairs it.
    {:ok, active} = RegentAgents.Authority.resolve(Repo, agent)

    let_in =
      AshTemplate.Actors.Agent.paired(
        AshTemplate.Agents.sign_in_agent!(agent, actor: %System{}),
        account,
        active
      )

    assert :ok = RegentAgents.unpair_agent(pairing, actor: owner)
    [key, new_key] = for _ <- 1..2, do: Ecto.UUID.generate()

    for call <- [
          fn -> AshTemplate.Chat.chat_list(actor: let_in) end,
          fn -> AshTemplate.Chat.chat_read(id, %{}, actor: let_in) end,
          fn ->
            AshTemplate.Chat.chat_send(%{conversation_id: id, text: "Late", operation_id: key},
              actor: let_in
            )
          end,
          fn -> AshTemplate.Chat.chat_send(%{text: "Late", operation_id: new_key}, actor: let_in) end
        ] do
      assert {:error, %Ash.Error.Forbidden{errors: [%NotPaired{code: "agent_not_paired"}]}} =
               call.()
    end

    sent = Ash.read!(AshTemplate.Chat.Message, authorize?: false)
    assert mine(sent, key) == [] and mine(sent, new_key) == []
    assert [%{id: ^id}] = Ash.read!(AshTemplate.Chat.Conversation, authorize?: false) |> mine(id)
    assert Ash.read!(AshTemplate.Chat.Conversation, authorize?: false) |> length() == 1
  end

  test "each polls tool answers through /mcp as HTTP answers, and the address alone names the poll",
       %{from: from} do
    agent = paired_wallet()
    voter = paired_wallet()
    key = Ecto.UUID.generate()
    start = %{question: "Lunch?", choices: ["Soup", "Salad"], minutes: 5, operation_id: key}

    # Started through /mcp; its retry over HTTP answers the same poll.
    assert %{"isError" => false, "structuredContent" => %{"replayed" => false, "poll" => started}} =
             result(mcp(call("polls_start", start), from: from, proof: agent))

    assert %{"id" => ^key, "open" => true, "counts" => nil, "votes_cast" => 0} = started
    again = http(:post, "/api/v1/polls", start, from, agent)
    assert {again.status, Jason.decode!(again.resp_body)} == {200, %{"poll" => started}}
    elsewhere = start_poll(from, voter)

    # Voted over HTTP; a poll in the body never chooses another. The same vote
    # through /mcp answers the same.
    voted = http(:post, "/api/v1/polls/#{key}/vote", %{choice: "Soup", poll: elsewhere}, from, voter)
    assert voted.status == 200, voted.resp_body

    assert %{"vote" => %{"choice" => "Soup"}, "poll" => %{"id" => ^key, "votes_cast" => 1}} =
             answer = Jason.decode!(voted.resp_body)

    assert %{"isError" => false, "structuredContent" => ^answer} =
             result(mcp(call("polls_vote", %{poll: key, choice: "Soup"}), from: from, proof: voter))

    assert %{"votes_cast" => 0} = read_poll(from, elsewhere)

    # Read the same both ways, by anyone.
    assert %{"isError" => false, "structuredContent" => shown} =
             result(mcp(call("polls_show", %{poll: key}), from: from, proof: wallet()))

    assert shown == %{"poll" => read_poll(from, key)}

    assert %{"isError" => false, "structuredContent" => listed} =
             result(mcp(call("polls_list", %{}), from: from, proof: agent))

    assert Jason.decode!(http(:get, "/api/v1/polls", nil, from, nil).resp_body) == listed
    assert [^elsewhere, ^key | _] = Enum.map(listed["polls"], & &1["id"])

    # Ended through /mcp; HTTP reads its counts.
    assert %{"isError" => false, "structuredContent" => %{"poll" => ended}} =
             result(mcp(call("polls_end", %{poll: key}), from: from, proof: agent))

    assert %{"open" => false, "counts" => [%{"choice" => "Soup", "votes" => 1}, %{"choice" => "Salad", "votes" => 0}]} =
             ended

    assert read_poll(from, key) == ended
  end

  test "each polls tool refuses through /mcp with the code and words HTTP gives", %{from: from} do
    unpaired = wallet()
    agent = paired_wallet()
    stranger = paired_wallet()
    id = start_poll(from, agent)
    theirs = start_poll(from, stranger)
    closed = start_poll(from, agent)
    assert %{"open" => false} = Jason.decode!(http(:post, "/api/v1/polls/#{closed}/end", nil, from, agent).resp_body)["poll"]
    # A person starts three polls a day: the starts are another person's.
    starter = paired_wallet()
    key = Ecto.UUID.generate()
    first = %{question: "Tea?", choices: ["Yes", "No"], minutes: 5, operation_id: key}
    assert http(:post, "/api/v1/polls", first, from, starter).status == 201
    assert http(:post, "/api/v1/polls/#{id}/vote", %{choice: "Soup"}, from, agent).status == 200
    missing = Ecto.UUID.generate()
    start = fn changes -> Map.merge(%{question: "Lunch?", choices: ["Soup", "Salad"], minutes: 5, operation_id: missing}, changes) end

    codes =
      for {name, input, method, path, body, signer} <- [
            {"polls_show", %{poll: missing}, :get, "/api/v1/polls/#{missing}", nil, nil},
            {"polls_show", %{poll: "not-a-uuid"}, :get, "/api/v1/polls/not-a-uuid", nil, nil},
            {"polls_start", start.(%{}), :post, "/api/v1/polls", start.(%{}), unpaired},
            {"polls_start", start.(%{choices: ["Soup", "Soup"]}), :post, "/api/v1/polls",
             start.(%{choices: ["Soup", "Soup"]}), starter},
            {"polls_start", start.(%{minutes: 0}), :post, "/api/v1/polls", start.(%{minutes: 0}),
             starter},
            {"polls_start", Map.delete(start.(%{}), :operation_id), :post, "/api/v1/polls",
             Map.delete(start.(%{}), :operation_id), starter},
            {"polls_start", start.(%{open: true}), :post, "/api/v1/polls", start.(%{open: true}),
             starter},
            {"polls_start", %{first | question: "Coffee?"}, :post, "/api/v1/polls",
             %{first | question: "Coffee?"}, starter},
            {"polls_start", start.(%{operation_id: theirs}), :post, "/api/v1/polls",
             start.(%{operation_id: theirs}), starter},
            {"polls_vote", %{poll: id, choice: "Soup"}, :post, "/api/v1/polls/#{id}/vote",
             %{choice: "Soup"}, unpaired},
            {"polls_vote", %{poll: missing, choice: "Soup"}, :post,
             "/api/v1/polls/#{missing}/vote", %{choice: "Soup"}, agent},
            {"polls_vote", %{poll: "not-a-uuid", choice: "Soup"}, :post,
             "/api/v1/polls/not-a-uuid/vote", %{choice: "Soup"}, agent},
            {"polls_vote", %{poll: id, choice: "Salad"}, :post, "/api/v1/polls/#{id}/vote",
             %{choice: "Salad"}, agent},
            {"polls_vote", %{poll: theirs, choice: "Pie"}, :post, "/api/v1/polls/#{theirs}/vote",
             %{choice: "Pie"}, agent},
            {"polls_vote", %{poll: theirs}, :post, "/api/v1/polls/#{theirs}/vote", %{}, agent},
            {"polls_vote", %{poll: theirs, choice: "Soup", note: "Hi"}, :post,
             "/api/v1/polls/#{theirs}/vote", %{choice: "Soup", note: "Hi"}, agent},
            {"polls_vote", %{poll: closed, choice: "Soup"}, :post, "/api/v1/polls/#{closed}/vote",
             %{choice: "Soup"}, stranger},
            {"polls_end", %{poll: id}, :post, "/api/v1/polls/#{id}/end", nil, unpaired},
            {"polls_end", %{poll: missing}, :post, "/api/v1/polls/#{missing}/end", nil, agent},
            {"polls_end", %{poll: "not-a-uuid"}, :post, "/api/v1/polls/not-a-uuid/end", nil, agent},
            {"polls_end", %{poll: theirs}, :post, "/api/v1/polls/#{theirs}/end", nil, agent},
            {"polls_end", %{poll: closed}, :post, "/api/v1/polls/#{closed}/end", nil, agent}
          ] do
        over_http = http(method, path, body, from, signer)
        %{"error" => refused} = Jason.decode!(over_http.resp_body)

        assert %{"isError" => true, "content" => [%{"text" => text}]} =
                 result(mcp(call(name, input), from: from, proof: signer || wallet()))

        assert Jason.decode!(text)["error"] == refused, "#{name} #{inspect(input)}"
        {over_http.status, refused["code"]}
      end

    assert codes == [
             {404, "poll_not_found"},
             {404, "poll_not_found"},
             {403, "agent_not_paired"},
             {422, "invalid_poll"},
             {422, "invalid_poll"},
             {422, "invalid_poll"},
             {422, "invalid_poll"},
             {409, "idempotency_conflict"},
             {409, "idempotency_conflict"},
             {403, "agent_not_paired"},
             {404, "poll_not_found"},
             {404, "poll_not_found"},
             {422, "invalid_vote"},
             {422, "invalid_vote"},
             {422, "invalid_vote"},
             {422, "invalid_vote"},
             {422, "invalid_vote"},
             {403, "agent_not_paired"},
             {404, "poll_not_found"},
             {404, "poll_not_found"},
             {403, "not_poll_starter"},
             {422, "poll_closed"}
           ]

    # Nothing refused started, counted or ended anything.
    assert %{"open" => true, "votes_cast" => 0} = read_poll(from, theirs)
    assert %{"open" => true, "votes_cast" => 1} = read_poll(from, id)
    assert %{"votes_cast" => 0} = read_poll(from, closed)
    assert %{"question" => "Tea?"} = read_poll(from, key)
    assert Ash.get(AshTemplate.Polls.Poll, missing, authorize?: false) |> elem(0) == :error
  end

  test "a poll's operation_id answers only the same question, choices and minutes, whichever way each call comes",
       %{from: from} do
    for first <- [:http, :mcp], again <- [:http, :mcp] do
      agent = paired_wallet()
      key = Ecto.UUID.generate()
      poll = %{question: "Lunch?", choices: ["Soup", "Salad"], minutes: 5, operation_id: key}
      assert poll(first, from, agent, poll) == {:sent, key}
      assert poll(again, from, agent, poll) == {:replayed, key}

      for changed <- [%{question: "Dinner?"}, %{choices: ["Salad", "Soup"]}, %{minutes: 6}] do
        assert poll(again, from, agent, Map.merge(poll, changed)) == {:refused, "idempotency_conflict"}
      end
    end
  end

  test "two starts with one operation_id at once start one poll, and both answer it",
       %{from: from} do
    for ways <- [[:http, :http], [:mcp, :mcp], [:http, :mcp], [:mcp, :http]], _ <- 1..3 do
      agent = paired_wallet()
      key = Ecto.UUID.generate()
      poll = %{question: "Once?", choices: ["Yes", "No"], minutes: 5, operation_id: key}
      before = length(Ash.read!(AshTemplate.Polls.Poll, authorize?: false))

      answers =
        ways
        |> Enum.map(fn way -> Task.async(fn -> poll(way, from, agent, poll) end) end)
        |> Task.await_many()

      assert Enum.sort(answers) == [{:replayed, key}, {:sent, key}], inspect(ways)
      assert length(Ash.read!(AshTemplate.Polls.Poll, authorize?: false)) == before + 1
    end
  end

  test "a polls action after the agent's pairing ended is refused as agent_not_paired",
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

    id = start_poll(from, agent)
    theirs = start_poll(from, paired_wallet())

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

    for call <- [
          fn ->
            AshTemplate.Polls.polls_start(
              %{question: "Late?", choices: ["Yes", "No"], minutes: 5, operation_id: key},
              actor: let_in
            )
          end,
          fn -> AshTemplate.Polls.polls_vote(theirs, %{choice: "Soup"}, actor: let_in) end,
          fn -> AshTemplate.Polls.polls_end(id, actor: let_in) end
        ] do
      assert {:error, %Ash.Error.Forbidden{errors: [%NotPaired{code: "agent_not_paired"}]}} =
               call.()
    end

    assert {:ok, nil} = AshTemplate.Polls.get_poll(key)
    assert %{"open" => true, "votes_cast" => 0} = read_poll(from, theirs)
    assert %{"open" => true} = read_poll(from, id)
  end

  test "an agent's own profile and marking its person's activity read answer through /mcp as over HTTP",
       %{from: from} do
    # Before pairing: set through /mcp, read and cleared over HTTP.
    agent = wallet()

    assert %{"isError" => false, "structuredContent" => %{"agent" => set}} =
             result(
               mcp(call("agents_edit_profile", %{name: " Scout ", status: "Reading"}),
                 from: from,
                 proof: agent
               )
             )

    assert %{"name" => "Scout", "status" => "Reading", "wallet_address" => ^agent} = set
    assert Jason.decode!(http(:get, "/api/v1/agents/me", nil, from, agent).resp_body) == %{"agent" => set}

    # A change names only what it changes; an empty one clears it.
    cleared = http(:patch, "/api/v1/agents/me", %{status: ""}, from, agent)
    assert cleared.status == 200, cleared.resp_body
    assert %{"agent" => %{"name" => "Scout", "status" => nil}} = answer = Jason.decode!(cleared.resp_body)

    assert %{"isError" => false, "structuredContent" => ^answer} =
             result(mcp(call("agents_profile", %{}), from: from, proof: agent))

    # Marked read through /mcp, then over HTTP: only the agent's person's.
    %{account: account, agent: paired} = paired_person()
    other = paired_person().account
    notify([account, account, other])
    assert {unread(account), unread(other)} == {2, 1}

    assert %{"isError" => false, "structuredContent" => %{"marked_read" => true}} =
             result(mcp(call("activity_mark_read", %{}), from: from, proof: paired))

    assert {unread(account), unread(other)} == {0, 1}
    notify([account])
    again = http(:post, "/api/v1/activity/read", %{}, from, paired)
    assert {again.status, Jason.decode!(again.resp_body)} == {200, %{"marked_read" => true}}
    assert {unread(account), unread(other)} == {0, 1}
  end

  test "an agent's own profile and marking activity read refuse through /mcp with the code and words HTTP gives",
       %{from: from} do
    agent = wallet()
    unpaired = wallet()
    %{account: account, agent: paired} = paired_person()
    notify([account])

    codes =
      for {name, input, method, path, body, signer} <- [
            {"agents_edit_profile", %{}, :patch, "/api/v1/agents/me", %{}, agent},
            {"agents_edit_profile", %{name: "Fix\u200bture"}, :patch, "/api/v1/agents/me",
             %{name: "Fix\u200bture"}, agent},
            {"agents_edit_profile", %{status: String.duplicate("a", 161)}, :patch,
             "/api/v1/agents/me", %{status: String.duplicate("a", 161)}, agent},
            {"agents_edit_profile", %{name: 5}, :patch, "/api/v1/agents/me", %{name: 5}, agent},
            {"agents_edit_profile", %{name: "Scout", wallet_address: unpaired}, :patch,
             "/api/v1/agents/me", %{name: "Scout", wallet_address: unpaired}, agent},
            {"activity_mark_read", %{}, :post, "/api/v1/activity/read", %{}, unpaired},
            {"activity_mark_read", %{all: true}, :post, "/api/v1/activity/read", %{all: true},
             paired},
            {"activity_mark_read", %{after: "x"}, :post, "/api/v1/activity/read", %{after: "x"},
             paired}
          ] do
        over_http = http(method, path, body, from, signer)
        %{"error" => refused} = Jason.decode!(over_http.resp_body)

        assert %{"isError" => true, "content" => [%{"text" => text}]} =
                 result(mcp(call(name, input), from: from, proof: signer))

        assert Jason.decode!(text)["error"] == refused, "#{name} #{inspect(input)}"
        {over_http.status, refused["code"], Map.has_key?(refused, "details")}
      end

    assert codes == [
             {422, "invalid_profile", false},
             {422, "invalid_profile", true},
             {422, "invalid_profile", true},
             {422, "invalid_profile", true},
             {422, "invalid_profile", true},
             {403, "agent_not_paired", false},
             {422, "invalid_mark_read_request", false},
             {422, "invalid_mark_read_request", false}
           ]

    # A body that is not an object is refused over HTTP too.
    listed = http(:post, "/api/v1/activity/read", [], from, paired)
    assert Jason.decode!(listed.resp_body)["error"]["code"] == "invalid_mark_read_request"

    # Nothing refused changed a profile or marked anything read.
    assert %{"agent" => %{"name" => nil, "status" => nil}} =
             Jason.decode!(http(:get, "/api/v1/agents/me", nil, from, agent).resp_body)

    assert unread(account) == 1
  end

  test "marking activity read after the agent's pairing ended is refused as agent_not_paired",
       %{from: from} do
    %{account: account, agent: agent, pairing: pairing, owner: owner} = paired_person()
    notify([account])

    # The agent as its signed request was let in, then the person unpairs it.
    {:ok, active} = RegentAgents.Authority.resolve(Repo, agent)

    let_in =
      AshTemplate.Actors.Agent.paired(
        AshTemplate.Agents.sign_in_agent!(agent, actor: %System{}),
        account,
        active
      )

    assert :ok = RegentAgents.unpair_agent(pairing, actor: owner)

    assert {:error, %Ash.Error.Forbidden{errors: [%NotPaired{code: "agent_not_paired"}]}} =
             AshTemplate.Activity.activity_mark_read(%{}, actor: let_in)

    assert unread(account) == 1
    assert http(:post, "/api/v1/activity/read", %{}, from, agent).status == 403
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

  # The conversation `agent`'s person opened over HTTP with `other`'s person, from
  # a room message `other` wrote: its id.
  defp conversation(from, agent, other) do
    theirs = said(from, other, "general", "Write to me")
    conn = http(:post, "/api/v1/dms", %{message_id: theirs}, from, agent)
    assert conn.status == 200, conn.resp_body
    Jason.decode!(conn.resp_body)["conversation"]["id"]
  end

  # One direct message with `key` in the conversation `id`, through `way`, as the
  # answer's meaning: sent, the earlier message answered again, or refused with its code.
  defp dm(:http, from, agent, id, text, key) do
    conn = http(:post, "/api/v1/dms/#{id}/messages", %{body: text, operation_id: key}, from, agent)

    case {conn.status, Jason.decode!(conn.resp_body)} do
      {201, %{"message" => %{"id" => message}}} -> {:sent, message}
      {200, %{"message" => %{"id" => message}}} -> {:replayed, message}
      {_status, %{"error" => %{"code" => code}}} -> {:refused, code}
    end
  end

  defp dm(:mcp, from, agent, id, text, key) do
    conn =
      mcp(call("dms_send", %{conversation: id, body: text, operation_id: key}),
        from: from,
        proof: agent
      )

    case result(conn) do
      %{"isError" => false, "structuredContent" => %{"replayed" => false, "message" => message}} ->
        {:sent, message["id"]}

      %{"isError" => false, "structuredContent" => %{"replayed" => true, "message" => message}} ->
        {:replayed, message["id"]}

      %{"isError" => true, "content" => [%{"text" => text}]} ->
        {:refused, Jason.decode!(text)["error"]["code"]}
    end
  end

  # The conversation `id`'s messages, newest first, as HTTP reads them for `agent`'s person.
  defp history(from, agent, id) do
    conn = http(:post, "/api/v1/dms/#{id}/history", %{}, from, agent)
    assert conn.status == 200, conn.resp_body
    Jason.decode!(conn.resp_body)["messages"]
  end

  # A new chat `agent` starts for its person over HTTP, with one message: its id.
  defp new_chat(from, agent) do
    conn = http(:post, "/api/v1/chat/messages", %{text: "Opening", operation_id: Ecto.UUID.generate()}, from, agent)
    assert conn.status == 201, conn.resp_body
    Jason.decode!(conn.resp_body)["message"]["conversation_id"]
  end

  # One message to the assistant with `key` in the chat `id`, or a new chat when it is
  # nil, through `way`, as the answer's meaning: sent, the earlier message answered
  # again, or refused with its code.
  defp chat(:http, from, agent, id, text, key) do
    body = if id, do: %{conversation_id: id, text: text, operation_id: key}, else: %{text: text, operation_id: key}
    conn = http(:post, "/api/v1/chat/messages", body, from, agent)

    case {conn.status, Jason.decode!(conn.resp_body)} do
      {201, %{"message" => %{"id" => message}}} -> {:sent, message}
      {200, %{"message" => %{"id" => message}}} -> {:replayed, message}
      {_status, %{"error" => %{"code" => code}}} -> {:refused, code}
    end
  end

  defp chat(:mcp, from, agent, id, text, key) do
    input = if id, do: %{conversation_id: id, text: text, operation_id: key}, else: %{text: text, operation_id: key}

    case result(mcp(call("chat_send", input), from: from, proof: agent)) do
      %{"isError" => false, "structuredContent" => %{"replayed" => false, "message" => message}} ->
        {:sent, message["id"]}

      %{"isError" => false, "structuredContent" => %{"replayed" => true, "message" => message}} ->
        {:replayed, message["id"]}

      %{"isError" => true, "content" => [%{"text" => text}]} ->
        {:refused, Jason.decode!(text)["error"]["code"]}
    end
  end

  # The chat `id`'s messages, newest first, as HTTP reads them for `agent`'s person.
  defp chat_history(from, agent, id) do
    conn = http(:post, "/api/v1/chat/#{id}/history", %{}, from, agent)
    assert conn.status == 200, conn.resp_body
    Jason.decode!(conn.resp_body)["messages"]
  end

  # A new poll `agent` starts for its person over HTTP: its id.
  defp start_poll(from, agent) do
    body = %{question: "Lunch?", choices: ["Soup", "Salad"], minutes: 5, operation_id: Ecto.UUID.generate()}
    conn = http(:post, "/api/v1/polls", body, from, agent)
    assert conn.status == 201, conn.resp_body
    Jason.decode!(conn.resp_body)["poll"]["id"]
  end

  # One start of `poll` through `way`, as the answer's meaning: started, the
  # earlier poll answered again, or refused with its code.
  defp poll(:http, from, agent, poll) do
    conn = http(:post, "/api/v1/polls", poll, from, agent)

    case {conn.status, Jason.decode!(conn.resp_body)} do
      {201, %{"poll" => %{"id" => id}}} -> {:sent, id}
      {200, %{"poll" => %{"id" => id}}} -> {:replayed, id}
      {_status, %{"error" => %{"code" => code}}} -> {:refused, code}
    end
  end

  defp poll(:mcp, from, agent, poll) do
    case result(mcp(call("polls_start", poll), from: from, proof: agent)) do
      %{"isError" => false, "structuredContent" => %{"replayed" => false, "poll" => %{"id" => id}}} ->
        {:sent, id}

      %{"isError" => false, "structuredContent" => %{"replayed" => true, "poll" => %{"id" => id}}} ->
        {:replayed, id}

      %{"isError" => true, "content" => [%{"text" => text}]} ->
        {:refused, Jason.decode!(text)["error"]["code"]}
    end
  end

  # The poll `id` as anyone reads it over HTTP.
  defp read_poll(from, id) do
    conn = http(:get, "/api/v1/polls/#{id}", nil, from, nil)
    assert conn.status == 200, conn.resp_body
    Jason.decode!(conn.resp_body)["poll"]
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

  # A new person's account here, with one agent paired to it.
  defp paired_person do
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

    %{account: account, agent: agent, pairing: pairing, owner: owner}
  end

  # One unread notification for each account in `accounts`.
  defp notify(accounts) do
    Ash.bulk_create!(
      for(account <- accounts, do: %{human_account_id: account.id, title: "Notice", path: "/notes"}),
      AshTemplate.Activity.Notification,
      :notify,
      actor: %System{}
    )
  end

  defp unread(account) do
    {:ok, count} =
      AshTemplate.Activity.count_unread(actor: AshTemplate.Actors.Human.for_account(account))

    count
  end

  defp wallet, do: "0x" <> Base.encode16(:crypto.strong_rand_bytes(20), case: :lower)
end
