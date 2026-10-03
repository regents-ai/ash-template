defmodule AshTemplate.Notes.Note.RecordWebhook do
  @moduledoc """
  Records how its job's save went, as `state`, unless the note was saved again
  since: a newer save has its own job, and that job records its own outcome.

  The note's `updated_at` stays the time it was last saved.
  """

  use Ash.Resource.Change

  alias AshTemplate.Notes.Note

  @impl true
  def change(changeset, opts, _context) do
    revision = Note.job_revision(changeset)
    state = Keyword.fetch!(opts, :state)

    changeset
    |> Ash.Changeset.atomic_update(
      :webhook_state,
      expr(if revision == ^revision, do: ^state, else: webhook_state)
    )
    |> Ash.Changeset.atomic_update(:updated_at, expr(updated_at))
  end

  @impl true
  def atomic(changeset, opts, context), do: {:ok, change(changeset, opts, context)}
end
