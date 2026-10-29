defmodule AshTemplate.Dms.Refused do
  @moduledoc """
  A direct-messages action refused, named by the refusal `code` every surface
  answers with (`AshTemplateWeb.DmsController` holds its words):
  `conversation_not_found`, `invalid_cursor`, `idempotency_conflict`, or
  `invalid_open` or `invalid_message` with the refused save as `error`.
  """
  use Splode.Error, fields: [:code, :error], class: :invalid

  def message(%{code: code}), do: "Refused: #{code}"
end
