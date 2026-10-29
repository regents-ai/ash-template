defmodule AshTemplate.Agents.Connection.Caller do
  @moduledoc """
  Holds for an app its person connected here, whether it calls as itself
  (`AshTemplate.Actors.ConnectedApp`) or, once its identity is paired, as that
  agent (`AshTemplate.Actors.Agent` with its `connection`).
  """

  use Ash.Policy.SimpleCheck

  alias AshTemplate.Actors.{Agent, ConnectedApp}

  @impl true
  def describe(_opts), do: "the actor is an app its person connected here"

  @impl true
  def match?(%ConnectedApp{}, _context, _opts), do: true
  def match?(%Agent{connection: %{}}, _context, _opts), do: true
  def match?(_actor, _context, _opts), do: false
end
