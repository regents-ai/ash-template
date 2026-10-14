defmodule AshTemplate.Notes.Decision.RequestLabel do
  @moduledoc """
  Creates a pending label decision for a save, on the notes' `:note_saved`
  signal, in the save's transaction, so a save that rolls back asks nothing. It
  asks as the person or agent who saved. When the site has used today's
  questions the note still saves, with no label.
  """

  alias AshTemplate.Notes.Decision
  alias AshTemplate.Notes.Decision.UnderDailyBudget

  @doc "Asks for a label on the note `signal` names, as `context`'s actor; `:ok` or `{:error, error}`."
  def ask(%{note_id: note_id}, context) do
    :ok = UnderDailyBudget.lock()

    Decision
    |> Ash.Changeset.for_create(:ask, %{note_id: note_id}, Ash.Context.to_opts(context))
    |> Ash.create()
    |> case do
      {:ok, _decision} -> :ok
      {:error, %Ash.Error.Forbidden{}} -> :ok
      {:error, error} -> {:error, error}
    end
  end
end
