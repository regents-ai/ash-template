defmodule AshTemplate.Agents.Agent do
  @moduledoc """
  An agent known by the wallet it signs every request with (`AshTemplateWeb.Plugs.AgentWallet`).
  Its first signed request adds it; it acts on the site as itself, never as a person.
  """

  use Ash.Resource,
    domain: AshTemplate.Agents,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "agents"
    repo(AshTemplate.Repo)
  end

  attributes do
    uuid_primary_key :id

    attribute :wallet_address, :string do
      allow_nil? false
      public? true
      constraints match: ~r/\A0x[0-9a-f]{40}\z/
    end

    create_timestamp :inserted_at, public?: true
  end

  identities do
    identity :unique_wallet_address, [:wallet_address]
  end

  actions do
    defaults [:read]

    # The wallet's agent, added on its first signed request.
    create :sign_in do
      argument :wallet_address, :string, allow_nil?: false
      upsert? true
      upsert_identity :unique_wallet_address
      upsert_fields []
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
