defmodule AshTemplate.Accounts.SessionPrunerTest do
  # Sign-in session rows are deleted only once no browser can still hold them: a
  # day longer than the cookie lives after they were last touched. Whatever a row
  # is (never signed in, signed in, revoked), one touched inside that time stays,
  # and so does everyone's current sign-in.
  use ExUnit.Case, async: false
  use Oban.Testing, repo: AshTemplate.Repo, prefix: "ash_template_app"

  alias AshTemplate.Accounts
  alias AshTemplate.Accounts.{SessionAuthority, SessionPruner}
  alias AshTemplate.Actors.System

  @day 86_400
  @lifetime Application.compile_env!(:ash_template, [:session_options, :max_age])

  setup do
    owner = Ecto.Adapters.SQL.Sandbox.start_owner!(AshTemplate.Repo, shared: true)
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(owner) end)

    wallet = "0x" <> String.duplicate("6", 40)
    %{account: Accounts.register_verified!("did:privy:session-pruner", wallet, [wallet], actor: %System{})}
  end

  test "only rows untouched for a day longer than the cookie lives are deleted", %{account: account} do
    past = fn seconds -> DateTime.add(DateTime.utc_now(), -seconds, :second) end
    old = @lifetime + @day + 60
    recent = @lifetime + @day - 60

    kinds = [
      unbound: %{},
      bound: %{human_account_id: account.id, generation: 3},
      revoked: %{human_account_id: account.id, generation: 2, revoked?: true}
    ]

    rows =
      for {kind, fields} <- kinds, {age, seconds} <- [old: old, recent: recent, today: 0] do
        touched = past.(seconds)
        {revoked?, fields} = Map.pop(fields, :revoked?, false)

        row =
          Ash.Seed.seed!(
            SessionAuthority,
            Map.merge(fields, %{
              lineage_digest: :crypto.strong_rand_bytes(32),
              signed_in_at: fields[:human_account_id] && touched,
              revoked_at: revoked? && touched || nil,
              inserted_at: touched,
              updated_at: touched
            })
          )

        {{kind, age}, row.id}
      end

    assert :ok = perform_job(SessionPruner, %{})

    left = SessionAuthority |> Ash.read!(actor: %System{}) |> MapSet.new(& &1.id)

    for {{kind, age}, id} <- rows do
      assert {kind, age, MapSet.member?(left, id)} == {kind, age, age != :old}
    end

    # A second run finds nothing more to delete.
    assert {:ok, 0} = SessionAuthority.prune()
  end
end
