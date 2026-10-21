defmodule AshTemplate.Rooms.Like.InMessagesRoom do
  @moduledoc "Files a like under the room of the message named by `message_id`, while that message is still here."

  use Ash.Resource.Change

  alias AshTemplate.Rooms
  alias AshTemplate.Rooms.Message

  @impl true
  def change(changeset, _opts, context) do
    message_id = Ash.Changeset.get_attribute(changeset, :message_id)

    case Rooms.get_message(message_id, Ash.Context.to_opts(context)) do
      {:ok, %Message{room: room}} ->
        Ash.Changeset.force_change_attribute(changeset, :room, room)

      _gone ->
        Ash.Changeset.add_error(changeset,
          field: :message_id,
          message: "That message is no longer here."
        )
    end
  end
end
