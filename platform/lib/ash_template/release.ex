defmodule AshTemplate.Release do
  @moduledoc false

  @app :ash_template
  @platform_schema "regent_names"

  @table_exists """
  SELECT EXISTS (
    SELECT 1 FROM pg_catalog.pg_class AS c
    JOIN pg_catalog.pg_namespace AS n ON n.oid = c.relnamespace
    WHERE n.nspname = $1 AND c.relname = $2 AND c.relkind IN ('r', 'p')
  )
  """
  @schema_exists "SELECT EXISTS (SELECT 1 FROM pg_catalog.pg_namespace WHERE nspname = $1)"

  def migrate do
    with_release_repo(fn repo ->
      require_signed_access_schema!(repo)
      repo.migrate!(migrations_path())
    end)
  end

  @doc "Read-only release prerequisite; shared migrations require separate founder authority."
  def require_signed_access_schema!(repo) do
    :ok = RegentAgents.Migrator.require_pairing_history!(repo)
    RegentCredits.Migrator.require_pairing_grants!(repo)
  end

  @doc """
  Prepares an empty staging database for the first deployment: creates a
  staging-only copy of the tables this repository reads but does not own
  (`regent_names.platform_human_users`), in the local fixture's shape, runs
  every migration into `ash_template_app`, then creates the Regent Credits
  ledger, which Regents migrates in production. It refuses a database that already
  carries migration state or the regent_names schema and repairs nothing: recovery
  from a half-finished bootstrap is to destroy and recreate the staging database.
  """
  def bootstrap_staging do
    # Read before anything opens a connection, so no configuration mistake can
    # point this command at a database outside staging.
    if System.get_env("ASH_TEMPLATE_DEPLOYMENT_ROLE") != "staging",
      do: raise("bootstrap-staging requires ASH_TEMPLATE_DEPLOYMENT_ROLE to be exactly staging")

    with_release_repo(fn repo ->
      refuse_existing_state!(repo)
      # The fixture is the only definition of these tables' shape in the repository.
      AshTemplate.LocalDatabaseFixture.create_shared_tables!()
      repo.migrate!(migrations_path())
      RegentAgents.Migrator.up(repo)
      RegentCredits.Migrator.up(repo)
      RegentPoints.Migrator.up(repo)
      RegentIdentity.Migrator.up(repo)
    end)
  end

  @doc """
  Prints what a deployed database and the release disagree about: the migrations
  the release carries that the database has not applied (`pending:`), and the
  versions the database has applied whose file the release does not carry
  (`applied-without-file:`), or `none`. It applies nothing, creates nothing, and
  takes no migration lock.
  """
  def pending_migrations do
    {pending, applied_without_file} = with_release_repo(&disagreements/1)

    if pending == [] and applied_without_file == [], do: IO.puts("none")
    if pending != [], do: IO.puts("pending: #{Enum.join(pending, " ")}")

    if applied_without_file != [],
      do: IO.puts("applied-without-file: #{Enum.join(applied_without_file, " ")}")
  end

  defp disagreements(repo) do
    path = migrations_path()
    prefix = repo.default_prefix()

    unless table_exists?(repo, prefix, migration_source(repo)),
      do: raise("no schema_migrations table: run bootstrap-staging first")

    migrations =
      Ecto.Migrator.migrations(repo, [path],
        prefix: prefix,
        skip_table_creation: true,
        migration_lock: false
      )

    carried = carried_versions(path)

    {for({:down, version, _name} <- migrations, do: version),
     for({:up, version, _name} <- migrations, version not in carried, do: version)}
  end

  # Ecto names an applied version with no file after a placeholder marker. The
  # set of versions the release actually carries answers the same question
  # without depending on that marker's text.
  defp carried_versions(path) do
    for file <- Path.wildcard(Path.join(path, "*.exs")),
        {version, "_" <> _name} <- [file |> Path.basename() |> Integer.parse()],
        into: MapSet.new(),
        do: version
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
    %{rows: [[exists?]]} = Ecto.Adapters.SQL.query!(repo, @table_exists, [prefix, table])
    exists?
  end

  defp schema_exists?(repo, schema) do
    %{rows: [[exists?]]} = Ecto.Adapters.SQL.query!(repo, @schema_exists, [schema])
    exists?
  end

  defp migration_source(repo), do: repo.config()[:migration_source] || "schema_migrations"

  # Loads the app and starts only its database connection, on the release
  # login, for as long as `fun` runs; returns what `fun` returns.
  defp with_release_repo(fun) do
    :ok = Application.ensure_loaded(@app)
    Application.put_env(@app, AshTemplate.Repo, AshTemplate.DatabaseConfig.release_config!())
    {:ok, result, _started} = Ecto.Migrator.with_repo(AshTemplate.Repo, fun)
    result
  end

  defp migrations_path, do: Application.app_dir(@app, "priv/repo/migrations")
end
