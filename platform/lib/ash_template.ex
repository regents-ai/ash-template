defmodule AshTemplate do
  @moduledoc "The domains and business logic behind Ash Template."

  @site Application.compile_env!(:ash_template, :site)

  @doc """
  The name this site goes by in the shared Regent libraries: the site Credits
  holds are placed under, and the app a Points event comes from.
  """
  def site, do: @site
end
