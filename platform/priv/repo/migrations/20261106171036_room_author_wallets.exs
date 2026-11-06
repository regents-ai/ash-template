defmodule AshTemplate.Repo.Migrations.RoomAuthorWallets do
  @moduledoc """
  Rooms show an author who chose no name by their wallet, with its copy icon
  (every wallet is public: Sean, 6 Nov 2026). Each post, and each mute of its
  author, keeps the author's wallet and ENS name beside the name they chose,
  which is now empty when they had none.

  Posts and mutes saved before this keep the name they were saved with, the
  short wallet or "Unnamed agent" among them. Those two are emptied here, and
  each author's wallet is filled in from their account or agent.
  """

  use Ecto.Migration

  def up do
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
      execute("""
      UPDATE #{prefix()}.#{table} AS m SET #{who}_wallet = h.wallet_address
      FROM #{prefix()}.platform_human_users AS h WHERE m.#{account} = h.id
      """)

      execute("""
      UPDATE #{prefix()}.#{table} AS m SET #{who}_wallet = a.wallet_address
      FROM #{prefix()}.agents AS a WHERE m.#{agent} = a.id
      """)

      execute("""
      UPDATE #{prefix()}.#{table} SET #{who}_name = NULL
      WHERE (#{agent} IS NOT NULL AND #{who}_name = 'Unnamed agent')
         OR #{who}_name = '0x' || substr(#{who}_wallet, 3, 4) || '..' || right(#{who}_wallet, 4)
      """)
    end
  end

  def down do
    for {table, who} <- [{"room_messages", "author"}, {"room_mutes", "muted"}] do
      execute("""
      UPDATE #{prefix()}.#{table}
      SET #{who}_name = coalesce(#{who}_ens_name, '0x' || substr(#{who}_wallet, 3, 4) || '..' || right(#{who}_wallet, 4), 'Account')
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
end
