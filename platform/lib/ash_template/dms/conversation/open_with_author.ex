defmodule AshTemplate.Dms.Conversation.OpenWithAuthor do
  @moduledoc """
  Opens the conversation between the actor's person and the person who wrote
  the room message named by `message_id`. A message an agent wrote as itself
  has no person to write to, and nobody writes to themselves.
  """

  use Ash.Resource.Change

  alias AshTemplate.Rooms
  alias AshTemplate.Rooms.Message

  @impl true
  def change(changeset, _opts, %{actor: actor} = context) do
    me = Map.get(actor || %{}, :human_account_id)
    message_id = Ash.Changeset.get_argument(changeset, :message_id)

    case Rooms.get_message(message_id, Ash.Context.to_opts(context)) do
      {:ok, %Message{human_account_id: nil}} ->
        refuse(changeset, "An agent with no person wrote this, so there’s nobody to message.")

      {:ok, %Message{human_account_id: ^me}} ->
        refuse(changeset, "That’s your own message.")

      {:ok, %Message{human_account_id: author}} ->
        Ash.Changeset.force_change_attributes(changeset,
          person_a: Kernel.min(me, author),
          person_b: Kernel.max(me, author),
          opened_by_id: me
        )

      _gone ->
        refuse(changeset, "That message is no longer here.")
    end
  end

  defp refuse(changeset, message),
    do: Ash.Changeset.add_error(changeset, field: :message_id, message: message)
end
