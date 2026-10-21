defmodule AshTemplate.Dms.Message.SendInConversation do
  @moduledoc """
  Sends the message from the actor's person to the other side of
  `conversation_id`, a conversation they are in, marked with the paired agent
  that wrote it, if one did. Once it is saved, the conversation moves up, in
  the same transaction.
  """

  use Ash.Resource.Change

  alias AshTemplate.Actors.System
  alias AshTemplate.Dms
  alias AshTemplate.Dms.Conversation

  @impl true
  def change(changeset, _opts, %{actor: actor} = context) do
    me = Map.get(actor || %{}, :human_account_id)
    id = Ash.Changeset.get_argument(changeset, :conversation_id)

    case Dms.get_conversation(id, Ash.Context.to_opts(context)) do
      {:ok, %Conversation{person_a: a, person_b: b} = conversation} when me in [a, b] ->
        changeset
        |> Ash.Changeset.force_change_attributes(
          conversation_id: conversation.id,
          from_id: me,
          to_id: if(me == a, do: b, else: a),
          via_agent_id: acting_agent(actor)
        )
        |> Ash.Changeset.after_action(&touch(&1, &2, conversation))

      _gone ->
        Ash.Changeset.add_error(changeset,
          field: :conversation_id,
          message: "That conversation is no longer here."
        )
    end
  end

  defp acting_agent(%{role: :agent, agent_id: id}), do: id
  defp acting_agent(actor), do: Map.get(actor, :acting_agent_id)

  defp touch(_changeset, message, conversation) do
    with {:ok, _conversation} <-
           conversation
           |> Ash.Changeset.for_update(:touch, %{last_message_at: message.inserted_at},
             actor: %System{}
           )
           |> Ash.update(),
         do: {:ok, message}
  end
end
