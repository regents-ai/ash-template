defmodule AshTemplate.Agents.Refused do
  @moduledoc """
  A read of an agent's profile refused, named by the refusal `code` every surface
  answers with: `agent_not_found` when no agent has that id. Its words are
  `AshTemplateWeb.AgentsController`'s.
  """
  use Splode.Error, fields: [:code], class: :invalid

  def message(%{code: code}), do: "Refused: #{code}"
end
