defmodule AshTemplate.Agents.Connection.Refused do
  @moduledoc """
  A connected app's identity request could not be completed: the account's
  pairing, its code or the hosted identity said no. The words are
  `RegentMCPAgents`'s, the same for every reason, so a refusal tells the app
  nothing about another account.
  """
  use Splode.Error, fields: [], class: :forbidden

  def message(_error), do: "The identity request could not be completed."
end
