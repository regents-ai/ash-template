defmodule AshTemplate.RealCommits do
  @moduledoc """
  Rows a test really commits. Every test runs in a transaction that rolls back; a
  race that needs separate connections that really commit calls `start/0`, which
  turns that off for the test and empties the database when the test ends.
  `test_helper.exs` empties it before every run as well, so rows an earlier run
  left, a stopped one included, never reach a test.

  Emptying keeps only the rows migrations put there: every `schema_migrations`,
  the rooms a site opens with (`rooms_people_start`), the sign-in scopes
  (`RegentOAuth.Migration`), ErrorTracker's version (`ErrorTracker.Migration`) and
  when Points coverage starts (Points' `period_end_snapshot`). A migration that
  fills another table adds it to `@kept`.

  It runs only through the sandbox pool, which only the test configuration sets
  (`AshTemplate.DatabaseConfig`), naming the local `ash_template*_test` database
  alone. The sandbox mode is global, and emptying a table waits for every open
  transaction that used it, so only a test that runs alone (`async: false`) calls
  `start/0`.
  """

  import ExUnit.Callbacks, only: [on_exit: 1]

  alias AshTemplate.Repo
  alias Ecto.Adapters.SQL.Sandbox

  @kept ~w(schema_migrations rooms oauth_scopes error_tracker_meta wallet_coverage)

  def start do
    Sandbox.mode(Repo, :auto)

    on_exit(fn ->
      empty!()
      Sandbox.mode(Repo, :manual)
    end)
  end

  # Emptied together, which also takes the rows Points keeps final. Postgres
  # refuses to truncate a table that a kept table refers to (a room names the
  # account that opened it), so those rows are deleted instead.
  def empty! do
    Sandbox.unboxed_run(Repo, fn ->
      tables =
        column!(
          """
          select c.oid::regclass::text from pg_class c join pg_namespace n on n.oid = c.relnamespace
          where c.relkind = 'r' and n.nspname <> 'information_schema' and n.nspname not like 'pg\\_%'
            and not c.relname::text = any($1)
          """,
          [@kept]
        )

      referred =
        column!(
          """
          select distinct confrelid::regclass::text from pg_constraint
          where contype = 'f' and confrelid::regclass::text = any($1)
            and not conrelid::regclass::text = any($1)
          """,
          [tables]
        )

      Repo.query!("truncate " <> Enum.join(tables -- referred, ", "))
      for table <- referred, do: Repo.query!("delete from #{table}")
    end)
  end

  defp column!(sql, params), do: sql |> Repo.query!(params) |> Map.fetch!(:rows) |> List.flatten()
end
