defmodule AshTemplate.Health do
  @moduledoc """
  Whether the site's own database answers, for the health check alone, and
  whether every migration this release carries is applied.

  The health query never waits for a connection: it takes one that is free or
  is told at once that none is, so it neither queues behind the work it reports
  on nor runs past Fly's two-second deadline. A pool with every connection in
  use looks the same as a database that has stopped answering, and a machine
  marked down for a busy pool is restarted at the moment it is serving most. So
  each query that succeeds anywhere on the machine marks the database as
  answering (`attach/0`), and a connection failure within 30 seconds of the last
  answer, none free or one that broke, is a busy pool: the site is healthy. An
  error from the database itself, or a connection failure with no answer in
  that time, is a database that does not answer.
  """

  @answered_within_ms 30_000
  @answered_at {__MODULE__, :answered_at}

  @doc "Starts marking each query that succeeds, once, as the site starts."
  @spec attach() :: :ok
  def attach do
    answered_at = :atomics.new(1, signed: true)
    # The least value it holds: the database has not answered yet.
    :atomics.put(answered_at, 1, :atomics.info(answered_at).min)
    :persistent_term.put(@answered_at, answered_at)

    :telemetry.attach(
      __MODULE__,
      [:ash_template, :repo, :query],
      &__MODULE__.handle_event/4,
      answered_at
    )
  end

  @doc false
  def handle_event(_event, _measurements, %{result: {:ok, _result}}, answered_at),
    do: :atomics.put(answered_at, 1, System.monotonic_time(:millisecond))

  def handle_event(_event, _measurements, _metadata, _answered_at), do: :ok

  # A running server alone does not make the site ready: read one of the site's
  # own tables without returning rows. The timeout is below Fly's two-second
  # health deadline, and no error or connection detail leaves this module. The
  # schema is the repository's own configured name, never request input.
  # sobelow_skip ["SQL.Query"]
  def database_ready? do
    sql = "SELECT 1 FROM \"#{AshTemplate.Repo.default_prefix()}\".session_authorities LIMIT 0"

    case Ecto.Adapters.SQL.query(AshTemplate.Repo, sql, [],
           queue: false,
           timeout: 1_000,
           log: false
         ) do
      {:ok, _result} -> true
      {:error, %DBConnection.ConnectionError{}} -> answered_lately?()
      {:error, _database_error} -> false
    end
  catch
    :exit, _reason -> false
  end

  defp answered_lately? do
    answered_at = :atomics.get(:persistent_term.get(@answered_at), 1)
    System.monotonic_time(:millisecond) - answered_at <= @answered_within_ms
  end

  @doc """
  True when every migration file this release carries is recorded in the site's
  own schema. It only reads: no lock, and it never creates the ledger. A
  database that does not answer is `false`.
  """
  def migrations_applied? do
    AshTemplate.Repo
    |> Ecto.Migrator.migrations([Application.app_dir(:ash_template, "priv/repo/migrations")],
      prefix: AshTemplate.Repo.default_prefix(),
      skip_table_creation: true,
      migration_lock: false,
      timeout: 1_000,
      log: false
    )
    |> Enum.all?(&match?({:up, _version, _name}, &1))
  rescue
    _error -> false
  catch
    :exit, _reason -> false
  end
end
