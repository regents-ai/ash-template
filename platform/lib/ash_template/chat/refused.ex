defmodule AshTemplate.Chat.Refused do
  @moduledoc """
  A chat action refused, named by the refusal `code` every surface answers with
  (`AshTemplateWeb.ChatController` holds its words): `chat_not_found`,
  `invalid_cursor`, `idempotency_conflict`, or `invalid_message` with the
  refused save as `error`.
  """
  use Splode.Error, fields: [:code, :error], class: :invalid

  def message(%{code: code}), do: "Refused: #{code}"
end
