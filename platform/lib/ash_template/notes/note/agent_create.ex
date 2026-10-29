defmodule AshTemplate.Notes.Note.AgentCreate do
  @moduledoc """
  An agent's new note for its person, the same on every surface: `%{note:
  Note.present/1, replayed: boolean}`.

  The agent's `operation_id` is spent once (`AshTemplate.Agents.Operation`, for
  the `note_create` capability), in the same transaction as the note, and before
  it; it becomes the note's id. A reuse with the same title and text answers the
  note it made (`replayed: true`) and saves nothing; a reuse with any other title
  or text, or of a UUID that is already another note's id, is refused as
  `idempotency_conflict`; a reuse after that note was deleted is refused as
  `note_removed`, naming it. Of two calls with one key at
  once, the second waits on the first's row, finds it spent, and answers as a
  reuse. A save the note refuses is `invalid_note`, with the refused save; one
  its pairing no longer allows is `agent_not_paired`.
  """

  use Ash.Resource.Actions.Implementation

  alias AshTemplate.Actors.System
  alias AshTemplate.{Agents, Notes}
  alias AshTemplate.Agents.{NotPaired, Operation}
  alias AshTemplate.Notes.{Note, Refused}

  @capability "note_create"

  # An agent acting for its person, and one acting as the account it owns, both
  # spend their keys under the agent's own id (`agent_id`).
  @impl true
  def run(input, _opts, %{actor: actor}) do
    %{title: title, operation_id: key} = input.arguments
    body = input.arguments[:body]
    fingerprint = Operation.fingerprint(actor, [title, body])

    with :ok <- NotPaired.check(actor) do
      case spent(actor, key) do
        {:ok, nil} -> create(title, body, key, fingerprint, actor)
        {:ok, operation} -> reuse(operation, fingerprint, actor)
        {:error, error} -> {:error, error}
      end
    end
  end

  # The key is spent first, so a second call with it waits on this row and never
  # reaches the note's own checks (the write limits).
  defp create(title, body, key, fingerprint, actor) do
    result =
      Ash.transact([Note, Operation], fn ->
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
             {:ok, note} <-
               Note
               |> Ash.Changeset.for_create(:create, %{title: title, body: body}, actor: actor)
               |> Ash.Changeset.force_change_attribute(:id, key)
               |> Ash.create(load: [:label_decision, :changed_by_agent]) do
          note
        end
      end)

    case result do
      {:ok, note} -> {:ok, %{note: Note.present(note), replayed: false}}
      {:error, error} -> answer_spent(error, actor, key, fingerprint)
    end
  end

  # The key was spent by a call that committed while this one waited. A key that
  # is already a note's id, made by another key, is used for another note: which
  # note, or whose, is not said.
  defp answer_spent(error, actor, key, fingerprint) do
    cond do
      Operation.key_spent?(error) ->
        with {:ok, operation} <- spent(actor, key), do: reuse(operation, fingerprint, actor)

      id_taken?(error) ->
        {:error, Refused.exception(code: "idempotency_conflict")}

      match?(%Ash.Error.Invalid{}, error) ->
        {:error, Refused.exception(code: "invalid_note", error: error)}

      true ->
        NotPaired.ended({:error, error}, actor)
    end
  end

  defp id_taken?(%Ash.Error.Invalid{errors: errors}),
    do: Enum.any?(errors, &match?(%{field: :id}, &1))

  defp id_taken?(_error), do: false

  defp spent(actor, key),
    do: Agents.get_operation(actor.agent_id, @capability, key, actor: %System{})

  defp reuse(%Operation{fingerprint: fingerprint} = operation, fingerprint, actor) do
    case Notes.get_my_note(operation.result_id, actor: actor) do
      {:ok, %Note{} = note} -> {:ok, %{note: Note.present(note), replayed: true}}
      {:ok, nil} -> {:error, Refused.exception(code: "note_removed", id: operation.result_id)}
      {:error, error} -> {:error, error}
    end
  end

  defp reuse(_operation, _fingerprint, _actor),
    do: {:error, Refused.exception(code: "idempotency_conflict")}
end
