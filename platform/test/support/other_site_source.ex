defmodule AshTemplate.Test.OtherSiteSource do
  @moduledoc """
  Another site's own record of an action, which this site cannot read: for a
  test that settles an event another site recorded, the action always stands.
  """

  def verify(_reference), do: {:ok, %{}}

  @doc "Runs `fun` with `rule_id` sourced from the other site, then puts this site's sources back."
  def settle(rule_id, fun) do
    adapters = Application.get_env(:regent_points, :adapters)
    Application.put_env(:regent_points, :adapters, Map.put(adapters, rule_id, __MODULE__))

    try do
      fun.()
    after
      Application.put_env(:regent_points, :adapters, adapters)
    end
  end
end
