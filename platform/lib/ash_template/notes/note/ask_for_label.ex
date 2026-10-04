defmodule AshTemplate.Notes.Note.AskForLabel do
  @moduledoc """
  Creates a pending label decision for the save, in the save's transaction, so
  a save that rolls back asks nothing. When the site has used today's
  questions the note still saves, with no label.
  """

  use Ash.Resource.Change

  alias AshTemplate.Notes.Decision
  alias AshTemplate.Notes.Decision.UnderDailyBudget

  @impl true
  def change(changeset, _opts, context) do
    Ash.Changeset.after_action(changeset, fn _changeset, note ->
      :ok = UnderDailyBudget.lock()

      Decision
      |> Ash.Changeset.for_create(:ask, %{note_id: note.id}, Ash.Context.to_opts(context))
      |> Ash.create()
      |> case do
        {:ok, _decision} -> {:ok, note}
        {:error, %Ash.Error.Forbidden{}} -> {:ok, note}
        {:error, error} -> {:error, error}
      end
    end)
  end

  @impl true
  def atomic(changeset, opts, context), do: {:ok, change(changeset, opts, context)}
end
