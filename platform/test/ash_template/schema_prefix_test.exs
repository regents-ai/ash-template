# A resource that names no schema, the way the site's own resources do, so every
# write takes its schema from the Repo (`AshTemplate.Repo.default_options/1`).
defmodule AshTemplate.SchemaPrefixTest.Probe do
  @moduledoc false
  use Ash.Resource,
    domain: AshTemplate.SchemaPrefixTest.Probes,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "schema_prefix_probes"
    repo AshTemplate.Repo
  end

  attributes do
    uuid_primary_key :id
    attribute :name, :string, allow_nil?: false
    attribute :amount, :integer, allow_nil?: false
  end

  identities do
    identity :unique_name, [:name]
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:name, :amount]
    end

    create :upsert do
      accept [:name, :amount]
      upsert? true
      upsert_identity :unique_name
      upsert_fields [:amount]
    end

    update :update do
      accept [:amount]
    end
  end
end

defmodule AshTemplate.SchemaPrefixTest.Probes do
  @moduledoc false
  use Ash.Domain, validate_config_inclusion?: false

  resources do
    resource AshTemplate.SchemaPrefixTest.Probe
  end
end

defmodule AshTemplate.SchemaPrefixTest do
  # Regression: every Hex release of ash_postgres through 2.15.2 built `Ash.update_many`
  # (and upserts, unless MERGE was turned off) with only the resource's own schema as
  # the prefix, never the Repo's, so on the
  # shared database they went to an unqualified table: `public`'s copy when one
  # exists, an error when none does. ash-project/ash_postgres#910 keeps the Repo's
  # prefix. platform/mix.exs pins the commit that carries it; run this before moving
  # that pin. Each table below is made inside the test's own transaction, which
  # always rolls back.
  use ExUnit.Case, async: true

  alias AshTemplate.Repo
  alias AshTemplate.SchemaPrefixTest.Probe

  @site Repo.default_prefix()
  @table "schema_prefix_probes"

  setup do
    owner = Ecto.Adapters.SQL.Sandbox.start_owner!(Repo)
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(owner) end)

    for schema <- [@site, "public"] do
      Ecto.Adapters.SQL.query!(
        Repo,
        ~s(CREATE TABLE "#{schema}".#{@table} ) <>
          "(id uuid PRIMARY KEY, name text NOT NULL UNIQUE, amount bigint NOT NULL)",
        []
      )
    end

    :ok
  end

  test "a create, a read, an update and a destroy touch only the site's schema" do
    probe = create("kept", 1)
    assert rows(@site) == [["kept", 1]]
    assert rows("public") == []

    # The same row in public, which a write sent there would change or remove.
    decoy("kept", probe.id)

    probe = probe |> Ash.Changeset.for_update(:update, %{amount: 2}) |> Ash.update!()
    assert rows(@site) == [["kept", 2]]
    assert [%{amount: 2}] = Ash.read!(Probe)

    Ash.destroy!(probe)
    assert rows(@site) == []
    assert rows("public") == [["kept", 100]]
  end

  test "an upsert, of one record or many, lands only in the site's schema" do
    # Public already holds the name, so an upsert sent there would update it.
    decoy("taken", Ash.UUID.generate())

    upsert("taken", 1)
    assert rows(@site) == [["taken", 1]]

    upsert("taken", 2)
    assert rows(@site) == [["taken", 2]]

    assert %Ash.BulkResult{status: :success} =
             Ash.bulk_create(
               [%{name: "taken", amount: 3}, %{name: "new", amount: 1}],
               Probe,
               :upsert,
               return_errors?: true
             )

    assert rows(@site) == [["new", 1], ["taken", 3]]
    assert rows("public") == [["taken", 100]]
  end

  test "updating many records at once changes only the site's rows" do
    # PostgreSQL 17 (`AshTemplate.Repo.min_pg_version/0`) makes this one MERGE.
    assert Ash.DataLayer.data_layer_can?(Probe, :update_many)

    first = create("first", 1)
    second = create("second", 1)
    decoy("first", first.id)
    decoy("second", second.id)

    assert %Ash.BulkResult{status: :success} =
             Ash.update_many(
               [{first, %{amount: 5}}, {second, %{amount: 6}}],
               Probe,
               :update,
               return_errors?: true
             )

    assert rows(@site) == [["first", 5], ["second", 6]]
    assert rows("public") == [["first", 100], ["second", 100]]
  end

  defp create(name, amount),
    do: Probe |> Ash.Changeset.for_create(:create, %{name: name, amount: amount}) |> Ash.create!()

  defp upsert(name, amount),
    do: Probe |> Ash.Changeset.for_create(:upsert, %{name: name, amount: amount}) |> Ash.create!()

  defp decoy(name, id) do
    Ecto.Adapters.SQL.query!(
      Repo,
      "INSERT INTO public.#{@table} (id, name, amount) VALUES ($1::text::uuid, $2, 100)",
      [id, name]
    )
  end

  defp rows(schema) do
    %{rows: rows} =
      Ecto.Adapters.SQL.query!(
        Repo,
        ~s(SELECT name, amount FROM "#{schema}".#{@table} ORDER BY name),
        []
      )

    rows
  end
end
