defmodule AshTemplate.Accounts.VerifiedSessionTest do
  # Every sign-in failed from 5 to 8 October 2026 and nothing noticed: saving the
  # account loaded its name through a primary read the account did not have.
  # This signs a person in, then back in with another wallet, as the site does.
  use ExUnit.Case, async: true

  alias AshTemplate.Accounts.VerifiedSession

  @first "0x" <> String.duplicate("a", 40)
  @second "0x" <> String.duplicate("c", 40)

  setup do
    owner = Ecto.Adapters.SQL.Sandbox.start_owner!(AshTemplate.Repo)
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(owner) end)
  end

  test "a person signs in, and signs in again with a wallet added" do
    session = %RegentPrivy.Session{
      app_id: "test-app",
      session_id: "test-session",
      privy_user_id: "did:privy:sign-in-test",
      wallet_address: @first,
      wallet_addresses: [@first],
      linked_socials: [],
      issued_at: System.system_time(:second),
      expires_at: System.system_time(:second) + 3600
    }

    assert {:ok, account, []} = VerifiedSession.establish(session)
    assert account.wallet_addresses == [@first]

    assert {:ok, again, []} =
             VerifiedSession.establish(%{session | wallet_addresses: [@first, @second]})

    assert again.id == account.id
    assert again.wallet_addresses == [@first, @second]
  end

  # A new person who signs in with email gets an account only once Privy has
  # given them a wallet, lands in that same account at every sign-in, and the
  # wallet they proved most recently becomes the account's wallet, with every
  # wallet they linked kept (106 b, 108 a). Tokens are signed as Privy signs them.
  test "a new person signs in with email, gets their wallet, and keeps one account" do
    key = JOSE.JWK.generate_key({:ec, "P-256"})
    {_, pem} = key |> JOSE.JWK.to_public() |> JOSE.JWK.to_pem()
    did = "did:privy:new-person"
    email = %{"type" => "email", "address" => "new@example.com", "lv" => 1_000}
    embedded = wallet(@first, 1_001, "privy")
    extension = wallet(@second, 2_000, "metamask")

    assert {:error, :missing_linked_wallet} =
             sign_in(key, pem, did, "s1", [email]) |> VerifiedSession.establish()

    assert {:ok, account, []} =
             sign_in(key, pem, did, "s1", [email, embedded]) |> VerifiedSession.establish()

    assert account.wallet_address == @first

    assert {:ok, again, []} =
             sign_in(key, pem, did, "s2", [email, embedded]) |> VerifiedSession.establish()

    assert again.id == account.id

    assert {:ok, linked, []} =
             sign_in(key, pem, did, "s3", [email, embedded, extension])
             |> VerifiedSession.establish()

    assert linked.id == account.id
    assert linked.wallet_address == @second
    assert Enum.sort(linked.wallet_addresses) == [@first, @second]
  end

  defp wallet(address, verified_at, client),
    do: %{
      "type" => "wallet",
      "address" => address,
      "chain_type" => "ethereum",
      "wallet_client_type" => client,
      "lv" => verified_at
    }

  defp sign_in(key, pem, did, sid, linked_accounts) do
    now = System.system_time(:second)

    claims = %{
      "iss" => "privy.io",
      "aud" => "test-app",
      "sub" => did,
      "iat" => now,
      "exp" => now + 3600,
      "sid" => sid
    }

    sign = fn claims ->
      key |> JOSE.JWT.sign(%{"alg" => "ES256"}, claims) |> JOSE.JWS.compact() |> elem(1)
    end

    {:ok, session} =
      RegentPrivy.Session.verify(
        %{
          access: sign.(claims),
          identity: sign.(Map.put(claims, "linked_accounts", Jason.encode!(linked_accounts)))
        },
        app_id: "test-app",
        verification_key: pem
      )

    session
  end
end
