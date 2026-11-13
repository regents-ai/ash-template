defmodule AshTemplateWeb.SignInLifetimeTest do
  # A sign-in here lasts a day from the sign-in that made it. After that the
  # person is signed out until fresh tokens from Privy sign them in again, which
  # Privy gives only while its own sign-in in that browser lasts. This signs in
  # through the site's own sign-in step, as the browser does, with tokens signed
  # as Privy signs them.
  use ExUnit.Case, async: false

  import Ecto.Query, only: [from: 2]
  import Phoenix.ConnTest
  import Plug.Conn, only: [put_req_header: 3]

  alias AshTemplate.Accounts.SessionAuthority

  @endpoint AshTemplateWeb.Endpoint
  @day 24 * 60 * 60
  @did "did:privy:sign-in-lifetime"
  @wallet "0x" <> String.duplicate("8", 40)

  setup do
    owner = Ecto.Adapters.SQL.Sandbox.start_owner!(AshTemplate.Repo, shared: true)
    key = JOSE.JWK.generate_key({:ec, "P-256"})
    {_, pem} = key |> JOSE.JWK.to_public() |> JOSE.JWK.to_pem()
    privy = Application.fetch_env!(:ash_template, :privy)

    Application.put_env(
      :ash_template,
      :privy,
      privy |> Keyword.put(:app_id, "test-app") |> Keyword.put(:verification_key, pem)
    )

    on_exit(fn ->
      Application.put_env(:ash_template, :privy, privy)
      Ecto.Adapters.SQL.Sandbox.stop_owner(owner)
    end)

    %{key: key}
  end

  test "a sign-in lasts a day: just before, the person is signed in; from then, signed out",
       %{key: key} do
    signed_in = key |> fresh_proof() |> sign_in(fresh_session())
    assert signed_in.status == 200

    signed_in_ago(@day - 60)
    assert signed_in?(signed_in)

    signed_in_ago(@day)
    refute signed_in?(signed_in)
  end

  test "after the day, only fresh tokens from Privy sign the person back in", %{key: key} do
    signed_in = key |> fresh_proof() |> sign_in(fresh_session())
    signed_in_ago(@day + 1)
    refute signed_in?(signed_in)

    # The ended sign-in's cookie is retired, and the browser starts a fresh session.
    retired = signed_in |> recycle() |> get("/auth/csrf")
    assert json_response(retired, 409)["error"]["code"] == "session_reset_required"

    # Privy's own sign-in in this browser has ended, so the tokens it gave before
    # are all the browser has.
    stale = sign_in(ended_proof(key), fresh_session(retired))
    assert json_response(stale, 401)["error"]["code"] == "unauthorized"
    refute signed_in?(stale)

    back = key |> fresh_proof() |> sign_in(fresh_session(retired))
    assert json_response(back, 200)["authenticated"] == true
    assert signed_in?(back)
  end

  defp signed_in?(conn),
    do:
      conn
      |> recycle()
      |> get("/auth/session")
      |> json_response(200)
      |> Map.fetch!("authenticated")

  # Moves every sign-in back in time, as if it had been made `seconds` ago.
  defp signed_in_ago(seconds) do
    at = DateTime.add(DateTime.utc_now(), -seconds, :second)

    AshTemplate.Repo.update_all(
      from(row in SessionAuthority, where: not is_nil(row.human_account_id)),
      set: [signed_in_at: at]
    )
  end

  # The browser's first step: a session with its forms token.
  defp fresh_session(conn \\ build_conn()) do
    csrf = conn |> recycle() |> get("/auth/csrf")
    {csrf, json_response(csrf, 200)["csrf_token"]}
  end

  # Privy's two tokens on the site's sign-in step, with the session the first step left.
  defp sign_in(proof, {csrf, token}) do
    csrf
    |> recycle()
    |> put_req_header("x-csrf-token", token)
    |> put_req_header("authorization", "Bearer " <> proof.access)
    |> put_req_header("privy-id-token", proof.identity)
    |> post("/auth/privy/session")
  end

  defp fresh_proof(key), do: proof(key, System.system_time(:second))

  # Tokens Privy gave an hour ago, which have since run out.
  defp ended_proof(key), do: proof(key, System.system_time(:second) - 3_600)

  defp proof(key, issued_at) do
    claims = %{
      "iss" => "privy.io",
      "aud" => "test-app",
      "sub" => @did,
      "iat" => issued_at - 1,
      "exp" => issued_at + 600,
      "sid" => @did
    }

    linked = [
      %{
        "type" => "wallet",
        "address" => @wallet,
        "chain_type" => "ethereum",
        "wallet_client_type" => "metamask",
        "lv" => issued_at
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
