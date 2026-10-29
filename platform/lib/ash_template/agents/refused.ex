defmodule AshTemplate.Agents.Refused do
  @moduledoc """
  An agent profile action refused, named by the refusal `code` every surface
  answers with: `agent_not_found` when no agent has that id, and
  `invalid_profile` when an agent's change to its own profile names neither a
  name nor a status, or with the refused save as `error`. Its words are
  `AshTemplateWeb.AgentsController`'s.
  """
  use Splode.Error, fields: [:code, :error], class: :invalid

  def message(%{code: code}), do: "Refused: #{code}"
end
