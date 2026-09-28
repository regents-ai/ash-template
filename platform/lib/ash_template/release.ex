defmodule AshTemplate.Release do
  @moduledoc false

  @app :ash_template
  @deployment_role_variable "ASH_TEMPLATE_DEPLOYMENT_ROLE"
  @staging_role "staging"
  @platform_schema "regent_names"
  @bootstrap_role_error "bootstrap-staging requires #{@deployment_role_variable} to be exactly staging"
  @missing_migration_table_error "no schema_migrations table: run bootstrap-staging first"

  def migration_config!(getenv \\ &System.get_env/1) do
    AshTemplate.DatabaseConfig.release_config!(getenv)
  end

  def migrate, do: with_release_repo(fn repo -> repo.migrate!(migrations_path()) end)

  @doc """
  Prepares an empty staging database for the first deployment.

  Staging owns a disposable database, so it has no copy of the tables this
  repository reads but does not own, `regent_names.platform_human_users`. This
  command creates a staging-only approximation of it with the local fixture's
  shape, then runs every migration into `ash_template_app`.

  It refuses any database that already carries migration state or the
  regent_names schema, and it repairs nothing: recovery from a half-finished
  bootstrap is to destroy and recreate the staging database.
  """
  def bootstrap_staging do
    # The role is read before anything opens a connection, so no configuration
    # mistake can point this command at a database outside staging.
    if System.get_env(@deployment_role_variable) != @staging_role do
      raise @bootstrap_role_error
    end

    with_release_repo(fn repo ->
      refuse_existing_state!(repo)

      # The fixture is the only definition of these tables' shape in the
      # repository. Calling it keeps staging identical to the local database
      # instead of copying it.
      AshTemplate.LocalDatabaseFixture.create_shared_tables!()

      repo.migrate!(migrations_path())
    end)
  end

  @doc """
  Lists what a deployed database and the release disagree about.

  Prints every migration the release carries that the database has not applied
  under `pending:`, and every version the database has applied whose file the
  release does not carry under `applied-without-file:`. Prints `none` when both
  are empty. It applies nothing, creates nothing, and takes no migration lock.
  """
  def pending_migrations do
    {pending, applied_without_file} = with_release_repo(&collect_disagreements/1)
    report(pending, applied_without_file)
  end

  defp collect_disagreements(repo) do
    path = migrations_path()
    migrations = migration_status(repo, path)
    carried = carried_versions(path)

    {for({:down, version, _name} <- migrations, do: version),
     for({:up, version, _name} <- migrations, not MapSet.member?(carried, version), do: version)}
  end

  defp migration_status(repo, path) do
    case read_migration_status(repo, path) do
      {:ok, migrations} -> migrations
      :no_migration_table -> raise @missing_migration_table_error
    end
  end

  defp read_migration_status(repo, path) do
    {:ok,
     Ecto.Migrator.migrations(repo, [path],
       prefix: repo.default_prefix(),
       skip_table_creation: true,
       migration_lock: false
     )}
  rescue
    error in Postgrex.Error ->
      if undefined_migration_table?(error, migration_source(repo)) do
        :no_migration_table
      else
        reraise error, __STACKTRACE__
      end
  end

  defp undefined_migration_table?(
         %Postgrex.Error{postgres: %{code: :undefined_table, message: message}},
         source
       ),
       do: String.contains?(message, source)

  defp undefined_migration_table?(_error, _source), do: false

  # Ecto names an applied version with no file after a placeholder marker. The
  # set of versions the release actually carries answers the same question
  # without depending on that marker's text.
  defp carried_versions(path) do
    path
    |> Path.join("*.exs")
    |> Path.wildcard()
    |> Enum.flat_map(fn file ->
      case file |> Path.basename() |> Integer.parse() do
        {version, "_" <> _name} -> [version]
        _unversioned -> []
      end
    end)
    |> MapSet.new()
  end

  defp report([], []), do: IO.puts("none")

  defp report(pending, applied_without_file) do
    if pending != [], do: IO.puts("pending: #{Enum.join(pending, " ")}")

    if applied_without_file != [] do
      IO.puts("applied-without-file: #{Enum.join(applied_without_file, " ")}")
    end
  end

  defp refuse_existing_state!(repo) do
    prefix = repo.default_prefix()
    source = migration_source(repo)

    if table_exists?(repo, prefix, source) do
      raise "#{prefix}.#{source} already exists: destroy and recreate the staging database"
    end

    if schema_exists?(repo, @platform_schema) do
      raise "#{@platform_schema} schema already exists: destroy and recreate the staging database"
    end
  end

  defp table_exists?(repo, prefix, table) do
    %{rows: [[exists?]]} =
      Ecto.Adapters.SQL.query!(
        repo,
        """
        SELECT EXISTS (
          SELECT 1
          FROM pg_catalog.pg_class AS c
          JOIN pg_catalog.pg_namespace AS n ON n.oid = c.relnamespace
          WHERE n.nspname = $1 AND c.relname = $2 AND c.relkind IN ('r', 'p')
        )
        """,
        [prefix, table]
      )

    exists?
  end

  defp schema_exists?(repo, schema) do
    %{rows: [[exists?]]} =
      Ecto.Adapters.SQL.query!(
        repo,
        "SELECT EXISTS (SELECT 1 FROM pg_catalog.pg_namespace WHERE nspname = $1)",
        [schema]
      )

    exists?
  end

  defp migration_source(repo), do: repo.config()[:migration_source] || "schema_migrations"

  # Loads the app and starts only its database connection, on the release
  # login, for as long as `fun` runs; returns what `fun` returns. Every release
  # command runs through it.
  defp with_release_repo(fun) do
    load_app()
    Application.put_env(@app, AshTemplate.Repo, migration_config!())

    {:ok, result, _started} = Ecto.Migrator.with_repo(AshTemplate.Repo, fun)
    result
  end

  defp load_app do
    case Application.load(@app) do
      :ok -> :ok
      {:error, {:already_loaded, @app}} -> :ok
    end
  end

  defp migrations_path do
    Application.app_dir(@app, "priv/repo/migrations")
  end
end
