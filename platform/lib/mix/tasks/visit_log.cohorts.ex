defmodule Mix.Tasks.VisitLog.Cohorts do
  @shortdoc "Prints weekly sign-in cohorts, activation and D1/D7 return from Sentinel's day exports"

  @moduledoc """
  Prints weekly sign-in cohorts by source, activation, D1 and D7 return and the
  median value steps of an activated account (`AshTemplateWeb.VisitLog.Cohorts`),
  from Sentinel's day export of the site's visit lines (`GET
  /api/ops/logs/:app/day`, Sentinel's README): a file of its rows, one JSON object
  a line, or standard input when no file, or `-`, is given. It reads only the
  rows, never the database. An export holds the last 24 hours, so D1 needs two
  saved a day apart and D7 eight, joined into one input; a row in two
  overlapping exports counts once.

      mix visit_log.cohorts day-export.ndjson
      cat day-exports/*.ndjson | mix visit_log.cohorts
  """

  use Mix.Task

  alias AshTemplateWeb.VisitLog.Cohorts

  @impl Mix.Task
  def run([path]) when path != "-", do: path |> File.stream!() |> print()
  def run(args) when args in [[], ["-"]], do: :stdio |> IO.stream(:line) |> print()
  def run(_args), do: Mix.raise("Usage: mix visit_log.cohorts [PATH]")

  defp print(lines), do: lines |> Cohorts.report() |> IO.puts()
end
