defmodule AshTemplate.Repo.Migrations.NamesKeepTheWallet do
  @moduledoc """
  A person with no display name is kept with no name, so rooms show their wallet
  with its copy icon (`AshTemplate.Rooms.Author`), never a short address saved
  as their name. Messages and mutes saved with a person's short wallet as their
  name lose it, whichever wallet it was shortened from: a person who has since
  changed wallets kept the old one's short form.
  """

  use Ecto.Migration

  # A short wallet as `RegentFormat.short_address/1` writes it.
  @short_wallet "^0x[0-9a-fA-F]{4}\\.\\.[0-9a-fA-F]{4}$"

  def up do
    alter table(:room_messages) do
      modify(:author_name, :text, null: true)
    end

    alter table(:room_mutes) do
      modify(:muted_name, :text, null: true)
    end

    Enum.each(clear_short_wallets(prefix()), &execute/1)
  end

  @doc "The statements that clear stored short wallets in `prefix`; a test runs them on its own rows."
  def clear_short_wallets(prefix) do
    [
      """
      UPDATE #{prefix}.room_messages SET author_name = NULL
      WHERE agent_id IS NULL AND author_name ~ '#{@short_wallet}'
      """,
      """
      UPDATE #{prefix}.room_mutes SET muted_name = NULL
      WHERE muted_agent_id IS NULL AND muted_name ~ '#{@short_wallet}'
      """
    ]
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
