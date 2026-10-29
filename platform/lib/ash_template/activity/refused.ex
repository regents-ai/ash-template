defmodule AshTemplate.Activity.Refused do
  @moduledoc """
  A read of a person's activity refused, named by the refusal `code` every
  surface answers with: `invalid_cursor` when `after` is not the previous page's
  cursor, and `activity_too_large` when one page would pass 262,144 encoded
  bytes. Its words are `AshTemplateWeb.PairedAgentController`'s.
  """
  use Splode.Error, fields: [:code], class: :invalid

  def message(%{code: code}), do: "Refused: #{code}"
end
