defmodule AshTemplate.ProtectPointsTest do
  # Invariant: `/app/bin/protect-points` puts every table of the shared Points
  # ledger but its migration ledger on the protected list, none allowing row
  # deletes, all in one go; when one of them is already listed it changes
  # nothing. The list is a stand-in for the shared database's, made inside the
  # test's own transaction, which always rolls back.
  # Not async: listing a table waits for every write in progress on it.
  use ExUnit.Case, async: false

  alias AshTemplate.{Release, Repo}

  @guard [
    "CREATE SCHEMA regent_guard",
    """
    CREATE TABLE regent_guard.protected_tables (
      relid oid PRIMARY KEY,
      name text NOT NULL,
      rows_deletable boolean NOT NULL
    )
    """,
    """
    CREATE FUNCTION regent_guard.refuse_rows() RETURNS trigger
    LANGUAGE plpgsql AS $$
    BEGIN
      RAISE EXCEPTION '% on %.% refused', TG_OP, TG_TABLE_SCHEMA, TG_TABLE_NAME;
    END $$
    """,
    """
    CREATE FUNCTION regent_guard.protect(qualified text, deletable boolean) RETURNS void
    LANGUAGE plpgsql AS $$
    DECLARE rel regclass := to_regclass(qualified);
    BEGIN
      IF rel IS NULL THEN
        RAISE EXCEPTION 'no table %', qualified;
      END IF;
      INSERT INTO regent_guard.protected_tables VALUES (rel, qualified, deletable);
      EXECUTE format('CREATE TRIGGER regent_guard_truncate BEFORE TRUNCATE ON %s
                      FOR EACH STATEMENT EXECUTE FUNCTION regent_guard.refuse_rows()', rel);
      EXECUTE format('CREATE VIEW regent_guard.%I AS SELECT FROM %s',
                     'keep_' || replace(qualified, '.', '__'), rel);
      IF NOT deletable THEN
        EXECUTE format('CREATE TRIGGER regent_guard_delete BEFORE DELETE ON %s
                        FOR EACH STATEMENT EXECUTE FUNCTION regent_guard.refuse_rows()', rel);
      END IF;
    END $$
    """
  ]

  @points_tables """
  SELECT n.nspname || '.' || c.relname FROM pg_catalog.pg_class AS c
  JOIN pg_catalog.pg_namespace AS n ON n.oid = c.relnamespace
  WHERE n.nspname = 'regent_points' AND c.relkind IN ('r', 'p')
    AND c.relname <> 'schema_migrations'
  ORDER BY 1
  """

  @listed "SELECT name, rows_deletable FROM regent_guard.protected_tables ORDER BY name"

  setup do
    owner = Ecto.Adapters.SQL.Sandbox.start_owner!(Repo)
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(owner) end)
    Enum.each(@guard, &Repo.query!/1)
    :ok
  end

  test "every Points table but the migration ledger is listed, none allowing row deletes" do
    tables = List.flatten(Repo.query!(@points_tables).rows)
    assert length(tables) == 9

    expected = for table <- tables, do: [table, false]
    assert Release.protect_points(Repo) == expected
    assert Repo.query!(@listed).rows == expected

    for table <- tables do
      assert {:error, %Postgrex.Error{postgres: %{code: :raise_exception}}} =
               Repo.query("DELETE FROM #{table}", [], mode: :savepoint)

      assert {:error, %Postgrex.Error{postgres: %{code: :raise_exception}}} =
               Repo.query("TRUNCATE #{table} CASCADE", [], mode: :savepoint)

      assert {:error, %Postgrex.Error{postgres: %{code: :dependent_objects_still_exist}}} =
               Repo.query("DROP TABLE #{table}", [], mode: :savepoint)
    end

    # A listed table still takes new columns, and the migration ledger, which
    # a rollback deletes from, stays off the list.
    assert {:ok, _} =
             Repo.query("ALTER TABLE regent_points.accounts ADD COLUMN listed_probe integer")

    assert {:ok, %{num_rows: 0}} =
             Repo.query("DELETE FROM regent_points.schema_migrations WHERE version = 0")
  end

  test "nothing changes when one of the tables is already listed" do
    Repo.query!("SELECT regent_guard.protect('regent_points.point_entries', false)")
    before = Repo.query!(@listed).rows

    assert_raise RuntimeError, fn -> Release.protect_points(Repo) end
    assert Repo.query!(@listed).rows == before

    assert {:ok, %{num_rows: 0}} =
             Repo.query("DELETE FROM regent_points.accounts WHERE false", [], mode: :savepoint)
  end
end
