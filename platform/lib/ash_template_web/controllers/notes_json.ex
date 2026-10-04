defmodule AshTemplateWeb.NotesJSON do
  @moduledoc "A note as the notes API and the browser tools return it."

  alias AshTemplate.Notes.Note

  @doc "The note's own fields."
  @spec note(Note.t()) :: map()
  def note(%Note{} = note), do: Map.take(note, [:id, :title, :body, :inserted_at, :updated_at])
end
