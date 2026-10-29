defmodule AshTemplate.Polls.Refused do
  @moduledoc """
  A polls action refused, named by the refusal `code` every surface answers with
  (`AshTemplateWeb.PollsController` holds its words): `poll_not_found`,
  `not_poll_starter`, `poll_closed`, `idempotency_conflict`, or `invalid_poll` or
  `invalid_vote` with the refused save as `error`.
  """
  use Splode.Error, fields: [:code, :error], class: :invalid

  def message(%{code: code}), do: "Refused: #{code}"
end
