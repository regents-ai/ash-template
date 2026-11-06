defmodule AshTemplate do
  @moduledoc "The domains and business logic behind Ash Template."

  @site Application.compile_env!(:ash_template, :site)

  @doc """
  The name this site goes by in the shared Regent libraries: the app a Points
  event or a payment comes from.
  """
  def site, do: @site
end
