defmodule AshTemplate.Messages.Message.AgentLeave do
  @moduledoc """
  An agent's message, the same on every surface: `%{receipt: Message.receipt/1,
  replayed: boolean}`.

  The agent's `operation_id` is spent once (`AshTemplate.Agents.Operation`, for
  the `message_leave` capability), in the same transaction as the message, and
  before it. A reuse with the same topic, text and reply_to answers the receipt
  of the message it left (`replayed: true`) and leaves nothing; a reuse with any
  other is refused as `idempotency_conflict`. Of two calls with one key at once,
  the second waits on the first's row, finds it spent, and answers as a reuse.
  The message's id is made here, so the row can name it before it is written.

  Every caller passes the client address as `context: %{client_key: key}`,
  which the message's allowances count (`AshTemplate.Limits.LimitWrites`).
  """

  use Ash.Resource.Actions.Implementation

  alias AshTemplate.Actors.{Agent, System}
  alias AshTemplate.Agents
  alias AshTemplate.Agents.Operation
  alias AshTemplate.Messages
  alias AshTemplate.Messages.{Message, Refused}

  @capability "message_leave"

  @impl true
  def run(input, _opts, %{actor: %Agent{} = actor}) do
    %{topic: topic, body: body, operation_id: key} = input.arguments
    reply_to = input.arguments[:reply_to]
    fingerprint = Operation.fingerprint([topic, body, reply_to || ""])

    case spent(actor, key) do
      {:ok, nil} -> leave(input.arguments, key, fingerprint, actor, input.context)
      {:ok, operation} -> reuse(operation, fingerprint)
      {:error, error} -> {:error, error}
    end
  end

  # The key is spent first, so a second call with it waits on this row and never
  # reaches the message's own write limits. Those are meant to run before a
  # transaction opens; here they run inside the key's, on purpose, so the
  # message's context says so.
  defp leave(arguments, key, fingerprint, actor, context) do
    id = Ash.UUID.generate()

    result =
      Ash.transact([Message, Operation], fn ->
        with {:ok, _operation} <-
               Agents.record_operation(
                 %{
                   principal: actor.agent_id,
                   capability: @capability,
                   operation_key: key,
                   fingerprint: fingerprint,
                   result_id: id
                 },
                 actor: %System{}
               ),
             {:ok, message} <-
               Message
               |> Ash.Changeset.for_create(
                 :leave,
                 Map.take(arguments, [:topic, :body, :reply_to]),
                 actor: actor,
                 context: %{
                   client_key: Map.fetch!(context, :client_key),
                   warn_on_transaction_hooks?: false
                 }
               )
               |> Ash.Changeset.force_change_attribute(:id, id)
               |> Ash.create() do
          message
        end
      end)

    case result do
      {:ok, message} -> {:ok, %{receipt: Message.receipt(message), replayed: false}}
      {:error, error} -> answer_spent(error, actor, key, fingerprint)
    end
  end

  # The key was spent by a call that committed while this one waited.
  defp answer_spent(error, actor, key, fingerprint) do
    with true <- key_spent?(error),
         {:ok, operation} <- spent(actor, key) do
      reuse(operation, fingerprint)
    else
      false -> {:error, error}
      {:error, error} -> {:error, error}
    end
  end

  defp key_spent?(%Ash.Error.Invalid{errors: errors}) do
    Enum.any?(
      errors,
      &match?(%Ash.Error.Changes.InvalidAttribute{field: :principal, private_vars: _}, &1)
    )
  end

  defp key_spent?(_error), do: false

  defp spent(actor, key),
    do: Agents.get_operation(actor.agent_id, @capability, key, actor: %System{})

  # Messages are never deleted, so a spent key always names one.
  defp reuse(%Operation{fingerprint: fingerprint} = operation, fingerprint) do
    with {:ok, %Message{} = message} <-
           Messages.get_message(operation.result_id, actor: %System{}) do
      {:ok, %{receipt: Message.receipt(message), replayed: true}}
    end
  end

  defp reuse(_operation, _fingerprint),
    do: {:error, Refused.exception(code: "idempotency_conflict")}
end
