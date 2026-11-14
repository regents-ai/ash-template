defmodule AshTemplateWeb.PublicNameTest do
  # A person's Public Display Name lives in the shared profile every Regent site
  # reads (`RegentIdentity.HTTP` at /api/v1/profile). It is read and changed for
  # the person signed in on this site, from its pages, or for the person an agent
  # they paired acts for, while that person's latest sign-in here names a wallet
  # (`AshTemplateWeb.Plugs.ProfileOwner`), and for nobody else. People sign in
  # through the site's own sign-in step, with tokens signed as Privy signs them;
  # the sign-in service is stood in for and vouches for the agent's wallet.
  use ExUnit.Case, async: false

  import Phoenix.ConnTest
  import Plug.Conn, only: [put_private: 3, put_req_header: 3]

  alias AshTemplate.Accounts.VerifiedSession

  @endpoint AshTemplateWeb.Endpoint
  @did "did:privy:public-name"
  @wallet "0x" <> String.duplicate("d", 40)
  @agent "0x" <> String.duplicate("2", 40)

  setup do
    :ets.delete_all_objects(AshTemplate.Accounts.RequestRateLimiter)
    owner = Ecto.Adapters.SQL.Sandbox.start_owner!(AshTemplate.Repo, shared: true)
    key = JOSE.JWK.generate_key({:ec, "P-256"})
    {_, pem} = key |> JOSE.JWK.to_public() |> JOSE.JWK.to_pem()
    privy = Application.fetch_env!(:ash_template, :privy)
    open? = Application.fetch_env!(:ash_template, :app_surfaces)
    broker = Application.fetch_env(:regent_agents, :req_options)

    Application.put_env(
      :ash_template,
      :privy,
      privy |> Keyword.put(:app_id, "test-app") |> Keyword.put(:verification_key, pem)
    )

    Application.put_env(:ash_template, :app_surfaces, true)
    Application.put_env(:regent_agents, :req_options, plug: {Req.Test, RegentAgents.Broker})

    on_exit(fn ->
      Application.put_env(:ash_template, :privy, privy)
      Application.put_env(:ash_template, :app_surfaces, open?)

      case broker do
        {:ok, options} -> Application.put_env(:regent_agents, :req_options, options)
        :error -> Application.delete_env(:regent_agents, :req_options)
      end

      Ecto.Adapters.SQL.Sandbox.stop_owner(owner)
    end)

    Req.Test.stub(RegentAgents.Broker, fn conn ->
      Req.Test.json(conn, %{
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
      })
    end)

    %{key: key}
  end

  test "the person signed in here reads and sets their name, a change only with the forms token",
       %{key: key} do
    {signed_in, token} = sign_in(key, @did, @wallet)
    assert read(signed_in)["display_name"] == nil

    # Without the forms token a change counts as signed out and changes nothing.
    refused = send_json(signed_in, %{display_name: "Mallory"}, nil)
    assert json_response(refused, 401)["error"]["code"] == "authentication_required"
    assert read(signed_in)["display_name"] == nil

    saved = send_json(signed_in, %{display_name: "Ada Lovelace"}, token)
    assert json_response(saved, 200)["profile"]["display_name"] == "Ada Lovelace"
    assert read(signed_in)["display_name"] == "Ada Lovelace"

    html = signed_in |> recycle() |> get("/account") |> html_response(200)
    assert html =~ ~s(value="Ada Lovelace")
    assert html =~ "<h2>Ada Lovelace</h2>"
  end

  test "with no sign-in nothing is read or changed" do
    for {method, body} <- [{:get, nil}, {:patch, Jason.encode!(%{display_name: "Mallory"})}] do
      refused =
        build_conn()
        |> put_private(:plug_skip_csrf_protection, false)
        |> put_req_header("content-type", "application/json")
        |> dispatch(@endpoint, method, "/api/v1/profile", body)

      assert json_response(refused, 401)["error"]["code"] == "authentication_required"
    end
  end

  test "a paired agent reads and sets its person's name, which reads back for that person and nobody else",
       %{key: key} do
    # An agent paired with no one acts for no one.
    assert json_response(agent(:get), 403)["error"]["code"] == "agent_not_paired"

    {person, _token} = sign_in(key, @did, @wallet)
    {someone_else, _token} = sign_in(key, "did:privy:someone-else", "0x" <> String.duplicate("e", 40))
    pair(@did)

    assert json_response(agent(:get), 200)["profile"]["display_name"] == nil

    saved = agent(:patch, %{display_name: "Named by my agent"})
    assert json_response(saved, 200)["profile"]["display_name"] == "Named by my agent"

    assert read(person)["display_name"] == "Named by my agent"
    assert read(someone_else)["display_name"] == nil
  end

  test "a paired agent whose person's latest sign-in names no wallet changes nothing, and acts again after one with a wallet" do
    session = %RegentPrivy.Session{
      app_id: "test-app",
      session_id: "public-name",
      privy_user_id: @did,
      wallet_address: @wallet,
      wallet_addresses: [@wallet],
      linked_socials: [],
      issued_at: System.system_time(:second),
      expires_at: System.system_time(:second) + 3600
    }

    assert {:ok, _account, []} = VerifiedSession.establish(session)
    pair(@did)

    assert {:error, :missing_linked_wallet} =
             VerifiedSession.establish(%{session | wallet_address: nil, wallet_addresses: []})

    for {method, body} <- [{:get, nil}, {:patch, %{display_name: "Unsent"}}] do
      refused = agent(method, body)
      assert json_response(refused, 403)["error"]["code"] == "person_not_here"
    end

    assert {:ok, _account, []} = VerifiedSession.establish(session)
    assert json_response(agent(:get), 200)["profile"]["display_name"] == nil
  end

  defp read(signed_in),
    do: signed_in |> recycle() |> get("/api/v1/profile") |> json_response(200) |> Map.fetch!("profile")

  # Phoenix's test connection skips the forms token check; these requests keep it,
  # as a browser's do.
  defp send_json(signed_in, body, token) do
    conn =
      signed_in
      |> recycle()
      |> put_private(:plug_skip_csrf_protection, false)
      |> put_req_header("content-type", "application/json")

    conn = if token, do: put_req_header(conn, "x-csrf-token", token), else: conn
    dispatch(conn, @endpoint, :patch, "/api/v1/profile", Jason.encode!(body))
  end

  # The agent's request, signed with its wallet.
  defp agent(method, body \\ nil) do
    conn = put_req_header(build_conn(), "x-siwa-signature", "fixture-proof")

    conn =
      if body,
        do: put_req_header(conn, "content-type", "application/json"),
        else: conn

    dispatch(conn, @endpoint, method, "/api/v1/profile", body && Jason.encode!(body))
  end

  defp pair(privy_user_id) do
    code = RegentAgents.issue_pairing_code!(actor: %RegentAgents.Person{privy_user_id: privy_user_id})
    RegentAgents.pair_agent!(code.code, "Fixture", :codex, actor: %RegentAgents.Agent{wallet: @agent})
  end

  # The browser's steps: a fresh session, then Privy's two tokens on the sign-in
  # step, then the forms token the site's pages carry for the session that step left.
  defp sign_in(key, did, wallet) do
    csrf = build_conn() |> get("/auth/csrf")
    proof = proof(key, did, wallet)

    signed_in =
      csrf
      |> recycle()
      |> put_req_header("x-csrf-token", Jason.decode!(csrf.resp_body)["csrf_token"])
      |> put_req_header("authorization", "Bearer " <> proof.access)
      |> put_req_header("privy-id-token", proof.identity)
      |> post("/auth/privy/session")

    assert signed_in.status == 200
    page = signed_in |> recycle() |> get("/auth/csrf")
    {page, json_response(page, 200)["csrf_token"]}
  end

  defp proof(key, did, wallet) do
    now = System.system_time(:second)

    claims = %{
      "iss" => "privy.io",
      "aud" => "test-app",
      "sub" => did,
      "iat" => now - 1,
      "exp" => now + 600,
      "sid" => did
    }

    linked = [
      %{
        "type" => "wallet",
        "address" => wallet,
        "chain_type" => "ethereum",
        "wallet_client_type" => "metamask",
        "lv" => now
      }
    ]

    sign = fn claims ->
      key |> JOSE.JWT.sign(%{"alg" => "ES256"}, claims) |> JOSE.JWS.compact() |> elem(1)
    end

    %{
      access: sign.(claims),
      identity: sign.(Map.put(claims, "linked_accounts", Jason.encode!(linked)))
    }
  end
end
