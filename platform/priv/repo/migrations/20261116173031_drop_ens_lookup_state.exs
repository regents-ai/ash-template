defmodule AshTemplate.Repo.Migrations.DropEnsLookupState do
  @moduledoc """
  Drops the ENS table's `lookup_state` column (`account_ens_identities`), which
  the release before this one already neither reads nor writes, so its
  machines keep serving while this runs. Every row keeps its wallet, name and
  picture.

  Its `down` adds the column back empty and not needing a value.

  Generated with `mix ash.codegen drop_ens_lookup_state`.
  """

  use Ecto.Migration

  def up do
    execute("SET LOCAL lock_timeout = '5s'")

    alter table(:account_ens_identities) do
      remove(:lookup_state)
    end
  end

  def down do
    alter table(:account_ens_identities) do
      add(:lookup_state, :text)
    end
  end
end
