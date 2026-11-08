defmodule AshTemplate.Repo.Migrations.AgentOwnedAccounts do
  @moduledoc """
  Adds `agent_owned_accounts`: the account an agent's own wallet opened
  (`AshTemplate.Accounts.AgentOwnedAccount`). It only adds a table; no existing
  row or column changes. The reference to the shared account table waits at most
  five seconds for its lock, then fails rather than holding up sign-ins.
  """

  use Ecto.Migration

  def up do
    execute("SET LOCAL lock_timeout = '5s'")

    create table(:agent_owned_accounts, primary_key: false) do
      add(:wallet_address, :text, null: false, primary_key: true)

      add(:inserted_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")
      )

      add(
        :human_account_id,
        references(:platform_human_users,
          column: :id,
          name: "agent_owned_accounts_human_account_id_fkey",
          type: :bigint,
          prefix: "regent_names"
        ), null: false)
    end
  end

  def down do
    drop(table(:agent_owned_accounts))
  end
end
