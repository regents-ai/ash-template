defmodule AshTemplate.Chat.Message.AgentSend do
  @moduledoc """
  An agent's message to the assistant for its person, the same on every
  surface: `%{message: Message.present/1, replayed: boolean}`. With no
  `conversation_id` it starts a chat.

  The agent's `operation_id` is spent once (`AshTemplate.Agents.Operation`, for
  the `chat_send` capability), in the same transaction as the message, and
  before it; it becomes the message's id. A reuse with the same words and the
  same `conversation_id`, or none again, answers the message it sent
  (`replayed: true`) and sends nothing; a reuse with other words or another
  `conversation_id`, or of a UUID that is already another message's id, is
  refused as `idempotency_conflict`. Of two calls with one key at once, the
  second waits on the first's row, finds it spent, and answers as a reuse. A
  chat that is not the person's is `chat_not_found`; a send the message refuses
  is `invalid_message`, with the refused save; one its pairing no longer allows
  is `agent_not_paired`.
  """

  use Ash.Resource.Actions.Implementation

  alias AshTemplate.Actors.System
  alias AshTemplate.{Agents, Chat}
  alias AshTemplate.Agents.{NotPaired, Operation}
  alias AshTemplate.Chat.{Conversation, Message, Refused}

  @capability "chat_send"

  # An agent acting for its person, and one acting as the account it owns, both
  # spend their keys under the agent's own id (`agent_id`).
  @impl true
  def run(input, _opts, %{actor: actor}) do
    %{text: text, operation_id: key} = input.arguments
    id = input.arguments[:conversation_id]
    fingerprint = Operation.fingerprint([id, text])

    with :ok <- NotPaired.check(actor),
         {:ok, conversation_id} <- conversation(id, actor) do
      case spent(actor, key) do
        {:ok, nil} -> send_message(conversation_id, text, key, fingerprint, actor)
        {:ok, operation} -> reuse(operation, fingerprint, actor)
        {:error, error} -> {:error, error}
      end
    end
  end

  defp conversation(nil, _actor), do: {:ok, nil}

  defp conversation(id, actor) do
    with {:ok, conversation} <- Conversation.mine(id, actor), do: {:ok, conversation.id}
  end

  # The key is spent first, so a second call with it waits on this row and never
  # reaches the message's own checks (the allowance a minute).
  defp send_message(conversation_id, text, key, fingerprint, actor) do
    result =
      Ash.transact([Message, Operation], fn ->
        with {:ok, _operation} <-
               Agents.record_operation(
                 %{
                   principal: actor.agent_id,
                   capability: @capability,
                   operation_key: key,
                   fingerprint: fingerprint,
                   result_id: key
                 },
                 actor: %System{}
               ),
             {:ok, message} <-
               Message
               |> Ash.Changeset.for_create(:create, %{text: text},
                 actor: actor,
                 private_arguments: %{conversation_id: conversation_id}
               )
               |> Ash.Changeset.force_change_attribute(:id, key)
               |> Ash.create() do
          message
        end
      end)

    case result do
      {:ok, message} -> {:ok, %{message: Message.present(message), replayed: false}}
      {:error, error} -> answer_spent(error, actor, key, fingerprint)
    end
  end

  # The key was spent by a call that committed while this one waited. A key that
  # is already a message's id, sent with another key, is used for another
  # message: which one, or whose, is not said.
  defp answer_spent(error, actor, key, fingerprint) do
    cond do
      Operation.key_spent?(error) ->
        with {:ok, operation} <- spent(actor, key), do: reuse(operation, fingerprint, actor)

      refused?(error, :id) ->
        {:error, Refused.exception(code: "idempotency_conflict")}

      match?(%Ash.Error.Invalid{}, error) ->
        {:error, Refused.exception(code: "invalid_message", error: error)}

      true ->
        NotPaired.ended({:error, error}, actor)
    end
  end

  defp refused?(%Ash.Error.Invalid{errors: errors}, field),
    do: Enum.any?(errors, &match?(%{field: ^field}, &1))

  defp refused?(_error, _field), do: false

  defp spent(actor, key),
    do: Agents.get_operation(actor.agent_id, @capability, key, actor: %System{})

  # Chats and their messages are never deleted, and the key's message is in the
  # person's own chat.
  defp reuse(%Operation{fingerprint: fingerprint} = operation, fingerprint, actor) do
    with {:ok, message} <- Chat.get_message(operation.result_id, actor: actor),
         do: {:ok, %{message: Message.present(message), replayed: true}}
  end

  defp reuse(_operation, _fingerprint, _actor),
    do: {:error, Refused.exception(code: "idempotency_conflict")}
end
