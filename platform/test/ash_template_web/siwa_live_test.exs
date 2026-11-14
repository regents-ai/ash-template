defmodule AshTemplateWeb.SiwaLiveTest do
  # The SIWA pages (AshTemplateWeb.SiwaLive), connected as in a browser, against
  # a stand-in for the sign-in service. The control token is kept on this
  # machine as the trade leaves it (AshTemplateWeb.SiwaSessionTest), and the
  # browser's side of a trade is the `traded` event its sign-in bridge sends.
  use ExUnit.Case, async: false

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  alias AshTemplate.Accounts.{SessionAuthority, VerifiedSession}
  alias AshTemplate.SiwaControl
  alias AshTemplate.SiwaControl.Tokens

  @endpoint AshTemplateWeb.Endpoint
  @base "/api/control/v1"
  @wallet "0x" <> String.duplicate("7", 40)
  @at "2026-11-14T10:00:00Z"
  @customer %{
    "id" => "6b1f0f8e-3d4c-4f3e-9a51-0d8d1f5a2b10",
    "name" => "Acme",
    "kind" => "paid",
    "capCents" => nil,
    "createdAt" => @at,
    "updatedAt" => @at
  }
  # A period that has counted one agent past the 1,000 it includes.
  @usage %{
    "periodStartsAt" => "2026-11-01T00:00:00Z",
    "periodEndsAt" => "2026-12-01T00:00:00Z",
    "activeAgents" => 1_001,
    "includedAgents" => 1_000,
    "feeCents" => "9909.9",
    "capCents" => nil,
    "maxAgents" => nil
  }
  @site %{
    "id" => "0e3a8f52-6f7b-4c11-8d2e-5b9c7a1d4e63",
    "name" => "Docs",
    "audience" => "acme-docs",
    "environment" => "sandbox",
    "origins" => ["http://localhost:4000"],
    "originProof" => nil,
    "archivedAt" => nil,
    "createdAt" => @at,
    "updatedAt" => @at
  }
  @key %{
    "id" => "9c4d2b7e-1a3f-4e5d-8b6c-7f0a1e2d3c4b",
    "prefix" => "siwa_sk_test_AbCdEf",
    "createdAt" => @at,
    "revokedAt" => nil
  }

  setup do
    owner = Ecto.Adapters.SQL.Sandbox.start_owner!(AshTemplate.Repo, shared: true)
    Req.Test.set_req_test_to_shared()

    on_exit(fn ->
      Req.Test.set_req_test_to_private()
      Ecto.Adapters.SQL.Sandbox.stop_owner(owner)
    end)

    {:ok, account, []} =
      VerifiedSession.establish(%RegentPrivy.Session{
        app_id: "test-app",
        session_id: "siwa-live",
        privy_user_id: "did:privy:siwa-live",
        wallet_address: @wallet,
        wallet_addresses: [@wallet],
        linked_socials: [],
        issued_at: System.system_time(:second),
        expires_at: System.system_time(:second) + 3600
      })

    {:bootstrap, claim} = SessionAuthority.renew(nil)
    {:ok, :bind, claim} = SessionAuthority.sign_in(claim, account.id)
    topic = SessionAuthority.topic(claim.lineage)
    keep = fn -> Tokens.keep(topic, account.id, "control-token", DateTime.add(DateTime.utc_now(), 900)) end
    keep.()
    on_exit(fn -> Tokens.forget(topic) end)

    browser =
      build_conn()
      |> Plug.Conn.put_req_header("accept", "text/html")
      |> Plug.Test.init_test_session(SessionAuthority.session(claim))
      |> Plug.Conn.put_private(:live_view_connect_info, %{})

    %{browser: browser, topic: topic, keep: keep}
  end

  # The service answers each `{method, path}` from `answers`, the path with its
  # query when it has one, and says what it was asked; anything else it was not
  # expected to be asked.
  defp service(answers) do
    test = self()

    Req.Test.stub(SiwaControl, fn conn ->
      {:ok, sent, conn} = Plug.Conn.read_body(conn)
      path = if conn.query_string == "", do: conn.request_path, else: "#{conn.request_path}?#{conn.query_string}"
      send(test, {:asked, conn.method, path, sent})
      {status, body} = Map.fetch!(answers, {conn.method, path})
      conn |> Plug.Conn.put_status(status) |> Req.Test.json(body)
    end)
  end

  defp ok(status \\ 200, code, data), do: {status, %{code: code, data: data}}

  defp refused(status, code, fields \\ nil) do
    error = %{code: code, message: "refused", hint: nil}
    {status, %{error: if(fields, do: Map.put(error, :fields, fields), else: error)}}
  end

  defp company(customer \\ @customer, usage \\ nil) do
    account = %{did: "did:privy:siwa-live", customer: customer, usage: usage}
    %{{"GET", @base <> "/account"} => ok("account", account)}
  end

  defp agent(chain_id, digit, site_id, at) do
    %{
      subject: "eip155:#{chain_id}:0x" <> String.duplicate(digit, 40),
      firstVerifiedAt: at,
      firstSiteId: site_id
    }
  end

  # A billed company's Overview: the period above, its one site, and the first
  # page of agents, one first seen at a site since archived.
  defp billed(customer \\ @customer) do
    Map.merge(company(customer, @usage), %{
      {"GET", @base <> "/sites"} => ok("sites", %{sites: [@site]}),
      {"GET", @base <> "/agents"} =>
        ok("agents", %{
          agents: [
            agent(8453, "a", @site["id"], "2026-11-14T09:00:00Z"),
            agent(1, "b", Ecto.UUID.generate(), "2026-11-02T09:00:00Z")
          ],
          next: "page-2"
        })
    })
  end

  defp site_answers(keys \\ []) do
    Map.merge(company(), %{
      {"GET", "#{@base}/sites/#{@site["id"]}"} => ok("site", @site),
      {"GET", "#{@base}/sites/#{@site["id"]}/keys"} => ok("site_keys", %{keys: keys})
    })
  end

  defp open(browser, path) do
    {:ok, view, _html} = live(browser, path)
    render_async(view)
    view
  end

  test "a person with no company names it and lands on Sites, where a refused field is shown beside it and a new site opens",
       %{browser: browser} do
    service(company(nil))
    view = open(browser, "/siwa/sites")
    assert has_element?(view, "#siwa-company-form")

    service(
      Map.merge(company(), %{
        {"POST", @base <> "/customer"} => ok(201, "customer_created", @customer),
        {"GET", @base <> "/sites"} => ok("sites", %{sites: []})
      })
    )

    view |> form("#siwa-company-form", company: %{name: "Acme"}) |> render_submit()
    render_async(view)
    assert_received {:asked, "POST", "/api/control/v1/customer", sent}
    assert Jason.decode!(sent) == %{"name" => "Acme"}
    assert has_element?(view, "#siwa-site-form")

    site = %{
      name: "Docs",
      audience: "acme-docs",
      environment: "sandbox",
      origins: "http://localhost:4000\r\n\r\n  http://localhost:4001  "
    }

    service(%{
      {"POST", @base <> "/sites"} =>
        refused(422, "control_fields_invalid", %{origins: ["lists an origin twice"]})
    })

    view |> form("#siwa-site-form", site: site) |> render_submit()
    render_async(view)
    assert_received {:asked, "POST", "/api/control/v1/sites", sent}

    assert Jason.decode!(sent) == %{
             "name" => "Docs",
             "audience" => "acme-docs",
             "environment" => "sandbox",
             "origins" => ["http://localhost:4000", "http://localhost:4001"]
           }

    assert has_element?(view, "#siwa-site-origins[aria-invalid='true']")
    assert has_element?(view, "#siwa-site-origins-errors p")
    assert has_element?(view, "#siwa-site-audience[aria-invalid='false']")
    assert has_element?(view, "#siwa-site-audience[value='acme-docs']")

    service(Map.put(site_answers(), {"POST", @base <> "/sites"}, ok(201, "site_created", @site)))
    view |> form("#siwa-site-form", site: site) |> render_submit()
    render_async(view)
    assert_patch(view, "/siwa/sites/#{@site["id"]}")
    render_async(view)
    assert has_element?(view, "#siwa-audience")
  end

  test "a new key goes to the browser once and nowhere into the page, and a revoked key stays listed",
       %{browser: browser} do
    secret = "siwa_sk_test_" <> String.duplicate("s", 43)
    service(site_answers())
    view = open(browser, "/siwa/sites/#{@site["id"]}")

    keys = "#{@base}/sites/#{@site["id"]}/keys"
    service(Map.put(site_answers(), {"POST", keys}, ok(201, "site_key_created", Map.put(@key, "key", secret))))
    view |> element("#siwa-make-key") |> render_click()
    render_async(view)

    assert_push_event(view, "siwa-key:reveal", %{key: ^secret})
    assert has_element?(view, "#siwa-key-reveal")
    assert has_element?(view, "#siwa-revoke-#{@key["id"]}")
    refute render(view) =~ secret
    refute inspect(:sys.get_state(view.pid), limit: :infinity, printable_limit: :infinity) =~ secret

    view |> element("#siwa-key-done") |> render_click()
    refute has_element?(view, "#siwa-key-reveal")

    revoked = Map.put(@key, "revokedAt", @at)
    service(Map.put(site_answers(), {"DELETE", "#{keys}/#{@key["id"]}"}, ok("site_key_revoked", revoked)))
    view |> element("#siwa-revoke-#{@key["id"]}") |> render_click()
    render_async(view)

    refute has_element?(view, "#siwa-revoke-#{@key["id"]}")
    assert has_element?(view, "#siwa-key-#{@key["id"]}")
  end

  test "a site's name and origins are saved together, and Archive goes back to Sites", %{browser: browser} do
    service(site_answers())
    view = open(browser, "/siwa/sites/#{@site["id"]}")
    path = "#{@base}/sites/#{@site["id"]}"
    renamed = %{@site | "name" => "Docs site"}

    service(Map.put(site_answers(), {"PATCH", path}, ok("site_updated", renamed)))
    view |> form("#siwa-details-form", details: %{name: "Docs site"}) |> render_submit()
    render_async(view)
    assert_received {:asked, "PATCH", ^path, sent}
    assert Jason.decode!(sent) == %{"name" => "Docs site", "origins" => @site["origins"]}
    assert has_element?(view, "#siwa-details-notice")
    assert has_element?(view, "#siwa-details-name[value='Docs site']")

    service(
      Map.merge(site_answers(), %{
        {"DELETE", path} => ok("site_archived", %{renamed | "archivedAt" => @at}),
        {"GET", @base <> "/sites"} => ok("sites", %{sites: []})
      })
    )

    view |> element("#siwa-archive") |> render_click()
    render_async(view)
    assert_patch(view, "/siwa/sites")
  end

  test "with no token the page asks the browser to trade and carries on; a change SIWA still refuses after a trade says to sign in again",
       %{browser: browser, topic: topic, keep: keep} do
    Tokens.forget(topic)
    service(company(nil))
    view = open(browser, "/siwa/sites")
    assert_push_event(view, "siwa-control:trade", %{})
    refute_received {:asked, _method, _path, _sent}

    keep.()
    view |> with_target("#siwa-page") |> render_hook("traded", %{"outcome" => "ready"})
    render_async(view)
    assert has_element?(view, "#siwa-company-form")

    service(Map.put(company(nil), {"POST", @base <> "/customer"}, refused(401, "control_token_invalid")))
    view |> form("#siwa-company-form", company: %{name: "Acme"}) |> render_submit()
    render_async(view)
    assert_push_event(view, "siwa-control:trade", %{})

    view |> with_target("#siwa-page") |> render_hook("traded", %{"outcome" => "ready"})
    render_async(view)
    assert has_element?(view, "#siwa-ended")
    assert_received {:asked, "POST", "/api/control/v1/customer", _sent}
    assert_received {:asked, "POST", "/api/control/v1/customer", _sent}
    refute_received {:asked, "POST", "/api/control/v1/customer", _sent}
  end

  test "SIWA off, out of reach or a failed trade shows it, and Try again reads again", %{
    browser: browser,
    topic: topic
  } do
    service(%{{"GET", @base <> "/account"} => refused(503, "control_not_configured")})
    view = open(browser, "/siwa/settings")
    assert has_element?(view, "#siwa-unavailable")

    service(company())
    view |> element("#siwa-unavailable button[phx-click='retry']") |> render_click()
    render_async(view)
    assert has_element?(view, "#siwa-company-form")

    Tokens.forget(topic)
    view = open(browser, "/siwa/sites")
    assert_push_event(view, "siwa-control:trade", %{})
    view |> with_target("#siwa-page") |> render_hook("traded", %{"outcome" => "unavailable"})
    assert has_element?(view, "#siwa-unavailable")

    view = open(browser, "/siwa/sites")
    assert_push_event(view, "siwa-control:trade", %{})
    view |> with_target("#siwa-page") |> render_hook("traded", %{"outcome" => "busy"})
    assert has_element?(view, "#siwa-busy button[phx-click='retry']")
  end

  test "a site SIWA doesn't know is refused on the page", %{browser: browser} do
    service(Map.put(company(), {"GET", "#{@base}/sites/#{@site["id"]}"}, refused(404, "site_not_found")))
    view = open(browser, "/siwa/sites/#{@site["id"]}")

    assert has_element?(view, "#siwa-refused")
    refute has_element?(view, "#siwa-keys-title")
  end

  test "only an ended token asks for a trade; any other refusal is shown", %{browser: browser} do
    service(%{{"GET", @base <> "/account"} => refused(401, "privy_proof_invalid")})
    view = open(browser, "/siwa/sites")

    assert has_element?(view, "#siwa-refused")
    refute_push_event(view, "siwa-control:trade", %{})
  end

  test "Settings shows the company, its owner and support, and renames the company", %{browser: browser} do
    service(company())
    view = open(browser, "/siwa/settings")

    assert has_element?(view, "#siwa-company-name[value='Acme']")
    # With no name of their own, the owner shows only as their wallet.
    assert has_element?(view, "#siwa-owner-wallet")
    refute has_element?(view, "#siwa-owner-name")
    assert has_element?(view, "#siwa-support[href='mailto:build@regents.sh']")

    service(Map.put(company(), {"PATCH", @base <> "/customer"}, ok("customer_updated", %{@customer | "name" => "Acme Labs"})))
    view |> form("#siwa-company-form", company: %{name: "Acme Labs"}) |> render_submit()
    render_async(view)

    assert has_element?(view, "#siwa-company-notice")
    assert has_element?(view, "#siwa-company-name[value='Acme Labs']")
  end

  test "Overview before billing starts says so, asks for no agents, and sets, refuses and removes a cap",
       %{browser: browser} do
    service(company())
    view = open(browser, "/siwa")
    assert has_element?(view, "#siwa-billing")
    refute has_element?(view, "#siwa-usage")
    refute has_element?(view, "#siwa-agents-panel")
    assert_received {:asked, "GET", "/api/control/v1/account", _sent}
    refute_received {:asked, _method, _path, _sent}

    # What isn't an amount in dollars is never sent.
    view |> form("#siwa-cap-form", cap: %{amount: "five hundred"}) |> render_submit()
    assert has_element?(view, "#siwa-cap-amount[aria-invalid='true']")
    refute_received {:asked, _method, _path, _sent}

    too_low = refused(422, "control_fields_invalid", %{capCents: ["must be greater than or equal to 9900"]})
    service(Map.put(company(), {"PUT", @base <> "/cap"}, too_low))
    view |> form("#siwa-cap-form", cap: %{amount: "50"}) |> render_submit()
    render_async(view)
    assert_received {:asked, "PUT", "/api/control/v1/cap", sent}
    assert Jason.decode!(sent) == %{"capCents" => 5_000}
    # The least cap shows beside the field; the service's own sentence doesn't.
    assert view |> element("#siwa-cap-amount-errors") |> render() =~ "$99.00"
    refute render(view) =~ "must be greater than"

    capped = %{@customer | "capCents" => 125_050}
    service(Map.put(company(), {"PUT", @base <> "/cap"}, ok("cap_updated", %{customer: capped, usage: nil})))
    view |> form("#siwa-cap-form", cap: %{amount: " $1,250.5 "}) |> render_submit()
    render_async(view)
    assert_received {:asked, "PUT", "/api/control/v1/cap", sent}
    assert Jason.decode!(sent) == %{"capCents" => 125_050}
    assert has_element?(view, "#siwa-cap-amount[aria-invalid='false'][value='1250.50']")
    assert has_element?(view, "#siwa-cap-notice")

    service(Map.put(company(), {"PUT", @base <> "/cap"}, ok("cap_updated", %{customer: @customer, usage: nil})))
    view |> element("#siwa-cap-remove") |> render_click()
    render_async(view)
    assert_received {:asked, "PUT", "/api/control/v1/cap", sent}
    assert Jason.decode!(sent) == %{"capCents" => nil}
    refute has_element?(view, "#siwa-cap-remove")
    assert has_element?(view, "#siwa-cap-amount[value='']")
  end

  test "Overview of a billed period shows its figures, and lists its agents a page at a time by their first site's name",
       %{browser: browser} do
    capped = %{@customer | "capCents" => 50_000}
    usage = %{@usage | "capCents" => 50_000, "maxAgents" => 5_050}
    answers = Map.merge(billed(capped), company(capped, usage))
    service(answers)
    view = open(browser, "/siwa")
    render_async(view)

    assert view |> element("#siwa-period") |> render() =~ "1–30 Nov 2026"
    assert view |> element("#siwa-agents-count") |> render() =~ "1,001"
    assert view |> element("#siwa-fee") |> render() =~ "$99.099"
    assert view |> element("#siwa-cap") |> render() =~ "$500.00"
    assert view |> element("#siwa-usage") |> render() =~ "5,050"
    assert has_element?(view, "#siwa-cap-amount[value='500.00']")

    on_base = "#siwa-agent-base-0x" <> String.duplicate("a", 40)
    on_ethereum = "#siwa-agent-ethereum-0x" <> String.duplicate("b", 40)
    assert view |> element(on_base) |> render() =~ @site["name"]
    assert has_element?(view, on_base <> "-wallet")
    refute view |> element(on_ethereum) |> render() =~ @site["name"]

    assert_received {:asked, "GET", "/api/control/v1/account", _sent}
    assert_received {:asked, "GET", "/api/control/v1/sites", _sent}
    assert_received {:asked, "GET", "/api/control/v1/agents", _sent}

    last = %{agents: [agent(8453, "c", @site["id"], "2026-11-01T09:00:00Z")], next: nil}
    service(Map.put(answers, {"GET", @base <> "/agents?after=page-2"}, ok("agents", last)))
    view |> element("#siwa-agents-more") |> render_click()
    render_async(view)

    # The next page joins the list under the first, named from the same sites.
    assert view |> element("#siwa-agent-base-0x" <> String.duplicate("c", 40)) |> render() =~ @site["name"]
    assert has_element?(view, on_base)
    refute has_element?(view, "#siwa-agents-more")
    assert_received {:asked, "GET", "/api/control/v1/agents?after=page-2", _sent}
    refute_received {:asked, "GET", "/api/control/v1/sites", _sent}

    # A cap below the fee so far is refused with the least whole cent above it.
    below = refused(422, "control_fields_invalid", %{capCents: ["is below the fee this period has already reached"]})
    service(Map.put(answers, {"PUT", @base <> "/cap"}, below))
    view |> form("#siwa-cap-form", cap: %{amount: "99"}) |> render_submit()
    render_async(view)
    assert view |> element("#siwa-cap-amount-errors") |> render() =~ "$99.10"
    assert has_element?(view, "#siwa-cap-amount[value='99']")
  end

  test "a period with no agents yet asks for none", %{browser: browser} do
    service(company(@customer, %{@usage | "activeAgents" => 0, "feeCents" => "9900.0"}))
    view = open(browser, "/siwa")
    render_async(view)

    assert view |> element("#siwa-fee") |> render() =~ "$99.00"
    assert has_element?(view, "#siwa-agents-none")
    refute has_element?(view, "#siwa-agents-box")
    assert_received {:asked, "GET", "/api/control/v1/account", _sent}
    refute_received {:asked, _method, _path, _sent}
  end

  test "an agent that isn't a wallet on a chain SIWA signs in on leaves the list unread, and Try again reads it again",
       %{browser: browser} do
    sepolia = %{agents: [agent(84_532, "a", @site["id"], @at)], next: nil}
    service(Map.put(billed(), {"GET", @base <> "/agents"}, ok("agents", sepolia)))
    view = open(browser, "/siwa")
    render_async(view)

    assert has_element?(view, "#siwa-usage")
    assert has_element?(view, "#siwa-agents-box[data-state='error']")
    refute has_element?(view, "#siwa-agents-more")

    service(billed())
    view |> element("#siwa-agents-box button[phx-click='list_agents']") |> render_click()
    render_async(view)

    assert has_element?(view, "#siwa-agents-box[data-state='ready']")
    assert has_element?(view, "#siwa-agent-base-0x" <> String.duplicate("a", 40))
    assert has_element?(view, "#siwa-agents-more")
  end

  test "signed out, the pages offer sign-in and ask SIWA nothing" do
    service(company())

    for path <- ["/siwa", "/siwa/sites", "/siwa/sites/#{@site["id"]}", "/siwa/settings"] do
      html = build_conn() |> get(path) |> html_response(200)
      assert html |> LazyHTML.from_document() |> LazyHTML.query("#siwa-signed-out") |> Enum.any?()
    end

    refute_received {:asked, _method, _path, _sent}
  end
end
