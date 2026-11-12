defmodule AshTemplate.Repo.Migrations.ClearShortWalletNames do
  @moduledoc """
  A short wallet saved as a person's name is not a name, whichever wallet it was
  shortened from (decision 11a, 12 Nov 2026: "names keep their wallet").
  `20261112151609_show_nameless_by_wallet` empties a saved short wallet only when it
  is the account's current wallet's. A person whose account has since moved to
  another wallet keeps the old one's, which a page prints as plain words with no
  copy icon. Here every such name is emptied, so the row shows by the wallet saved
  beside it, with its copy icon.

  Only names that came from a person's account change: a room post or a mute whose
  author is no agent, and a message left for the team by a person or by an agent
  paired with one (`human_account_id` set). An agent posting as itself keeps its
  profile name. A row with no wallet beside it keeps its name, since it would have
  nothing to show in its place.

  Its down changes nothing: an emptied name was the short form of a wallet the row
  no longer records. The down of `20261112151609` gives every empty name its ENS
  name or short wallet back.
  """

  use Ecto.Migration

  # A short wallet as `RegentFormat.short_address/1` writes it.
  @short_wallet "^0x[0-9a-fA-F]{4}\\.\\.[0-9a-fA-F]{4}$"

  # Each table, the prefix of its name and wallet columns, and its rows whose name
  # came from a person's account.
  @tables [
    {"room_messages", "author", "agent_id IS NULL"},
    {"room_mutes", "muted", "muted_agent_id IS NULL"},
    {"left_messages", "sender", "human_account_id IS NOT NULL"}
  ]

  def up do
    execute("SET LOCAL lock_timeout = '5s'")
    Enum.each(clear(prefix()), &execute/1)
  end

  def down, do: :ok

  @doc "The statements `up/0` runs in the schema `prefix`."
  def clear(prefix) do
    for {table, who, person} <- @tables do
      """
      UPDATE #{prefix}.#{table}
      SET #{who}_name = NULL
      WHERE #{person} AND #{who}_wallet IS NOT NULL AND #{who}_name ~ '#{@short_wallet}'
      """
    end
  end
end
