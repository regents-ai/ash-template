defmodule AshTemplateWeb.PublicNameTest do
  # A person's Public Display Name lives in the shared profile every Regent site
  # reads, and changes only with their sign-in's own proof. Saved from the Account
  # page as the browser saves it, it must show there, in the form and as the
  # account's name, and never without that proof. Tokens are signed as Privy signs them.
  use ExUnit.Case, async: false

  import Phoenix.ConnTest, only: [get: 2, html_response: 2, init_test_session: 2]
  import Plug.Conn, only: [put_req_header: 3]

  alias AshTemplate.Accounts.{SessionAuthority, VerifiedSession}

  @endpoint AshTemplateWeb.Endpoint
  @did "did:privy:public-name"
  @wallet "0x" <> String.duplicate("d", 40)

  setup do
    owner = Ecto.Adapters.SQL.Sandbox.start_owner!(AshTemplate.Repo, shared: true)
    key = JOSE.JWK.generate_key({:ec, "P-256"})
    {_, pem} = key |> JOSE.JWK.to_public() |> JOSE.JWK.to_pem()
    privy = Application.fetch_env!(:ash_template, :privy)
    open? = Application.fetch_env!(:ash_template, :app_surfaces)
    Application.put_env(:ash_template, :privy, Keyword.put(privy, :verification_key, pem))
    Application.put_env(:ash_template, :app_surfaces, true)

    on_exit(fn ->
      Application.put_env(:ash_template, :privy, privy)
      Application.put_env(:ash_template, :app_surfaces, open?)
      Ecto.Adapters.SQL.Sandbox.stop_owner(owner)
    end)

    %{proof: proof(key), pem: pem}
  end

  test "a name saved with the person's proof shows on their Account page", %{
    proof: proof,
    pem: pem
  } do
    # Signing in gives the person their shared profile, with no name yet.
    {:ok, account, []} = proof |> verified(pem) |> VerifiedSession.establish()

    assert Jason.decode!(profile(:get, proof).resp_body)["profile"]["display_name"] == nil

    assert profile(:patch, %{proof | identity: "forged"}, %{display_name: "Mallory"}).status ==
             401

    saved = profile(:patch, proof, %{display_name: "Ada Lovelace"})
    assert Jason.decode!(saved.resp_body)["profile"]["display_name"] == "Ada Lovelace"

    html = account |> signed_in() |> get("/account") |> html_response(200)
    assert html =~ "Public Display Name"
    assert html =~ ~s(value="Ada Lovelace")
    assert html =~ "<h2>Ada Lovelace</h2>"
  end

  defp profile(:get, proof), do: call(:get, "/api/v1/profile", proof, nil)
  defp profile(:patch, proof, body), do: call(:patch, "/api/v1/profile", proof, body)

  defp call(method, path, proof, body) do
    method
    |> Plug.Test.conn(path, body && Jason.encode!(body))
    |> put_req_header("authorization", "Bearer " <> proof.access)
    |> put_req_header("privy-id-token", proof.identity)
    |> put_req_header("content-type", "application/json")
    |> put_req_header("accept", "application/json")
    |> @endpoint.call(@endpoint.init([]))
  end

  # The cookie the site's own sign-in step leaves.
  defp signed_in(account) do
    {:bootstrap, claim} = SessionAuthority.renew(nil)
    {:ok, _account, bound} = SessionAuthority.sign_in(claim, account.id)
    Phoenix.ConnTest.build_conn() |> init_test_session(SessionAuthority.session(bound))
  end

  defp verified(proof, pem) do
    {:ok, session} =
      RegentPrivy.Session.verify(proof,
        app_id: "test-app",
        verification_key: pem
      )

    session
  end

  defp proof(key) do
    now = System.system_time(:second)

    wallet = %{
      "type" => "wallet",
      "address" => @wallet,
      "chain_type" => "ethereum",
      "wallet_client_type" => "metamask",
      "lv" => now - 1
    }

    claims = %{
      "iss" => "privy.io",
      "aud" => "test-app",
      "sub" => @did,
      "iat" => now - 1,
      "exp" => now + 600,
      "sid" => "public-name"
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
