defmodule AshTemplate.Repo.Migrations.EnsLookupStateOptional do
  @moduledoc """
  The ENS table's `lookup_state` column (`account_ens_identities`) stops
  needing a value. Nothing reads it, and the code released with this migration
  saves rows without it; the next release drops the column. The release this
  one replaces still writes it while it runs, which keeps working. No row is
  rewritten or changed.

  Its `down` makes the column need a value again, which fails once a row has
  been saved without one.

  Generated with `mix ash.codegen ens_lookup_state_optional`, from the resource
  with the attribute made optional before it was removed.
  """

  use Ecto.Migration

  def up do
    execute("SET LOCAL lock_timeout = '5s'")

    alter table(:account_ens_identities) do
      modify(:lookup_state, :text, null: true)
    end
  end

  def down do
    alter table(:account_ens_identities) do
      modify(:lookup_state, :text, null: false)
    end
  end
end
