defmodule AshTemplate.Accounts.Refused do
  @moduledoc """
  A read of a person's Credits or Points refused, named by the refusal `code`
  every surface answers with: `invalid_cursor` when `after` is not the previous
  page's cursor. Its words are `AshTemplateWeb.PairedAgentController`'s.
  """
  use Splode.Error, fields: [:code], class: :invalid

  def message(%{code: code}), do: "Refused: #{code}"
end
