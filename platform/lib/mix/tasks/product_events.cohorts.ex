defmodule Mix.Tasks.ProductEvents.Cohorts do
  @shortdoc "Prints weekly account cohorts from the product events"

  @moduledoc """
  Prints weekly account cohorts from the local database's product events
  (`AshTemplate.ProductEvents.Cohorts`). It only reads, and starts only the
  database connection. On a deployment, run `/app/bin/product-cohorts`.

      mix product_events.cohorts
  """

  use Mix.Task

  @impl true
  def run(_args) do
    Mix.Task.run("app.config")

    {:ok, report, _started} =
      Ecto.Migrator.with_repo(AshTemplate.Repo, &AshTemplate.ProductEvents.Cohorts.report/1)

    Mix.shell().info(report)
  end
end
