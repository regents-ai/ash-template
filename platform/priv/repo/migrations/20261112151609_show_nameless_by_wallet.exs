defmodule AshTemplate.Repo.Migrations.ShowNamelessByWallet do
  @moduledoc """
  Someone who chose no name shows by their wallet, with its copy icon (every
  wallet is public: Sean, 6 Nov 2026). Each room post, each mute of its author
  and each message left for the site's team keeps the wallet and ENS name of
  who wrote it beside the name they chose, which is now empty when they had
  none.

  Rows saved before this keep the name they were saved with: the ENS name,
  short wallet or "Unnamed agent" among them. Those three are emptied here, and
  each wallet, and a person's ENS name, is filled in from their account
  (`regent_names.platform_human_users`, `account_ens_identities`) or agent. A
  message a paired agent left for the team is the agent's, so it takes the
  agent's wallet.

  It runs in one transaction that holds the three tables' locks until it ends,
  so their writes wait for it; it gives up after waiting five seconds for those
  locks rather than queueing every read behind it.

  Columns generated with `mix ash.codegen show_nameless_by_wallet`; the fill
  written by hand.
  """

  use Ecto.Migration

  # Each table, the prefix of its three columns, and its account and agent columns.
  @tables [
    {"room_messages", "author", "human_account_id", "agent_id"},
    {"room_mutes", "muted", "muted_account_id", "muted_agent_id"},
    {"left_messages", "sender", "human_account_id", "agent_id"}
  ]

  def up do
    execute("SET LOCAL lock_timeout = '5s'")

    alter table(:left_messages) do
      add(:sender_wallet, :text)
      add(:sender_ens_name, :text)
      modify(:sender_name, :text, null: true)
    end

    alter table(:room_messages) do
      add(:author_wallet, :text)
      add(:author_ens_name, :text)
      modify(:author_name, :text, null: true)
    end

    alter table(:room_mutes) do
      add(:muted_wallet, :text)
      add(:muted_ens_name, :text)
      modify(:muted_name, :text, null: true)
    end

    flush()

    # One pass for people and one for agents, so each row is written once.
    for {table, who, account, agent} <- @tables do
      execute("""
      UPDATE #{prefix()}.#{table} AS m
      SET #{who}_wallet = h.wallet_address,
          #{who}_ens_name = e.ens_name,
          #{who}_name = CASE
            WHEN m.#{who}_name = e.ens_name OR m.#{who}_name = #{short("h.wallet_address")} THEN NULL
            ELSE m.#{who}_name
          END
      FROM regent_names.platform_human_users AS h
      LEFT JOIN #{prefix()}.account_ens_identities AS e
        ON e.human_account_id = h.id AND e.wallet_address = h.wallet_address
      WHERE m.#{account} = h.id AND m.#{agent} IS NULL
      """)

      execute("""
      UPDATE #{prefix()}.#{table} AS m
      SET #{who}_wallet = a.wallet_address,
          #{who}_name = CASE
            WHEN m.#{who}_name = 'Unnamed agent' OR m.#{who}_name = #{short("a.wallet_address")} THEN NULL
            ELSE m.#{who}_name
          END
      FROM #{prefix()}.agents AS a
      WHERE m.#{agent} = a.id
      """)
    end
  end

  # Gives every empty name back the words a page showed for it, the ENS name or
  # short wallet, so the names can be required again. An agent with no name gets
  # its short wallet, not "Unnamed agent".
  def down do
    execute("SET LOCAL lock_timeout = '5s'")

    for {table, who, _account, _agent} <- @tables do
      execute("""
      UPDATE #{prefix()}.#{table}
      SET #{who}_name = coalesce(#{who}_ens_name, #{short("#{who}_wallet")}, 'Account')
      WHERE #{who}_name IS NULL
      """)
    end

    alter table(:room_mutes) do
      modify(:muted_name, :text, null: false)
      remove(:muted_ens_name)
      remove(:muted_wallet)
    end

    alter table(:room_messages) do
      modify(:author_name, :text, null: false)
      remove(:author_ens_name)
      remove(:author_wallet)
    end

    alter table(:left_messages) do
      modify(:sender_name, :text, null: false)
      remove(:sender_ens_name)
      remove(:sender_wallet)
    end
  end

  # The short wallet the site saved as a name: 0x, its first four and last four characters.
  defp short(wallet), do: "'0x' || substr(#{wallet}, 3, 4) || '..' || right(#{wallet}, 4)"
end
