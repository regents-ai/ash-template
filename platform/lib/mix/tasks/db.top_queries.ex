defmodule Mix.Tasks.Db.TopQueries do
  @shortdoc "Prints the statements on this site's schema that took the most database time"

  @moduledoc """
  Prints the statements on this site's own schema that took the most time in all,
  from `pg_stat_statements` (`AshTemplate.TopQueries`), 20 unless a count from 1
  to 100 is given. It only reads, and starts only the database connection. On a
  deployment, run `/app/bin/top-queries [count]`.

      mix db.top_queries
      mix db.top_queries 50
  """

  use Mix.Task

  @impl true
  def run(args) do
    limit = AshTemplate.TopQueries.limit!(List.first(args, "20"))
    Mix.Task.run("app.config")

    {:ok, report, _started} =
      Ecto.Migrator.with_repo(AshTemplate.Repo, &AshTemplate.TopQueries.report(&1, limit))

    Mix.shell().info(report)
  end
end
