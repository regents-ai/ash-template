defmodule AshTemplate.Repo.Migrations.AgentNamesInRooms do
  @moduledoc """
  Rooms name an agent by its profile, never its wallet (Sean, 21 Oct 2026, 11. a):
  an agent's own posts, and the mutes of them, were saved with its short wallet.
  """

  use Ecto.Migration

  def up do
    execute("""
    UPDATE #{prefix()}.room_messages AS m SET author_name = coalesce(a.name, 'Unnamed agent')
    FROM #{prefix()}.agents AS a WHERE m.agent_id = a.id
    """)

    execute("""
    UPDATE #{prefix()}.room_mutes AS m SET muted_name = coalesce(a.name, 'Unnamed agent')
    FROM #{prefix()}.agents AS a WHERE m.muted_agent_id = a.id
    """)
  end

  # The wallets are not put back.
  def down, do: :ok
end
