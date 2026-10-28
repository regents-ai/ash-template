defmodule AshTemplate.Rooms.Message.AgentPost do
  @moduledoc """
  An agent's post, the same on every surface: `%{message: Message.present/1,
  replayed: boolean}`.

  The agent's `operation_id` is spent once (`AshTemplate.Agents.Operation`, for
  the `room_post` capability), in the same transaction as the post, and before it. A reuse
  with the same room and text answers the message it posted (`replayed: true`)
  and posts nothing; a reuse with any other room or text is refused as
  `idempotency_conflict`; a reuse after that message was deleted is refused as
  `message_removed`, naming it. Of two calls with one key at once, the second
  waits on the first's row, finds it spent, and answers as a reuse. The
  message's id is made here, so the row can name it before the post is written.

  The key's fingerprint is taken from the text as the message stores it, so a
  retry with the text the first answer gave back replays it.

  Every caller passes the client address as `context: %{client_key: key}`,
  which the post's allowances count (`AshTemplate.Rooms.Message.SetAuthor`).
  """

  use Ash.Resource.Actions.Implementation

  alias AshTemplate.Actors.{Agent, System}
  alias AshTemplate.Agents
  alias AshTemplate.Agents.Operation
  alias AshTemplate.Rooms
  alias AshTemplate.Rooms.{Message, Refused, Room}
  alias AshTemplate.Rooms.Message.SquashBlankLines

  @capability "room_post"

  @impl true
  def run(input, _opts, %{actor: %Agent{} = actor}) do
    %{room: slug, body: body, operation_id: key} = input.arguments
    fingerprint = Operation.fingerprint([slug, SquashBlankLines.squash(body)])

    case spent(actor, key) do
      {:ok, nil} -> post(slug, body, key, fingerprint, actor, input.context)
      {:ok, operation} -> reuse(operation, slug, fingerprint)
      {:error, error} -> {:error, error}
    end
  end

  # The key is spent first, so a second call with it waits on this row and never
  # reaches the post's own checks (the allowance before pairing, the write limits).
  defp post(slug, body, key, fingerprint, actor, context) do
    id = Ash.UUID.generate()

    result =
      Ash.transact([Message, Operation], fn ->
        with {:ok, %Room{} = room} <- Rooms.get_room(slug),
             {:ok, _operation} <-
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
               |> Ash.Changeset.for_create(:post, %{room: room.slug, body: body},
                 actor: actor,
                 context: %{client_key: Map.fetch!(context, :client_key)}
               )
               |> Ash.Changeset.force_change_attribute(:id, id)
               |> Ash.create() do
          message
        else
          {:ok, nil} -> {:error, Refused.exception(code: "room_not_found")}
          {:error, error} -> {:error, error}
        end
      end)

    case result do
      {:ok, message} -> {:ok, %{message: Message.present(message), replayed: false}}
      {:error, error} -> answer_spent(error, actor, key, slug, fingerprint)
    end
  end

  # The key was spent by a call that committed while this one waited.
  defp answer_spent(error, actor, key, slug, fingerprint) do
    with true <- key_spent?(error),
         {:ok, operation} <- spent(actor, key) do
      reuse(operation, slug, fingerprint)
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

  defp reuse(%Operation{fingerprint: fingerprint} = operation, slug, fingerprint) do
    case Rooms.get_room_message(slug, operation.result_id) do
      {:ok, %Message{} = message} -> {:ok, %{message: Message.present(message), replayed: true}}
      {:ok, nil} -> {:error, Refused.exception(code: "message_removed", id: operation.result_id)}
      {:error, error} -> {:error, error}
    end
  end

  defp reuse(_operation, _slug, _fingerprint),
    do: {:error, Refused.exception(code: "idempotency_conflict")}
end
