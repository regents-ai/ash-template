defmodule AshTemplateWeb.ErrorsAdminTest do
  # The saved errors are for Credits admins only, through the shared owners check
  # (RegentPrivy.Owners): anyone else, signed in or not, gets the ordinary
  # not-found page, and a signed-in account that is not an admin is logged with
  # its Privy id. Tokens are signed as Privy signs them.
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog
  import Phoenix.ConnTest

  alias AshTemplate.Accounts.{SessionAuthority, VerifiedSession}

  @endpoint AshTemplateWeb.Endpoint
  @admin "did:privy:errors-admin"
  @person "did:privy:errors-person"

  setup do
    owner = Ecto.Adapters.SQL.Sandbox.start_owner!(AshTemplate.Repo, shared: true)
    admins = Application.fetch_env!(:regent_credits, :admins)
    Application.put_env(:regent_credits, :admins, [@admin])

    on_exit(fn ->
      Application.put_env(:regent_credits, :admins, admins)
      Ecto.Adapters.SQL.Sandbox.stop_owner(owner)
    end)

    key = JOSE.JWK.generate_key({:ec, "P-256"})
    {_, pem} = key |> JOSE.JWK.to_public() |> JOSE.JWK.to_pem()
    %{account: fn did -> account(key, pem, did) end}
  end

  test "signed out, the page is not found" do
    assert build_conn() |> get("/admin/errors") |> html_response(404)
  end

  test "an account that is not an admin finds no page, and its Privy id is logged", %{
    account: account
  } do
    conn = signed_in(account.(@person))
    # The site logs at info in production; tests log warnings only.
    level = Logger.level()
    Logger.configure(level: :info)
    on_exit(fn -> Logger.configure(level: level) end)

    log = capture_log(fn -> assert conn |> get("/admin/errors") |> html_response(404) end)

    assert log =~ "Privy account #{@person} is not an owner"
  end

  test "an admin opens the page under its own nonce", %{
    account: account
  } do
    conn = account.(@admin) |> signed_in() |> get("/admin/errors")

    assert html_response(conn, 200)
    [policy] = Plug.Conn.get_resp_header(conn, "content-security-policy")
    assert policy =~ "script-src 'self' 'nonce-#{conn.assigns.csp_nonce}'"
  end

  test "an admin whose sign-in has ended finds no page", %{account: account} do
    {conn, claim} = account.(@admin) |> signed_in_with_claim()
    SessionAuthority.revoke(claim)

    assert conn |> get("/admin/errors") |> html_response(404)
  end

  defp signed_in(account), do: account |> signed_in_with_claim() |> elem(0)

  # The cookie the site's own sign-in step leaves.
  defp signed_in_with_claim(account) do
    {:bootstrap, claim} = SessionAuthority.renew(nil)
    {:ok, _account, bound} = SessionAuthority.sign_in(claim, account.id)
    {build_conn() |> init_test_session(SessionAuthority.session(bound)), bound}
  end

  defp account(key, pem, did) do
    now = System.system_time(:second)

    wallet = %{
      "type" => "wallet",
      "address" => "0x" <> String.duplicate("e", 40),
      "chain_type" => "ethereum",
      "wallet_client_type" => "metamask",
      "lv" => now - 1
    }

    claims = %{
      "iss" => "privy.io",
      "aud" => "test-app",
      "sub" => did,
      "iat" => now - 1,
      "exp" => now + 600,
      "sid" => did
    }

    sign = fn claims ->
      key |> JOSE.JWT.sign(%{"alg" => "ES256"}, claims) |> JOSE.JWS.compact() |> elem(1)
    end

    {:ok, verified} =
      RegentPrivy.Session.verify(
        %{
          access: sign.(claims),
          identity: sign.(Map.put(claims, "linked_accounts", Jason.encode!([wallet])))
        },
        app_id: "test-app",
        verification_key: pem
      )

    {:ok, account, []} = VerifiedSession.establish(verified)
    account
  end
end
