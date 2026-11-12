defmodule AshTemplate.Messages.Refused do
  @moduledoc """
  Leaving a message refused its input, named by the refusal `code` every surface
  answers with (`AshTemplateWeb.MessagesController` holds its words):
  `idempotency_conflict`, or `too_many_requests` with `retry_after`, the seconds
  left of the allowance a message was refused by.
  """
  use Splode.Error, fields: [:code, :retry_after], class: :invalid

  def message(%{code: code}), do: "Refused: #{code}"
end
