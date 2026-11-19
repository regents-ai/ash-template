defmodule AshTemplate.Accounts.SocialRefreshTest do
  # Invariant: a sign-in that finds its social account already linked to the
  # account still signs in when the person's other sign-in removes or replaces
  # that link at the same moment, and it only ever writes a subject's own name
  # onto that subject's row.
  #
  # The other sign-in holds its change open while this one reaches the linked
  # account, then commits; that needs separate connections that really commit.
  use ExUnit.Case, async: false

  alias AshTemplate.{Accounts, Repo}
  alias AshTemplate.Accounts.VerifiedSession
  alias AshTemplate.Actors.System

  @actor %System{}

  setup do
    AshTemplate.RealCommits.start()
    did = "did:privy:refresh-" <> Ecto.UUID.generate()
    x = %{provider: :x, subject: "x-" <> Ecto.UUID.generate(), username: "first"}
    assert {:ok, account, []} = did |> session([x]) |> VerifiedSession.establish()
    {:ok, link} = Accounts.get_linked_identity_by_subject(:x, x.subject, actor: @actor)
    %{did: did, x: x, account: account, link: link}
  end

  test "the other sign-in replaces the link: this one signs in and keeps each name on its own subject",
       %{did: did, x: x, account: account, link: link} do
    replacement = %{
      provider: :x,
      subject: "x-" <> Ecto.UUID.generate(),
      username: "replacement",
      verified_at: DateTime.utc_now(),
      metadata: %{},
      human_account_id: account.id
    }

    assert {:ok, _account, []} =
             sign_in_during(did, [%{x | username: "renamed"}], fn ->
               Accounts.upsert_linked_identity!(replacement, actor: @actor)
             end)

    # This sign-in came last, so its subject is linked again, with its own name.
    assert {:ok, [%{subject: subject, username: "renamed", inserted_at: relinked_at}]} =
             Accounts.list_linked_identities_for_account(account.id, actor: @actor)

    assert subject == x.subject
    assert DateTime.after?(relinked_at, link.inserted_at)
  end

  test "the other sign-in removes the link: this one signs in and links it again",
       %{did: did, x: x, account: account, link: link} do
    assert {:ok, _account, []} =
             sign_in_during(did, [%{x | username: "renamed"}], fn ->
               :ok = Accounts.remove_linked_identity(link, actor: @actor)
             end)

    assert {:ok, [%{subject: subject, username: "renamed"}]} =
             Accounts.list_linked_identities_for_account(account.id, actor: @actor)

    assert subject == x.subject
  end

  test "with nothing else changing, a sign-in refreshes the link and leaves when it was linked",
       %{did: did, x: x, account: account, link: link} do
    assert {:ok, _account, []} =
             did |> session([%{x | username: "renamed"}]) |> VerifiedSession.establish()

    assert {:ok, [refreshed]} =
             Accounts.list_linked_identities_for_account(account.id, actor: @actor)

    assert %{id: id, subject: subject, username: "renamed", inserted_at: linked_at} = refreshed
    assert {id, subject, linked_at} == {link.id, x.subject, link.inserted_at}
    assert DateTime.after?(refreshed.verified_at, link.verified_at)
  end

  test "a subject another account holds is reported, and that account's link is left as it was",
       %{x: x, link: link} do
    someone = "did:privy:someone-" <> Ecto.UUID.generate()
    assert {:ok, _account, []} = someone |> session([]) |> VerifiedSession.establish()

    assert {:ok, _account, [:x]} =
             someone |> session([%{x | username: "taken"}]) |> VerifiedSession.establish()

    assert {:ok, %{id: id, username: "first", human_account_id: holder}} =
             Accounts.get_linked_identity_by_subject(:x, x.subject, actor: @actor)

    assert {id, holder} == {link.id, link.human_account_id}
  end

  # The other sign-in's change runs in a transaction it keeps open until this
  # sign-in waits on the row that change holds; it then commits, and this
  # sign-in finishes.
  defp sign_in_during(did, socials, change) do
    test = self()

    other =
      Task.async(fn ->
        Repo.transaction(fn ->
          change.()
          send(test, :changed)

          receive do
            :commit -> :ok
          end
        end)
      end)

    assert_receive :changed, 5_000
    this = Task.async(fn -> did |> session(socials) |> VerifiedSession.establish() end)
    wait_until_blocked()
    send(other.pid, :commit)
    assert {:ok, :ok} = Task.await(other)
    Task.await(this)
  end

  defp wait_until_blocked(tries \\ 500) do
    %{rows: [[waiting]]} =
      Repo.query!("select count(*) from pg_locks where not granted and locktype = 'transactionid'")

    cond do
      waiting > 0 -> :ok
      tries == 0 -> flunk("this sign-in never reached the row the other sign-in holds")
      true ->
        Process.sleep(10)
        wait_until_blocked(tries - 1)
    end
  end

  defp session(did, linked_socials) do
    wallet = "0x" <> String.slice(Base.encode16(:crypto.hash(:sha, did), case: :lower), 0, 40)

    %RegentPrivy.Session{
      app_id: "test-app",
      session_id: "test-session",
      privy_user_id: did,
      wallet_address: wallet,
      wallet_addresses: [wallet],
      linked_socials: linked_socials,
      issued_at: :erlang.system_time(:second),
      expires_at: :erlang.system_time(:second) + 3600
    }
  end
end
