defmodule AshTemplate.Rooms.Refused do
  @moduledoc """
  A rooms action refused its input, named by the refusal `code` every surface
  answers with (`AshTemplateWeb.RoomsController` holds its words): `room_not_found`,
  `invalid_cursor`, `idempotency_conflict`, or `message_removed` with `id`, the
  message the operation key had posted.
  """
  use Splode.Error, fields: [:code, :id], class: :invalid

  def message(%{code: code}), do: "Refused: #{code}"
end
