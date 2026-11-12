defmodule AshTemplate.Repo.Migrations.RemoveCreditsSchema do
  @moduledoc """
  Removes the shared `regent_credits` schema: Credits are gone from every Regent
  site (Sean, 12 November 2026). Its thirteen tables go first, then the trigger the
  Credits package put on `regent_agents.paired_agents`, then the schema's two
  functions, then the schema. Nothing cascades: anything else that still depends
  on one of them stops the migration, and the whole of it rolls back.

  Each statement names its object `IF EXISTS`, so a database that never had
  Credits, such as a local or test database, is left as it is.

  On the shared production database ten of the tables are on the founder's
  protected-tables lock, whose guard views make this migration fail until Sean's
  lock comes off those ten.

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
