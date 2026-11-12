defmodule AshTemplate.Rooms.Refused do
  @moduledoc """
  A rooms action refused its input, named by the refusal `code` every surface
  answers with (`AshTemplateWeb.RoomsController` holds its words): `room_not_found`,
  `invalid_cursor`, `idempotency_conflict`, `message_removed` with `id`, the
  message the operation key had posted, or `too_many_requests` with
  `retry_after`, the seconds left of the allowance a post was refused by.
  """
  use Splode.Error, fields: [:code, :id, :retry_after], class: :invalid

  def message(%{code: code}), do: "Refused: #{code}"
end
