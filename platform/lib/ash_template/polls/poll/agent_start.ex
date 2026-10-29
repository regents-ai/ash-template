defmodule AshTemplate.Polls.Poll.AgentStart do
  @moduledoc """
  A poll an agent starts for its person, the same on every surface: `%{poll:
  Poll.present/1, replayed: boolean}`.

  The agent's `operation_id` is spent once (`AshTemplate.Agents.Operation`, for
  the `poll_start` capability), in the same transaction as the poll, and before
  it; it becomes the poll's id. A reuse with the same question, choices and
  minutes answers the poll it started (`replayed: true`) and starts nothing; a
  reuse with any of them changed, or of a UUID that is already another poll's
  id, is refused as `idempotency_conflict`. Of two calls with one key at once,
  the second waits on the first's row, finds it spent, and answers as a reuse.
  A start the poll refuses is `invalid_poll`, with the refused save; one its
  pairing no longer allows is `agent_not_paired`.
  """

  use Ash.Resource.Actions.Implementation

  alias AshTemplate.Actors.System
  alias AshTemplate.{Agents, Polls}
  alias AshTemplate.Agents.{NotPaired, Operation}
  alias AshTemplate.Polls.{Poll, Refused}

  @capability "poll_start"

  # An agent acting for its person, and one acting as the account it owns, both
  # spend their keys under the agent's own id (`agent_id`).
  @impl true
  def run(input, _opts, %{actor: actor}) do
    %{operation_id: key} = input.arguments
    poll = Map.take(input.arguments, [:question, :choices, :minutes])
    fingerprint = Operation.fingerprint(actor, [poll.question, poll.choices, poll.minutes])

    with :ok <- NotPaired.check(actor) do
      case spent(actor, key) do
        {:ok, nil} -> start(poll, key, fingerprint, actor)
        {:ok, operation} -> reuse(operation, fingerprint)
        {:error, error} -> {:error, error}
      end
    end
  end

  # The key is spent first, so a second call with it waits on this row and never
  # reaches the poll's own checks (the daily allowance).
  defp start(params, key, fingerprint, actor) do
    result =
      Ash.transact([Poll, Operation], fn ->
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
             {:ok, poll} <-
               Poll
               |> Ash.Changeset.for_create(:start, params, actor: actor)
               |> Ash.Changeset.force_change_attribute(:id, key)
               |> Ash.create() do
          poll
        end
      end)

    case result do
      {:ok, poll} -> {:ok, %{poll: Poll.present(poll), replayed: false}}
      {:error, error} -> answer_spent(error, actor, key, fingerprint)
    end
  end

  # The key was spent by a call that committed while this one waited. A key that
  # is already a poll's id, started with another key, is used for another poll:
  # which one, or whose, is not said.
  defp answer_spent(error, actor, key, fingerprint) do
    cond do
      Operation.key_spent?(error) ->
        with {:ok, operation} <- spent(actor, key), do: reuse(operation, fingerprint)

      refused?(error, :id) ->
        {:error, Refused.exception(code: "idempotency_conflict")}

      match?(%Ash.Error.Invalid{}, error) ->
        {:error, Refused.exception(code: "invalid_poll", error: error)}

      true ->
        NotPaired.ended({:error, error}, actor)
    end
  end

  defp refused?(%Ash.Error.Invalid{errors: errors}, field),
    do: Enum.any?(errors, &match?(%{field: ^field}, &1))

  defp refused?(_error, _field), do: false

  defp spent(actor, key),
    do: Agents.get_operation(actor.agent_id, @capability, key, actor: %System{})

  # A poll is never removed, so the key's poll is always there.
  defp reuse(%Operation{fingerprint: fingerprint} = operation, fingerprint) do
    with {:ok, poll} <- Polls.get_poll(operation.result_id),
         do: {:ok, %{poll: Poll.present(poll), replayed: true}}
  end

  defp reuse(_operation, _fingerprint),
    do: {:error, Refused.exception(code: "idempotency_conflict")}
end
