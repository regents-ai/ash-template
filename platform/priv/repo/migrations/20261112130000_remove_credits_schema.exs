defmodule AshTemplate.Repo.Migrations.RemoveCreditsSchema do
  @moduledoc """
  Removes the shared `regent_credits` schema: Credits are gone from every Regent
  site (Sean, 12 November 2026). The ten Credits tables came off the founder's
  protected-tables list on production on 12 November 2026 (Sean's 18 a), and
  this migration no longer touches the list. In one transaction, in this order:

  1. The thirteen tables.
  2. The trigger the Credits package put on `regent_agents.paired_agents`.
  3. The schema's two functions.
  4. The schema.

  Nothing cascades: anything else that still depends on one of them stops the
  migration, and the whole of it rolls back.

  Each statement names its objects `IF EXISTS`, so a database without Credits,
  such as a local or test database, is left as it is.

  Hand-written; no resource changes.
  """

  use Ecto.Migration

  def up do
    execute("SET LOCAL lock_timeout = '5s'")

    execute("""
    DROP TABLE IF EXISTS
      regent_credits.accounts,
      regent_credits.agent_permissions,
      regent_credits.balances,
      regent_credits.card_purchases,
      regent_credits.deposit_cursors,
      regent_credits.first_uses,
      regent_credits.gifts,
      regent_credits.holds,
      regent_credits.purchases,
      regent_credits.refunds,
      regent_credits.schema_migrations,
      regent_credits.transfers,
      regent_credits.wallets
    """)

    execute("DROP TRIGGER IF EXISTS revoke_credit_grant ON regent_agents.paired_agents")

    execute("""
    DROP FUNCTION IF EXISTS
      regent_credits.refuse_change(),
      regent_credits.revoke_pairing_grant()
    """)

    execute("DROP SCHEMA IF EXISTS regent_credits")
  end

  def down, do: raise(Ecto.MigrationError, "the Credits schema and its rows cannot be restored")
end
