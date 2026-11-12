# A resource that names no schema, the way the site's own resources do, so every
# write takes its schema from the Repo (`AshTemplate.Repo.default_options/1`).
defmodule AshTemplate.SchemaPrefixProbe do
  @moduledoc false
  use Ash.Resource,
    domain: AshTemplate.SchemaPrefixProbes,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "schema_prefix_probes"
    repo(AshTemplate.Repo)
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

defmodule AshTemplate.SchemaPrefixProbes do
  @moduledoc false
  use Ash.Domain, validate_config_inclusion?: false

  resources do
    resource AshTemplate.SchemaPrefixProbe
  end
end
