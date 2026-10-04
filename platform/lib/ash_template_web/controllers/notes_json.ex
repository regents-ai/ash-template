defmodule AshTemplateWeb.NotesJSON do
  @moduledoc "A note as the notes API and the browser tools return it, with its latest label."

  alias AshTemplate.Notes.{Decision, Note}

  @doc "The note's fields and its `label`, or `label: nil` when none was asked for."
  @spec note(Note.t()) :: map()
  def note(%Note{} = note) do
    note
    |> Map.take([:id, :title, :body, :inserted_at, :updated_at])
    |> Map.put(:label, label(note.label_decision))
  end

  defp label(nil), do: nil

  defp label(%Decision{} = decision) do
    %{
      state: decision.state,
      choice: decision.choice,
      confidence: decision.confidence,
      rating: decision.report
    }
  end
end
