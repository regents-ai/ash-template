defmodule AshTemplate.Agents.Agent do
  @moduledoc """
  An agent known by the wallet it signs every request with (`AshTemplateWeb.Plugs.AgentWallet`).
  Its first signed request adds it; it acts on the site as itself, never as a person.

  When a person verified with World ID stands behind the wallet in World's AgentBook,
  and the wallet has accepted that person, the sign-in service says so on every signed
  request. Each request keeps its answer: the person's anonymous World ID number and how
  many agent wallets they stand behind, or neither.
  """

  use Ash.Resource,
    domain: AshTemplate.Agents,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "agents"
    repo(AshTemplate.Repo)

    check_constraints do
      check_constraint(:world_id_human_id, "world_id_whole",
        check: "(world_id_human_id IS NULL) = (world_id_agent_count IS NULL)",
        message: "has both World ID fields or neither"
      )
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :wallet_address, :string do
      allow_nil? false
      public? true
      constraints match: ~r/\A0x[0-9a-f]{40}\z/
    end

    # The person's anonymous World ID number; the same person's agents share it.
    attribute :world_id_human_id, :string do
      public? true
      constraints match: ~r/\A0x[0-9a-f]{64}\z/
    end

    # How many agent wallets, this one included, that person stands behind.
    attribute :world_id_agent_count, :integer do
      public? true
      constraints min: 1
    end

    create_timestamp :inserted_at, public?: true
  end

  identities do
    identity :unique_wallet_address, [:wallet_address]
  end

  actions do
    defaults [:read]

    # The wallet's agent, added on its first signed request, with the World ID
    # answer of this request.
    create :sign_in do
      argument :wallet_address, :string, allow_nil?: false
      accept [:world_id_human_id, :world_id_agent_count]
      upsert? true
      upsert_identity :unique_wallet_address
      upsert_fields [:world_id_human_id, :world_id_agent_count]
      change set_attribute(:wallet_address, arg(:wallet_address))
    end
  end

  policies do
    policy action(:sign_in) do
      authorize_if actor_attribute_equals(:role, :system)
    end

    policy action_type(:read) do
      authorize_if always()
    end
  end
end
