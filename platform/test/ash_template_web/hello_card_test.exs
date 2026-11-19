defmodule AshTemplateWeb.HelloCardTest do
  # Hello cards (RegentAgents.HelloCard), through this site's own endpoint and
  # router:
  # - the SIWA service's pairing read, sent as the service sends it, with only its
  #   token: no agent signature, cookie, forms token or Origin;
  # - a card beside an agent's signed request, on the API and at /mcp, and what the
  #   agent's own profile says of it.
  # The SIWA service is stood in for: it publishes an Ed25519 key made here, and
  # vouches for @agent's signed requests. The published keys are kept for the
  # whole node, so each test starts and ends with none kept.
  use ExUnit.Case, async: false

  import Plug.Conn
  import Plug.Test

  alias AshTemplate.Accounts.VerifiedSession

  @endpoint AshTemplateWeb.Endpoint
  @did "did:privy:hello-card"
  @wallet "0x" <> String.duplicate("c", 40)
  @agent "0x" <> String.duplicate("4", 40)
  @subject "eip155:8453:" <> @agent
  @other_subject "eip155:8453:0x" <> String.duplicate("5", 40)
  @card "siwa-hello-card+jws"
  @service "siwa-service+jwt"
  @keys {RegentAgents.HelloCard, :keys}

  setup do
    owner = Ecto.Adapters.SQL.Sandbox.start_owner!(AshTemplate.Repo, shared: true)
    broker = Application.fetch_env(:regent_agents, :req_options)
    Application.put_env(:regent_agents, :req_options, plug: {Req.Test, RegentAgents.Broker})
    :persistent_term.erase(@keys)

    on_exit(fn ->
      :persistent_term.erase(@keys)

      case broker do
        {:ok, options} -> Application.put_env(:regent_agents, :req_options, options)
        :error -> Application.delete_env(:regent_agents, :req_options)
      end

      Ecto.Adapters.SQL.Sandbox.stop_owner(owner)
    end)

    key = new_key()

    Req.Test.stub(RegentAgents.Broker, fn conn ->
      case conn.request_path do
        "/.well-known/jwks.json" -> Req.Test.json(conn, %{"keys" => [key.jwk]})
        _verify -> Req.Test.json(conn, verdict())
      end
    end)

    # Each test calls from its own address, so it spends its own rate budgets.
    %{key: key, from: {10, :rand.uniform(250), :rand.uniform(250), :rand.uniform(250)}}
  end

  describe "the pairing read" do
    test "answers a paired agent's name, its person's profile code and when it paired, and nothing else",
         %{key: key, from: from} do
      sign_in(@did)
      paired = pair(@did)
      {:ok, profile_id} = RegentIdentity.profile_id("test-app", @did)
      assert is_binary(profile_id)

      answer = ask(sign(key, @service, token_claims()), %{"subject" => @subject}, from)

      assert answer.status == 200

      assert Jason.decode!(answer.resp_body) == %{
               "name" => "Fixture",
               "person" => profile_id,
               "pairedAt" => iso(paired.paired_at)
             }

      assert_visit_lines_kept()
    end

    test "says an agent with no pairing is not paired here", %{key: key, from: from} do
      token = sign(key, @service, token_claims())

      assert {404, "not_paired_here"} = refusal(ask(token, %{"subject" => @subject}, from))
      assert_visit_lines_kept()
    end

    test "says a paired agent's person has no profile yet", %{key: key, from: from} do
      # Paired by a person who has never signed in here, so has no profile yet.
      pair("did:privy:never-signed-in")
      token = sign(key, @service, token_claims())

      assert {409, "person_has_no_profile"} = refusal(ask(token, %{"subject" => @subject}, from))
      assert_visit_lines_kept()
    end

    test "is refused without the SIWA service's token for this site's address", %{
      key: key,
      from: from
    } do
      sign_in(@did)
      pair(@did)

      refused = [
        nil,
        sign(new_key(), @service, token_claims()),
        sign(key, @service, token_claims(%{"aud" => "https://other.example"})),
        sign(key, @service, token_claims(%{"sub" => @other_subject})),
        sign(key, @card, card_claims())
      ]

      for token <- refused do
        assert {401, "service_token_invalid"} =
                 refusal(ask(token, %{"subject" => @subject}, from))
      end

      # A body naming another agent than the token does.
      assert {401, "service_token_invalid"} =
               refusal(
                 ask(sign(key, @service, token_claims()), %{"subject" => @other_subject}, from)
               )

      assert_visit_lines_kept()
    end
  end

  describe "a card beside a signed request" do
    test "on the API is kept when it passes for the agent's own wallet, and left out otherwise",
         %{key: key, from: from} do
      claims = card_claims()
      shown = api(sign(key, @card, claims), from)
      assert shown.status == 200
      assert shown.assigns.hello_card == claims

      for other <- [
            nil,
            sign(key, @card, card_claims(%{"subject" => @other_subject})),
            expired(key)
          ] do
        conn = api(other, from)
        assert conn.status == 200
        assert conn.assigns.hello_card == nil
      end
    end

    test "is in the agent's own profile when it passes, without its person, and null otherwise",
         %{key: key, from: from} do
      for ask <- [&api/2, &edit/2] do
        claims = card_claims()
        shown = ask.(sign(key, @card, claims), from)
        assert shown.status == 200

        assert Jason.decode!(shown.resp_body)["hello_card"] == %{
                 "name" => "Sol",
                 "paired_on" => "keyfleet",
                 "paired_at" => claims["pairedAt"],
                 "expires_at" => claims["expiresAt"]
               }

        refute shown.resp_body =~ claims["person"]

        for other <- [
              nil,
              sign(key, @card, card_claims(%{"subject" => @other_subject})),
              expired(key)
            ] do
          conn = ask.(other, from)
          assert conn.status == 200

          assert %{"agent" => %{"wallet_address" => @agent}, "hello_card" => nil} =
                   Jason.decode!(conn.resp_body)
        end
      end
    end

    test "at /mcp is kept when it passes for the agent's own wallet, and left out otherwise",
         %{key: key, from: from} do
      claims = card_claims()
      shown = mcp(sign(key, @card, claims), from)
      assert shown.status == 200
      assert shown.assigns.hello_card == claims

      for other <- [
            nil,
            sign(key, @card, card_claims(%{"subject" => @other_subject})),
            expired(key)
          ] do
        conn = mcp(other, from)
        assert conn.status == 200
        assert conn.assigns.hello_card == nil
      end
    end
  end

  # The SIWA service asks whether the agent is paired here.
  defp ask(token, body, from) do
    conn = conn(:post, "/api/agents/v1/pairing", Jason.encode!(body))
    conn = if token, do: put_req_header(conn, "authorization", "Bearer " <> token), else: conn

    conn
    |> Map.put(:remote_ip, from)
    |> put_req_header("content-type", "application/json")
    |> @endpoint.call([])
  end

  # The agent's signed read of its own profile, with `card` beside it when given.
  defp api(card, from) do
    conn(:get, "/api/v1/agents/me")
    |> Map.put(:remote_ip, from)
    |> signed(card)
    |> @endpoint.call([])
  end

  # The agent's signed change to its own status line, with `card` beside it when given.
  defp edit(card, from) do
    conn(:patch, "/api/v1/agents/me", Jason.encode!(%{"status" => "Reading"}))
    |> Map.put(:remote_ip, from)
    |> put_req_header("content-type", "application/json")
    |> signed(card)
    |> @endpoint.call([])
  end

  # The agent's signed tools/list at /mcp, with `card` beside it when given.
  defp mcp(card, from) do
    conn(:post, "/mcp", Jason.encode!(%{"jsonrpc" => "2.0", "id" => 1, "method" => "tools/list"}))
    |> Map.put(:remote_ip, from)
    |> put_req_header("content-type", "application/json")
    |> put_req_header("accept", "application/json, text/event-stream")
    |> signed(card)
    |> @endpoint.call([])
  end

  defp signed(conn, card) do
    conn =
      conn
      |> put_req_header("x-siwa-signature", "fixture-proof")
      |> put_req_header("x-agent-wallet-address", @agent)

    if card, do: put_req_header(conn, "x-siwa-hello-card", card), else: conn
  end

  defp refusal(conn), do: {conn.status, Jason.decode!(conn.resp_body)["error"]["code"]}

  # The visit lines' handler would be taken off had it failed on any answer above.
  defp assert_visit_lines_kept do
    assert Enum.any?(
             :telemetry.list_handlers([:phoenix, :endpoint, :stop]),
             &(&1.id == "ash-template-visit-log")
           )
  end

  # The sign-in service vouching for @agent's signed request to this site.
  defp verdict do
    %{
      code: "http_envelope_valid",
      data: %{
        verified: true,
        walletAddress: @agent,
        agentBook: nil,
        agentRegistration: nil,
        principal: %{
          kind: "wallet",
          wallet_address: @agent,
          chain_id: 8453,
          audience: RegentAgents.Broker.audience()
        }
      }
    }
  end

  # The person signs in here with a wallet, which makes their shared profile.
  defp sign_in(did) do
    now = System.system_time(:second)

    assert {:ok, _account, []} =
             VerifiedSession.establish(%RegentPrivy.Session{
               app_id: "test-app",
               session_id: "hello-card",
               privy_user_id: did,
               wallet_address: @wallet,
               wallet_addresses: [@wallet],
               linked_socials: [],
               issued_at: now,
               expires_at: now + 3600
             })
  end

  defp pair(privy_user_id) do
    code =
      RegentAgents.issue_pairing_code!(actor: %RegentAgents.Person{privy_user_id: privy_user_id})

    RegentAgents.pair_agent!(code.code, "Fixture", :codex,
      actor: %RegentAgents.Agent{wallet: @agent}
    )
  end

  # An Ed25519 key as the SIWA service publishes it, `kid` its RFC 7638 thumbprint.
  defp new_key do
    {public, seed} = :crypto.generate_key(:eddsa, :ed25519)
    x = encode(public)
    kid = encode(:crypto.hash(:sha256, ~s({"crv":"Ed25519","kty":"OKP","x":"#{x}"})))

    %{
      seed: seed,
      jwk: %{
        "kty" => "OKP",
        "crv" => "Ed25519",
        "alg" => "EdDSA",
        "use" => "sig",
        "kid" => kid,
        "x" => x
      }
    }
  end

  defp sign(key, typ, claims) do
    header = encode(Jason.encode!(%{"alg" => "EdDSA", "typ" => typ, "kid" => key.jwk["kid"]}))
    payload = encode(Jason.encode!(claims))
    signature = :crypto.sign(:eddsa, :none, header <> "." <> payload, [key.seed, :ed25519])
    Enum.join([header, payload, encode(signature)], ".")
  end

  defp encode(bytes), do: Base.url_encode64(bytes, padding: false)

  defp iso(time), do: time |> DateTime.truncate(:second) |> DateTime.to_iso8601()

  # The service's token for this site's own address and @agent.
  defp token_claims(claims \\ %{}) do
    siwa = Application.fetch_env!(:regent_agents, :siwa)
    now = System.os_time(:second)

    Map.merge(
      %{
        "iss" => String.trim_trailing(siwa[:url], "/"),
        "aud" => siwa[:origin],
        "sub" => @subject,
        "iat" => now,
        "exp" => now + 60,
        "jti" => encode(:crypto.strong_rand_bytes(16))
      },
      claims
    )
  end

  defp card_claims(fields \\ %{}) do
    now = DateTime.utc_now()

    Map.merge(
      %{
        "cardId" => encode(:crypto.strong_rand_bytes(16)),
        "subject" => @subject,
        "name" => "Sol",
        "person" => Ecto.UUID.generate(),
        "pairedAt" => iso(DateTime.add(now, -7, :day)),
        "pairedOn" => "keyfleet",
        "issuedAt" => iso(now),
        "expiresAt" => iso(DateTime.add(now, 1, :day))
      },
      fields
    )
  end

  defp expired(key) do
    ended = DateTime.add(DateTime.utc_now(), -1, :second)

    sign(
      key,
      @card,
      card_claims(%{"issuedAt" => iso(DateTime.add(ended, -1, :day)), "expiresAt" => iso(ended)})
    )
  end
end
