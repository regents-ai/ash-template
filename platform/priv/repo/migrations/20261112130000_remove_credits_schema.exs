defmodule AshTemplate.Repo.Migrations.RemoveCreditsSchema do
  @moduledoc """
  Removes the shared `regent_credits` schema: Credits are gone from every Regent
  site (Sean, 12 November 2026). In one transaction, in this order:

  1. The founder's protected-tables lock comes off exactly the ten Credits tables
     that carry it (Sean's 18 a, 12 November 2026): each one's guard view and its
     row in `regent_guard.protected_tables`. The lock's triggers on those tables
     go with the tables in step 2. Every other protected table keeps its lock.
  2. The thirteen tables.
  3. The trigger the Credits package put on `regent_agents.paired_agents`.
  4. The schema's two functions.
  5. The schema.

  Nothing cascades: anything else that still depends on one of them stops the
  migration, and the whole of it rolls back with the lock still on.

  Each statement names its objects `IF EXISTS`, and the list's rows go only where
  the list exists, so a database without the lock or without Credits, such as a
  local or test database, is left as it is.

  Hand-written; no resource changes.
  """

  use Ecto.Migration

  def up do
    execute("SET LOCAL lock_timeout = '5s'")

    execute("""
    DROP VIEW IF EXISTS
      regent_guard.keep_regent_credits__accounts,
      regent_guard.keep_regent_credits__agent_permissions,
      regent_guard.keep_regent_credits__balances,
      regent_guard.keep_regent_credits__first_uses,
      regent_guard.keep_regent_credits__gifts,
      regent_guard.keep_regent_credits__holds,
      regent_guard.keep_regent_credits__purchases,
      regent_guard.keep_regent_credits__refunds,
      regent_guard.keep_regent_credits__transfers,
      regent_guard.keep_regent_credits__wallets
    """)

    execute("""
    DO $$
    BEGIN
      IF to_regclass('regent_guard.protected_tables') IS NOT NULL THEN
        DELETE FROM regent_guard.protected_tables WHERE name IN (
          'regent_credits.accounts',
          'regent_credits.agent_permissions',
          'regent_credits.balances',
          'regent_credits.first_uses',
          'regent_credits.gifts',
          'regent_credits.holds',
          'regent_credits.purchases',
          'regent_credits.refunds',
          'regent_credits.transfers',
          'regent_credits.wallets'
        );
      END IF;
    END
    $$
    """)

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
