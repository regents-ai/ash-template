defmodule AshTemplate.Accounts.SessionAuthorityTest do
  # Every sign-in, refresh and sign-out ran in a transaction Ash did not start, so
  # production logged a missed notification for each; the test settings raise on
  # one. An exhausted lineage is revoked and refused in one transaction, and the
  # revocation must commit although the answer is an error.
  use ExUnit.Case, async: true

  alias AshTemplate.Accounts.{SessionAuthority, VerifiedSession}
  alias AshTemplate.Repo

  @maximum_generation 9_223_372_036_854_775_807

  setup do
    owner = Ecto.Adapters.SQL.Sandbox.start_owner!(Repo)
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(owner) end)
  end

  test "a person signs in, refreshes, signs in as someone else and signs out" do
    first = account("first", "a")
    second = account("second", "b")

    {:bootstrap, claim} = SessionAuthority.renew(nil)
    assert {:ok, :bind, bound} = SessionAuthority.sign_in(claim, first.id)
    assert {:ok, :refresh, refreshed} = SessionAuthority.sign_in(bound, first.id)
    assert refreshed.generation == bound.generation + 1
    assert {:error, :superseded} = SessionAuthority.sign_in(bound, first.id)

    topic = SessionAuthority.topic(refreshed.lineage)
    assert {:switch, ^topic} = SessionAuthority.sign_in(refreshed, second.id)
    assert {nil, nil, nil} = SessionAuthority.resolve(refreshed)

    {:bootstrap, fresh} = SessionAuthority.renew(nil)
    assert {:ok, :bind, signed_in} = SessionAuthority.sign_in(fresh, second.id)
    assert SessionAuthority.revoke(signed_in) == SessionAuthority.topic(signed_in.lineage)
    assert {:error, :reset} = SessionAuthority.renew(signed_in)
  end

  test "an exhausted lineage is refused and stays revoked" do
    person = account("exhausted", "e")
    {:bootstrap, claim} = SessionAuthority.renew(nil)
    {:ok, :bind, bound} = SessionAuthority.sign_in(claim, person.id)

    Repo.query!(
      "UPDATE ash_template_app.session_authorities SET generation = $1 WHERE lineage_digest = $2",
      [@maximum_generation, :crypto.hash(:sha256, bound.lineage)]
    )

    exhausted = %{bound | generation: @maximum_generation}
    assert {:error, :reset} = SessionAuthority.sign_in(exhausted, person.id)

    assert %{rows: [[revoked_at]]} =
             Repo.query!(
               "SELECT revoked_at FROM ash_template_app.session_authorities WHERE lineage_digest = $1",
               [:crypto.hash(:sha256, bound.lineage)]
             )

    assert revoked_at
    assert {:error, :reset} = SessionAuthority.sign_in(exhausted, person.id)
  end

  defp account(name, digit) do
    wallet = "0x" <> String.duplicate(digit, 40)

    {:ok, account, []} =
      VerifiedSession.establish(%RegentPrivy.Session{
        app_id: "test-app",
        session_id: "session-" <> name,
        privy_user_id: "did:privy:session-authority-" <> name,
        wallet_address: wallet,
        wallet_addresses: [wallet],
        linked_socials: []
      })

    account
  end
end
