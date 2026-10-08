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
      linked_socials: []
    }

    assert {:ok, account, []} = VerifiedSession.establish(session)
    assert account.wallet_addresses == [@first]

    assert {:ok, again, []} =
             VerifiedSession.establish(%{session | wallet_addresses: [@first, @second]})

    assert again.id == account.id
    assert again.wallet_addresses == [@first, @second]
  end
end
