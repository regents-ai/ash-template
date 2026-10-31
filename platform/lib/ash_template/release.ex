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

  # Every shared library with its own schema and ledger, in the order their
  # changes apply: Credits' pairing grants build on Agents' pairing history.
  @shared [
    {:regent_identity, "regent_identity", RegentIdentity.Migrator},
    {:regent_agents, "regent_agents", RegentAgents.Migrator},
    {:regent_credits, "regent_credits", RegentCredits.Migrator},
    {:regent_points, "regent_points", RegentPoints.Migrator},
    {:regent_payments, "regent_payments", RegentPayments.Migrator}
  ]

  def migrate do
    with_release_repo(fn repo ->
      require_signed_access_schema!(repo)
      repo.migrate!(migrations_path())
    end)
  end

  @doc """
  Applies the shared database changes this release's pinned libraries carry
  that the database has not applied, and prints each one, or `none`. Run as
  `/app/bin/migrate-shared`.

  Every site carries this same command. A deployment never runs it: `migrate/0`
  refuses while a shared change is missing and applies none. Each change needs
  the founder's own named go; the site whose release first carries it runs this
  from the new image before that deployment, because only that image carries
  the change's file. Each library's ledger takes a migration lock, so two sites
  running it at once apply each change once.
  """
  def migrate_shared do
    applied =
      with_release_repo(fn repo ->
        unapplied = unapplied_shared_migrations(repo)
        if unapplied != [], do: apply_shared(repo)
        unapplied
      end)

    case applied do
      [] -> IO.puts("none")
      applied -> IO.puts("applied: #{Enum.join(applied, ", ")}")
    end
  end

  @doc "Read-only release prerequisite; shared migrations require separate founder authority."
  def require_signed_access_schema!(repo) do
    :ok = require_shared_migrations!(repo)
    :ok = RegentAgents.Migrator.require_pairing_history!(repo)
    RegentCredits.Migrator.require_pairing_grants!(repo)
  end

  # The shared code this release carries reads tables and columns from every
  # migration its pinned library ships, so each must already be in that schema's
  # own ledger. Every missing version is named at once.
  defp require_shared_migrations!(repo) do
    case unapplied_shared_migrations(repo) do
      [] ->
        :ok

      unapplied ->
        raise "These separately approved shared migrations must be applied before deployment: " <>
                Enum.join(unapplied, ", ")
    end
  end

  defp unapplied_shared_migrations(repo) do
    for {app, schema, _migrator} <- carried_shared(),
        {:down, version, _name} <-
          Ecto.Migrator.migrations(repo, [Application.app_dir(app, "priv/repo/migrations")],
            prefix: schema,
            skip_table_creation: true,
            migration_lock: false
          ),
        do: "#{schema} #{version}"
  end

  @doc """
  Prepares an empty staging database for the first deployment: creates a
  staging-only copy of the tables this repository reads but does not own
  (`regent_names.platform_human_users`), in the local fixture's shape, applies
  every shared change this release carries, as `migrate_shared/0` does in
  production, then runs every migration into `ash_template_app`. It refuses a database that already
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
      apply_shared(repo)
      repo.migrate!(migrations_path())
    end)
  end

  @doc """
  Prints what a deployed database and the release disagree about: the migrations
  the release carries that the database has not applied (`pending:`), the
  versions the database has applied whose file the release does not carry
  (`applied-without-file:`), and the shared changes the release carries that
  their own ledgers do not hold (`shared-pending:`, each as schema and version;
  a deployment is refused while one is listed, and `migrate_shared/0` applies
  them), or `none`.
  It applies nothing, creates nothing, and takes no migration lock.
  """
  def pending_migrations do
    {pending, applied_without_file, shared} =
      with_release_repo(fn repo ->
        {pending, applied_without_file} = disagreements(repo)
        {pending, applied_without_file, unapplied_shared_migrations(repo)}
      end)

    if pending == [] and applied_without_file == [] and shared == [], do: IO.puts("none")
    if pending != [], do: IO.puts("pending: #{Enum.join(pending, " ")}")

    if applied_without_file != [],
      do: IO.puts("applied-without-file: #{Enum.join(applied_without_file, " ")}")

    if shared != [], do: IO.puts("shared-pending: #{Enum.join(shared, ", ")}")
  end

  @doc """
  Prints the `count` statements on this site's schema that took the most
  database time (`AshTemplate.TopQueries`), `count` being a whole number from 1
  to 100 as text. Run as `/app/bin/top-queries [count]`. It only reads, and
  never creates `pg_stat_statements`.
  """
  def top_queries(count) do
    limit = AshTemplate.TopQueries.limit!(count)
    IO.puts(with_serving_repo(&AshTemplate.TopQueries.report(&1, limit)))
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

  defp apply_shared(repo), do: Enum.each(carried_shared(), fn {_, _, m} -> m.up(repo) end)

  # A shared library this site does not carry has no tables it reads or changes.
  defp carried_shared do
    carried = Application.spec(@app, :applications)
    for {app, _schema, _migrator} = shared <- @shared, app in carried, do: shared
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

  # A read-only report connects as the running site does, on the serving login with
  # its statement, lock and idle limits, so a slow report gives up before it holds
  # up the shared database, and sees the site's own statements.
  defp with_serving_repo(fun) do
    :ok = Application.ensure_loaded(@app)
    Application.put_env(@app, AshTemplate.Repo, AshTemplate.DatabaseConfig.runtime_config!(:prod))
    {:ok, result, _started} = Ecto.Migrator.with_repo(AshTemplate.Repo, fun)
    result
  end

  defp migrations_path, do: Application.app_dir(@app, "priv/repo/migrations")
end
