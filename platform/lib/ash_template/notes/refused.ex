defmodule AshTemplate.Notes.Refused do
  @moduledoc """
  A notes action refused, named by the refusal `code` every surface answers with
  (`AshTemplateWeb.NotesController` holds its words): `note_not_found`,
  `invalid_note` with the refused save as `error`, `idempotency_conflict`,
  `note_removed` with `id`, the note the operation key had made,
  `label_not_found` or `invalid_label_report`.
  """
  use Splode.Error, fields: [:code, :id, :error], class: :invalid

  def message(%{code: code}), do: "Refused: #{code}"
end
