defmodule AshTemplate.RealCommits do
  @moduledoc """
  For a test whose race needs separate connections that really commit. `start/0`
  turns the sandbox off for the test and notes every table that holds no rows;
  when the test ends it empties those tables again and turns the sandbox back on.
  Every run reuses the test database, so a run that left its rows behind would
  slow every later run that reads them all.

  The sandbox mode is global, and emptying a table waits for every open
  transaction that used it, so only a test that runs alone (`async: false`)
  calls it.
  """

  import ExUnit.Callbacks, only: [on_exit: 1]

  alias AshTemplate.Repo
  alias Ecto.Adapters.SQL.Sandbox

  def start do
    Sandbox.mode(Repo, :auto)
    empty = Enum.reject(tables(), &rows?/1)

    on_exit(fn ->
      empty!(empty)
      Sandbox.mode(Repo, :manual)
    end)
  end

  defp tables do
    """
    select c.oid::regclass::text from pg_class c join pg_namespace n on n.oid = c.relnamespace
    where c.relkind = 'r' and n.nspname <> 'information_schema' and n.nspname not like 'pg\\_%'
    """
    |> Repo.query!()
    |> Map.fetch!(:rows)
    |> List.flatten()
  end

  defp rows?(table), do: Repo.query!("select exists (select from #{table})").rows == [[true]]

  # Emptied together, which also takes the rows Points keeps final. Postgres
  # refuses to truncate a table that a kept table refers to (a room names the
  # account that opened it), so those rows are deleted instead.
  defp empty!(tables) do
    referred =
      """
      select distinct confrelid::regclass::text from pg_constraint
      where contype = 'f' and confrelid::regclass::text = any($1)
        and not conrelid::regclass::text = any($1)
      """
      |> Repo.query!([tables])
      |> Map.fetch!(:rows)
      |> List.flatten()

    Repo.query!("truncate " <> Enum.join(tables -- referred, ", "))
    for table <- referred, do: Repo.query!("delete from #{table}")
  end
end
