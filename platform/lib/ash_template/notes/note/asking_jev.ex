defmodule AshTemplate.Notes.Note.AskingJev do
  @moduledoc "Holds when the server can ask Jev for a note's label."

  use Ash.Resource.Validation

  alias AshTemplate.Notes.Labels

  @impl true
  def validate(_changeset, _opts, _context) do
    if Labels.asking?(), do: :ok, else: {:error, message: "Jev is not set up on this server"}
  end

  @impl true
  def atomic(changeset, opts, context), do: validate(changeset, opts, context)
end
