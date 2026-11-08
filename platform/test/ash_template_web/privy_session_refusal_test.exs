defmodule AshTemplateWeb.PrivySessionRefusalTest do
  # A signed-in page sends the sign-in step again after each social link. A fault
  # on the site's own side must leave the person signed in, in every tab; only a
  # proof this browser cannot back ends the sign-in. Both cases go through the
  # site's own sign-in step with tokens signed as Privy signs them.
  use ExUnit.Case, async: false

  import Phoenix.ConnTest
  import Plug.Conn, only: [put_req_header: 3, get_resp_header: 2]

  alias AshTemplate.Accounts.SessionAuthority
  alias AshTemplate.Repo

  @endpoint AshTemplateWeb.Endpoint
  @wallet "0x" <> String.duplicate("a", 40)

  setup do
    owner = Ecto.Adapters.SQL.Sandbox.start_owner!(Repo, shared: true)
    key = JOSE.JWK.generate_key({:ec, "P-256"})
    {_, pem} = key |> JOSE.JWK.to_public() |> JOSE.JWK.to_pem()
    privy = Application.fetch_env!(:ash_template, :privy)
    open? = Application.fetch_env!(:ash_template, :app_surfaces)

    Application.put_env(
      :ash_template,
      :privy,
      privy |> Keyword.put(:app_id, "test-app") |> Keyword.put(:verification_key, pem)
    )

    Application.put_env(:ash_template, :app_surfaces, true)

    on_exit(fn ->
      Application.put_env(:ash_template, :privy, privy)
      Application.put_env(:ash_template, :app_surfaces, open?)
      Ecto.Adapters.SQL.Sandbox.stop_owner(owner)
    end)

    %{key: key}
  end

  test "a failed account write leaves the sign-in bound and current", %{key: key} do
    signed_in = key |> exchange("did:privy:kept", build_conn()) |> session()
    account = signed_in.assigns.current_human_account
    lineage = signed_in.assigns.current_lineage
    assert account
    @endpoint.subscribe(SessionAuthority.topic(lineage))

    refuse_account_writes()
    failed = exchange(key, "did:privy:kept", signed_in)

    assert failed.status == 503
    assert get_resp_header(failed, "set-cookie") == []
    refute_receive %Phoenix.Socket.Broadcast{event: "disconnect"}

    kept = session(failed)
    assert kept.assigns.current_lineage == lineage
    assert kept.assigns.current_human_account.id == account.id
  end

  test "a proof signed by another key still ends the sign-in", %{key: key} do
    signed_in = key |> exchange("did:privy:ended", build_conn()) |> session()
    @endpoint.subscribe(SessionAuthority.topic(signed_in.assigns.current_lineage))

    forged = exchange(JOSE.JWK.generate_key({:ec, "P-256"}), "did:privy:ended", signed_in)

    assert forged.status == 401
    assert_receive %Phoenix.Socket.Broadcast{event: "disconnect"}
    # The cookie the browser held before the refusal no longer names anyone.
    assert is_nil(session(signed_in).assigns.current_human_account)
  end

  # The database itself refuses the account write, as a failing database would.
  # The trigger rolls back with the test's sandbox transaction.
  defp refuse_account_writes do
    Repo.query!("""
    CREATE FUNCTION public.refuse_account_write() RETURNS trigger LANGUAGE plpgsql AS $$
    BEGIN RAISE EXCEPTION 'account writes refused'; END $$
    """)

    Repo.query!("""
    CREATE TRIGGER refuse_account_write BEFORE INSERT OR UPDATE
    ON regent_names.platform_human_users
    FOR EACH ROW EXECUTE FUNCTION public.refuse_account_write()
    """)
  end

  # The browser's steps: a CSRF token for the cookie it holds, then Privy's two
  # tokens on the sign-in step.
  defp exchange(key, did, conn) do
    csrf = conn |> recycle() |> get("/auth/csrf")
    token = Jason.decode!(csrf.resp_body)["csrf_token"]
    proof = proof(key, did)

    csrf
    |> recycle()
    |> put_req_header("x-csrf-token", token)
    |> put_req_header("authorization", "Bearer " <> proof.access)
    |> put_req_header("privy-id-token", proof.identity)
    |> post("/auth/privy/session")
  end

  defp session(conn), do: conn |> recycle() |> get("/auth/session")

  defp proof(key, did) do
    now = System.system_time(:second)

    claims = %{
      "iss" => "privy.io",
      "aud" => "test-app",
      "sub" => did,
      "iat" => now - 1,
      "exp" => now + 600,
      "sid" => did
    }

    wallet = %{
      "type" => "wallet",
      "address" => @wallet,
      "chain_type" => "ethereum",
      "wallet_client_type" => "metamask",
      "lv" => 1_000
    }

    sign = fn claims ->
      key |> JOSE.JWT.sign(%{"alg" => "ES256"}, claims) |> JOSE.JWS.compact() |> elem(1)
    end

    %{
      access: sign.(claims),
      identity: sign.(Map.put(claims, "linked_accounts", Jason.encode!([wallet])))
    }
  end
end
