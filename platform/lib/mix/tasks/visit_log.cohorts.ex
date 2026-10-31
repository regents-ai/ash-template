defmodule Mix.Tasks.VisitLog.Cohorts do
  @shortdoc "Prints weekly sign-in cohorts, activation and D1/D7 return from exported visit lines"

  @moduledoc """
  Prints weekly sign-in cohorts by source, activation, D1 and D7 return and the
  median value steps of an activated account (`AshTemplateWeb.VisitLog.Cohorts`),
  from exported visit lines: a file of one JSON object a line, or standard input
  when no file, or `-`, is given. The site's own JSON lines, Fly's JSON log lines
  and the same fields at the top level (the shape Sentinel's export is expected to
  take) all read. It reads only the lines, never the database, and the window is
  only what the export holds: `fly logs` is a short buffer, and no 30-day export
  exists yet.

      mix visit_log.cohorts visit-lines.jsonl
      fly logs --app template-regents-sh --json --no-tail | mix visit_log.cohorts
  """

  use Mix.Task

  alias AshTemplateWeb.VisitLog.Cohorts

  @impl Mix.Task
  def run([path]) when path != "-", do: path |> File.stream!() |> print()
  def run(args) when args in [[], ["-"]], do: :stdio |> IO.stream(:line) |> print()
  def run(_args), do: Mix.raise("Usage: mix visit_log.cohorts [PATH]")

  defp print(lines), do: lines |> Cohorts.report() |> IO.puts()
end
