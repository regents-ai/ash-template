defmodule AshTemplate.Repo.Migrations.RoomAuthorWallets do
  @moduledoc """
  Rooms show an author who chose no name by their wallet, with its copy icon
  (every wallet is public: Sean, 6 Nov 2026). Each post, and each mute of its
  author, keeps the author's wallet and ENS name beside the name they chose,
  which is now empty when they had none.

  Posts and mutes saved before this keep the name they were saved with, the
  ENS name, short wallet or "Unnamed agent" among them. Those three are emptied
  here, and each author's wallet, and a person's ENS name, is filled in from
  their account or agent.

  It runs in one transaction that holds both tables' locks until it ends, so
  room posts and mutes wait for it; it gives up after waiting five seconds for
  those locks rather than queueing every room read behind it.
  """

  use Ecto.Migration

  def up do
    execute("SET LOCAL lock_timeout = '5s'")

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

    for {table, who, account, agent} <- [
          {"room_messages", "author", "human_account_id", "agent_id"},
          {"room_mutes", "muted", "muted_account_id", "muted_agent_id"}
        ] do
      # One pass for people and one for agents, so each row is written once.
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
      WHERE m.#{account} = h.id
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

  def down do
    execute("SET LOCAL lock_timeout = '5s'")

    for {table, who} <- [{"room_messages", "author"}, {"room_mutes", "muted"}] do
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
  end

  # The short wallet rooms saved as a name: 0x, its first four and last four characters.
  defp short(wallet), do: "'0x' || substr(#{wallet}, 3, 4) || '..' || right(#{wallet}, 4)"
end
