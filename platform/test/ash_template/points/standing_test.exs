defmodule AshTemplate.Points.StandingTest do
  # Invariant: before the start, an account's Points read names, of the start
  # actions this site counts, the ones the account already has, so its page and its
  # agent show what the start will add; what it does not have yet is still to do.
  # From the start on nothing is foretold. No action this site does not count is
  # ever listed.
  use ExUnit.Case, async: false

  alias AshTemplate.Accounts.VerifiedSession
  alias AshTemplate.Actors.Human
  alias AshTemplateWeb.PointsEntries

  @counted ~w(account.activated social.x social.github agent.activated)

  setup do
    owner = Ecto.Adapters.SQL.Sandbox.start_owner!(AshTemplate.Repo, shared: true)
    previous = Map.new([:starts_at, :approved_rules], &{&1, Application.get_env(:regent_points, &1)})
    Application.put_env(:regent_points, :starts_at, nil)
    Application.put_env(:regent_points, :approved_rules, @counted)

    on_exit(fn ->
      Enum.each(previous, fn {key, value} -> Application.put_env(:regent_points, key, value) end)
      Ecto.Adapters.SQL.Sandbox.stop_owner(owner)
    end)
  end

  test "an account with nothing linked or paired would get only its account at the start" do
    standing = standing(account([]))

    assert standing.at_start == ["account.activated"]
    assert left(standing) == ~w(social.x social.github agent.activated)
  end

  test "a linked X and a paired agent are added at the start; an uncounted link is never listed" do
    did = "did:privy:standing-" <> Ecto.UUID.generate()
    x = %{provider: :x, subject: "x-" <> Ecto.UUID.generate(), username: "early"}
    farcaster = %{provider: :farcaster, subject: "fc-" <> Ecto.UUID.generate(), username: "early"}
    person = account(did, [x, farcaster])
    pair(did)

    standing = standing(person)

    assert standing.at_start == ~w(account.activated social.x agent.activated)
    assert left(standing) == ["social.github"]

    listed = for group <- PointsEntries.todo(standing), item <- group.items, do: item.id
    assert Enum.sort(listed) == Enum.sort(@counted)
  end

  test "from the start on, nothing is foretold" do
    Application.put_env(:regent_points, :starts_at, DateTime.add(DateTime.utc_now(), -1, :day))

    assert standing(account([])).at_start == []
  end

  test "a start in the future still foretells what the start adds" do
    Application.put_env(:regent_points, :starts_at, DateTime.add(DateTime.utc_now(), 2, :day))

    standing = standing(account([]))
    assert standing.at_start == ["account.activated"]
    assert Enum.map(standing.seasons, & &1.earned_micro) == [nil, nil, nil]
  end

  defp standing(account) do
    {:ok, standing} = AshTemplate.Points.my_points(actor: Human.for_account(account))
    standing
  end

  defp left(standing) do
    for group <- PointsEntries.todo(standing), item <- group.items, item.left, do: item.id
  end

  defp account(linked), do: account("did:privy:standing-" <> Ecto.UUID.generate(), linked)

  defp account(did, linked) do
    wallet = "0x" <> String.slice(Base.encode16(:crypto.hash(:sha, did), case: :lower), 0, 40)

    {:ok, account, []} =
      VerifiedSession.establish(%RegentPrivy.Session{
        app_id: "test-app",
        session_id: "standing",
        privy_user_id: did,
        wallet_address: wallet,
        wallet_addresses: [wallet],
        linked_socials: linked,
        issued_at: :erlang.system_time(:second),
        expires_at: :erlang.system_time(:second) + 3600
      })

    account
  end

  defp pair(did) do
    code = RegentAgents.issue_pairing_code!(actor: %RegentAgents.Person{privy_user_id: did})
    wallet = "0x" <> Base.encode16(:crypto.strong_rand_bytes(20), case: :lower)
    RegentAgents.pair_agent!(code.code, "Early", :codex, actor: %RegentAgents.Agent{wallet: wallet})
  end
end
