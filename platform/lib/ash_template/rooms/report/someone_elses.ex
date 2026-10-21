defmodule AshTemplate.Rooms.Report.SomeoneElses do
  @moduledoc "Reports the message named by `message_id` while it is still here, and only when someone else wrote it."

  use Ash.Resource.Change

  alias AshTemplate.Rooms
  alias AshTemplate.Rooms.Message

  @impl true
  def change(changeset, _opts, context) do
    reporter = Ash.Changeset.get_attribute(changeset, :reporter_id)
    message_id = Ash.Changeset.get_attribute(changeset, :message_id)

    case Rooms.get_message(message_id, Ash.Context.to_opts(context)) do
      {:ok, %Message{human_account_id: ^reporter}} ->
        Ash.Changeset.add_error(changeset,
          field: :message_id,
          message: "You can't report your own message."
        )

      {:ok, %Message{}} ->
        changeset

      _gone ->
        Ash.Changeset.add_error(changeset,
          field: :message_id,
          message: "That message is no longer here."
        )
    end
  end
end
