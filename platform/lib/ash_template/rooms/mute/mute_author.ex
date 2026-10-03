defmodule AshTemplate.Rooms.Mute.MuteAuthor do
  @moduledoc "Mutes the author of the message named by `message_id`, never the muter themselves."

  use Ash.Resource.Change

  alias AshTemplate.Rooms
  alias AshTemplate.Rooms.Message

  @impl true
  def change(changeset, _opts, context) do
    muter = Ash.Changeset.get_attribute(changeset, :muter_account_id)
    message_id = Ash.Changeset.get_argument(changeset, :message_id)

    case Rooms.get_message(message_id, Ash.Context.to_opts(context)) do
      {:ok, %Message{human_account_id: ^muter}} ->
        Ash.Changeset.add_error(changeset,
          field: :message_id,
          message: "You can't mute yourself."
        )

      {:ok, %Message{} = message} ->
        Ash.Changeset.force_change_attributes(changeset,
          muted_account_id: message.human_account_id,
          muted_name: message.author_name
        )

      _gone ->
        Ash.Changeset.add_error(changeset,
          field: :message_id,
          message: "That message is no longer here."
        )
    end
  end
end
