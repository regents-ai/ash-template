defmodule AshTemplate.Repo.Migrations.NamesKeepTheWallet do
  @moduledoc """
  A person with no display name is kept with no name, so rooms show their wallet
  with its copy icon (`AshTemplate.Rooms.Author`), never a short address saved
  as their name. Messages and mutes saved with a person's short wallet as their
  name lose it.
  """

  use Ecto.Migration

  def up do
    alter table(:room_messages) do
      modify(:author_name, :text, null: true)
    end

    alter table(:room_mutes) do
      modify(:muted_name, :text, null: true)
    end

    execute("""
    UPDATE #{prefix()}.room_messages AS m SET author_name = NULL
    FROM regent_names.platform_human_users AS h
    WHERE m.agent_id IS NULL AND m.human_account_id = h.id
      AND lower(m.author_name) = lower('0x' || substr(h.wallet_address, 3, 4) || '..' || right(h.wallet_address, 4))
    """)

    execute("""
    UPDATE #{prefix()}.room_mutes AS m SET muted_name = NULL
    FROM regent_names.platform_human_users AS h
    WHERE m.muted_account_id = h.id
      AND lower(m.muted_name) = lower('0x' || substr(h.wallet_address, 3, 4) || '..' || right(h.wallet_address, 4))
    """)
  end

  # The short addresses are written back where a person has no name.
  def down do
    execute("""
    UPDATE #{prefix()}.room_messages AS m
    SET author_name = '0x' || substr(h.wallet_address, 3, 4) || '..' || right(h.wallet_address, 4)
    FROM regent_names.platform_human_users AS h
    WHERE m.author_name IS NULL AND m.human_account_id = h.id
    """)

    execute("""
    UPDATE #{prefix()}.room_mutes AS m
    SET muted_name = '0x' || substr(h.wallet_address, 3, 4) || '..' || right(h.wallet_address, 4)
    FROM regent_names.platform_human_users AS h
    WHERE m.muted_name IS NULL AND m.muted_account_id = h.id
    """)

    alter table(:room_mutes) do
      modify(:muted_name, :text, null: false)
    end

    alter table(:room_messages) do
      modify(:author_name, :text, null: false)
    end
  end
end
