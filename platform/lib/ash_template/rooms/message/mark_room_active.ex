defmodule AshTemplate.Rooms.Message.MarkRoomActive do
  @moduledoc """
  Moves the post's room to the top of the list of rooms once the post is saved,
  in the same transaction (`AshTemplate.Rooms.Room` `:mark_active`), so the
  room's time and its messages never disagree. The room's notice, which carries
  all the list draws of it, goes out with the post's own, after the commit.
  """

  use Ash.Resource.Change

  alias AshTemplate.Actors.System
  alias AshTemplate.Rooms

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.after_action(changeset, fn _changeset, message ->
      case Rooms.mark_room_active(message.room, message.inserted_at,
             actor: %System{},
             return_notifications?: true
           ) do
        {:ok, _room, notifications} -> {:ok, message, notifications}
        {:error, error} -> {:error, error}
      end
    end)
  end
end
