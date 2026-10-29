defmodule AshTemplate.Rooms.Refused do
  @moduledoc """
  A rooms action refused, named by the refusal `code` every surface answers with
  (`AshTemplateWeb.RoomsController` holds its words): `room_not_found`,
  `room_name_taken`, `not_room_maker`, `public_message_not_found`,
  `message_not_found`, `mute_not_found`, `invalid_cursor`,
  `idempotency_conflict`, `message_removed` with `id`, the message the operation
  key had posted, or `invalid_room`, `invalid_message`, `invalid_report` or
  `invalid_mute` with the refused save as `error`.
  """
  use Splode.Error, fields: [:code, :id, :error], class: :invalid

  def message(%{code: code}), do: "Refused: #{code}"
end
