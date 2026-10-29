defmodule AshTemplateWeb.ClaudeConnectorTest do
  # The Claude connector through this site's own endpoint, router, sign-in and
  # agent records: off, nothing about agents changes; on, one connected account
  # pairs one hosted agent, checks in, and loses access when it disconnects.
  # The hosted signer and the SIWA service are stubbed; the rest is the site's.
  use ExUnit.Case, async: false

  import Plug.Conn
  import Plug.Test

  alias AshTemplate.Accounts.{SessionAuthority, VerifiedSession}
  alias AshTemplateWeb.PairingBox

  @endpoint AshTemplateWeb.Endpoint
  @wallet "0x2222222222222222222222222222222222222222"
  @site_key String.duplicate("k", 32)
  @signed %{
    "x-siwa-signature" => "sig1=:c2lnbmVk:",
    "x-siwa-signature-input" =>
      ~s|sig1=("@method" "@path");created=1;expires=2;nonce="n";keyid="k"|,
    "x-siwa-receipt" => "receipt",
    "x-key-id" => "k",
    "x-timestamp" => "1",
    "x-agent-wallet-address" => @wallet,
    "x-agent-chain-id" => "8453"
  }
  # Every request the hosted signer may be asked to sign for this site.
  @signable [
    {"GET", "/api/agents/v1/whoami"},
    {"GET", "/api/agents/v1/me"},
    {"POST", "/api/agents/v1/pair"}
  ]

  setup do
    owner = Ecto.Adapters.SQL.Sandbox.start_owner!(AshTemplate.Repo, shared: true)
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(owner) end)
    put_env(:regent_agents, :req_options, plug: {Req.Test, RegentAgents.Broker})
    test = self()

    # The SIWA service verifies every signed request as the one hosted wallet's.
    Req.Test.stub(RegentAgents.Broker, fn conn ->
      {:ok, body, conn} = read_body(conn)
      send(test, {:verify, conn.req_headers, body, Jason.decode!(body)})

      Req.Test.json(conn, %{
        "code" => "http_envelope_valid",
        "data" => %{
          "verified" => true,
          "principal" => %{
            "kind" => "wallet",
            "wallet_address" => @wallet,
            "chain_id" => 8453,
            "audience" => "ash-template"
          },
          "agentRegistration" => nil,
          "agentBook" => nil
        }
      })
    end)

    :ok
  end

  describe "with the connector off, as config/test.exs and production leave it" do
    test "its addresses are not found and Claude is neither offered nor accepted" do
      assert post_mcp(rpc("ping"), nil).status == 404
      assert @endpoint.call(conn(:get, "/.well-known/oauth-authorization-server"), []).status == 404
      assert @endpoint.call(conn(:post, "/oauth/register", %{}), []).status == 404

      refute :claude in RegentAgents.Harness.offered()
      refute "claude" in Enum.map(PairingBox.choices(), & &1.value)
    end

    test "an agent's sign-in and pairing work as before, and a Claude pairing is refused" do
      subject = "did:privy:connector-off"
      sign_in!(subject)

      whoami = signed(:get, "/api/agents/v1/whoami")
      assert whoami.status == 200
      assert Jason.decode!(whoami.resp_body)["data"]["status"] == "not_paired"

      refused = pair_request(code!(subject), "claude")
      assert refused.status in 400..499
      assert agents(subject) == []

      paired = pair_request(code!(subject), "codex")
      assert paired.status in 200..201, paired.resp_body
      assert [%{harness: :codex, wallet: @wallet}] = agents(subject)
    end
  end

  describe "with the connector on" do
    setup :connector_on

    test "pair_identity makes one paired agent of the authorizing account, from that account's own code only" do
      subject = "did:privy:connector-pair"
      sign_in!(subject)
      %{access: token} = connect!(subject)

      # Another account's code is refused before anything is signed.
      sign_in!("did:privy:connector-other")
      other = code!("did:privy:connector-other")
      assert %{"isError" => true} = tool(token, "pair_identity", pair_args(other))
      assert signer_asks() == []
      assert agents(subject) == [] and agents("did:privy:connector-other") == []

      arguments = pair_args(code!(subject))
      assert %{"isError" => false} = tool(token, "pair_identity", arguments)

      # The POST the hosted signer signed is verified with its exact body.
      assert [%{"operation" => "sign", "request" => signed}] =
               for({_, _, %{"operation" => "sign"} = ask} <- signer_asks(), do: ask)

      assert {signed["method"], signed["path"]} == {"POST", "/api/agents/v1/pair"}
      assert Jason.decode!(signed["body"]) == arguments
      assert_received {:verify, _headers, _raw, payload}
      assert payload["body_digest"] == Siwa.content_digest_for_body(signed["body"])

      assert [%{harness: :claude, wallet: @wallet, name: "Claude"}] = agents(subject)
    end

    test "the hosted signer signs only the identity requests, as the account's one identity, and the connection's token stays here" do
      subject = "did:privy:connector-allowlist"
      sign_in!(subject)
      %{access: token} = connect!(subject)

      assert %{"isError" => false} = tool(token, "register_identity")
      assert %{"isError" => false} = tool(token, "get_identity")
      assert %{"isError" => false} = tool(token, "pair_identity", pair_args(code!(subject)))
      assert %{"isError" => false} = tool(token, "check_in")
      assert %{"error" => _} = json(post_mcp(rpc("tools/call", %{"name" => "post"}), token))

      key = RegentMCPAgents.identity_key("ash-template", subject)
      asked = signer_asks()

      for {auth, raw, ask} <- asked do
        assert auth == ["Bearer " <> @site_key]
        assert ask["identity_key"] == key
        refute raw =~ token
      end

      signed = for {_, _, %{"operation" => "sign", "request" => r}} <- asked, do: r
      assert length(signed) == 3
      assert Enum.map(signed, &{&1["method"], &1["path"]}) -- @signable == []

      for _ <- signed do
        assert_received {:verify, headers, raw, _payload}
        refute raw =~ token
        refute Enum.any?(headers, fn {_name, value} -> value =~ token end)
      end
    end

    test "reconnecting or refreshing keeps the one hosted identity and the one agent" do
      subject = "did:privy:connector-again"
      sign_in!(subject)
      first = connect!(subject)
      assert %{"isError" => false} = tool(first.access, "pair_identity", pair_args(code!(subject)))
      [%{id: agent_id}] = agents(subject)

      again = connect!(subject)
      assert {200, %{"access_token" => refreshed}} = refresh(first.client_id, first.refresh)

      for token <- [again.access, refreshed] do
        assert %{"structuredContent" => %{"paired" => true, "identity_id" => id}} =
                 tool(token, "get_identity")

        assert id == RegentMCPAgents.identity_key("ash-template", subject)
        assert %{"isError" => false} = tool(token, "check_in")
      end

      assert [%{id: ^agent_id}] = agents(subject)
    end

    test "only a check-in moves when the agent was last in touch" do
      subject = "did:privy:connector-touch"
      sign_in!(subject)
      %{client_id: client, access: token, refresh: refresh_token} = connect!(subject)
      assert %{"isError" => false} = tool(token, "pair_identity", pair_args(code!(subject)))
      [%{last_contact_at: paired_at}] = agents(subject)

      assert post_mcp(rpc("initialize", %{"protocolVersion" => "2025-06-18"}), token).status ==
               200

      assert post_mcp(rpc("ping"), token).status == 200
      assert {200, %{"access_token" => refreshed}} = refresh(client, refresh_token)
      assert %{"isError" => false} = tool(refreshed, "get_identity")
      assert %{"isError" => false} = tool(refreshed, "register_identity")
      assert [%{last_contact_at: ^paired_at}] = agents(subject)

      assert %{"isError" => false} = tool(refreshed, "check_in")
      assert [%{last_contact_at: checked_in}] = agents(subject)
      assert DateTime.after?(checked_in, paired_at)
    end

    test "unpairing on the Account page holds: a check-in is refused and pairs nothing again" do
      subject = "did:privy:connector-unpair"
      sign_in!(subject)
      %{access: token} = connect!(subject)
      assert %{"isError" => false} = tool(token, "pair_identity", pair_args(code!(subject)))
      [agent] = agents(subject)

      :ok = RegentAgents.unpair_agent!(agent, actor: person(subject))

      assert %{"isError" => true} = tool(token, "check_in")
      assert %{"structuredContent" => %{"paired" => false}} = tool(token, "get_identity")
      assert agents(subject) == []
    end

    test "disconnecting at Connected apps revokes the app's tokens: its next call is asked to sign in" do
      subject = "did:privy:connector-revoke"
      browser = sign_in!(subject)
      %{client_id: client, access: token, refresh: refresh_token} = connect!(subject)
      assert %{"isError" => false} = tool(token, "register_identity")

      csrf = Plug.CSRFProtection.get_csrf_token()

      revoked =
        conn(:post, "/oauth/connections/revoke", %{"client_id" => client, "_csrf_token" => csrf})
        |> init_test_session(Map.put(browser, "_csrf_token", Plug.CSRFProtection.dump_state()))
        |> put_req_header("accept", "text/html")
        |> @endpoint.call([])

      assert revoked.status == 303
      assert get_resp_header(revoked, "location") == ["/oauth/connections"]

      refused = post_mcp(rpc("tools/call", %{"name" => "check_in", "arguments" => %{}}), token)
      assert refused.status == 401
      assert [_challenge] = get_resp_header(refused, "www-authenticate")
      assert {400, %{"error" => "invalid_grant"}} = refresh(client, refresh_token)
    end
  end

  # Switches the connector on for one test as config/runtime.exs does with
  # ASH_TEMPLATE_CLAUDE_CONNECTOR_ENABLED=true, and starts its sign-in store in
  # this test's transaction; everything is put back after.
  defp connector_on(_context) do
    origin = "http://127.0.0.1:4002"

    put_env(
      :ash_template,
      AshTemplate.OAuth,
      Keyword.merge(Application.fetch_env!(:ash_template, AshTemplate.OAuth),
        enabled?: true,
        issuer: origin,
        resource: origin <> "/mcp"
      )
    )

    put_env(
      :regent_mcp_agents,
      :config,
      Keyword.merge(Application.fetch_env!(:regent_mcp_agents, :config),
        enabled?: true,
        hosted_signer: [base_url: "https://siwa.test", key: @site_key]
      )
    )

    put_env(:regent_agents, :hosted_pairing, [:claude])
    put_env(:regent_mcp_agents, :req_options, plug: {Req.Test, RegentMCPAgents.HostedSigner})
    for key <- [RegentOAuth.Repo, :site, :prefix], do: keep_env(:regent_oauth, key)
    keep_env(:boruta, Boruta.Oauth)

    :ok = RegentOAuth.configure(AshTemplate.OAuth)
    :ok = RegentMCPAgents.configure!()

    Application.put_env(
      :regent_oauth,
      RegentOAuth.Repo,
      Keyword.put(
        Application.fetch_env!(:regent_oauth, RegentOAuth.Repo),
        :pool,
        Ecto.Adapters.SQL.Sandbox
      )
    )

    start_supervised!(RegentOAuth.Repo)
    oauth = Ecto.Adapters.SQL.Sandbox.start_owner!(RegentOAuth.Repo, shared: true)
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(oauth) end)

    test = self()

    # The hosted signer registers the identity and signs what it is asked to, as
    # the one hosted wallet.
    Req.Test.stub(RegentMCPAgents.HostedSigner, fn conn ->
      {:ok, body, conn} = read_body(conn)
      asked = Jason.decode!(body)
      send(test, {:signer, get_req_header(conn, "authorization"), body, asked})

      case asked do
        %{"operation" => "register"} -> Req.Test.json(conn, %{"address" => @wallet})
        %{"operation" => "sign", "request" => r} -> Req.Test.json(conn, Map.put(r, "headers", @signed))
      end
    end)

    :ok
  end

  defp put_env(app, key, value) do
    keep_env(app, key)
    Application.put_env(app, key, value)
  end

  defp keep_env(app, key) do
    old = Application.fetch_env(app, key)

    on_exit(fn ->
      case old do
        {:ok, value} -> Application.put_env(app, key, value)
        :error -> Application.delete_env(app, key)
      end
    end)
  end

  # A person signed in on this site; answers the session their browser holds.
  defp sign_in!(subject) do
    {:ok, account, []} =
      VerifiedSession.establish(%RegentPrivy.Session{
        app_id: "test-app",
        session_id: subject,
        privy_user_id: subject,
        wallet_address: "0x3333333333333333333333333333333333333333",
        wallet_addresses: ["0x3333333333333333333333333333333333333333"],
        linked_socials: [],
        issued_at: System.system_time(:second),
        expires_at: System.system_time(:second) + 3600
      })

    {:bootstrap, claim} = SessionAuthority.renew(nil)
    {:ok, _bind, bound} = SessionAuthority.sign_in(claim, account.id)
    SessionAuthority.session(bound)
  end

  # An app connected by `subject`, as consent leaves it: its client id and the
  # plain access and refresh tokens it holds.
  defp connect!(subject) do
    register =
      conn(:post, "/oauth/register", %{
        "client_name" => "Claude",
        "redirect_uris" => ["https://claude.ai/api/mcp/auth_callback"]
      })
      |> put_req_header("accept", "application/json")
      |> @endpoint.call([])

    assert register.status == 201, register.resp_body
    client = Boruta.ClientsAdapter.get_client(json(register)["client_id"])

    {:ok, token} =
      RegentOAuth.AccessTokens.create(
        %{client: client, sub: subject, scope: "regent.identity.manage"},
        refresh_token: true
      )

    %{client_id: client.id, access: token.value, refresh: token.refresh_token}
  end

  defp refresh(client_id, refresh_token) do
    conn =
      conn(:post, "/oauth/token", %{
        "grant_type" => "refresh_token",
        "client_id" => client_id,
        "refresh_token" => refresh_token,
        "resource" => RegentOAuth.resource()
      })
      |> put_req_header("accept", "application/json")
      |> @endpoint.call([])

    {conn.status, json(conn)}
  end

  defp tool(token, name, arguments \\ %{}),
    do: json(post_mcp(rpc("tools/call", %{"name" => name, "arguments" => arguments}), token))["result"]

  defp post_mcp(body, token) do
    conn =
      conn(:post, "/mcp", Jason.encode!(body))
      |> put_req_header("content-type", "application/json")
      |> put_req_header("accept", "application/json, text/event-stream")

    conn = if token, do: put_req_header(conn, "authorization", "Bearer " <> token), else: conn
    @endpoint.call(conn, [])
  end

  defp rpc(method, params \\ %{}),
    do: %{"jsonrpc" => "2.0", "id" => 1, "method" => method, "params" => params}

  # An agent's signed request, verified by the stubbed SIWA service.
  defp signed(method, path, body \\ nil) do
    conn = conn(method, path, body)
    conn = if body, do: put_req_header(conn, "content-type", "application/json"), else: conn

    conn
    |> put_req_header("x-siwa-signature", "fixture-proof")
    |> @endpoint.call([])
  end

  defp pair_request(code, harness),
    do:
      signed(
        :post,
        "/api/agents/v1/pair",
        Jason.encode!(%{code: code, name: "Fixture", harness: harness})
      )

  defp pair_args(code), do: %{"code" => code, "name" => "Claude", "harness" => "claude"}

  defp person(subject), do: %RegentAgents.Person{privy_user_id: subject}

  defp code!(subject), do: RegentAgents.issue_pairing_code!(actor: person(subject)).code

  defp agents(subject), do: RegentAgents.list_my_agents!(actor: person(subject))

  defp signer_asks do
    receive do
      {:signer, auth, raw, asked} -> [{auth, raw, asked} | signer_asks()]
    after
      0 -> []
    end
  end

  defp json(conn), do: Jason.decode!(conn.resp_body)
end
