defmodule AshTemplate.Accounts.HumanAccount do
  @moduledoc "A person's shared Regent account, read from the table Regents owns."

  use Ash.Resource,
    domain: AshTemplate.Accounts,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "platform_human_users"
    schema("regent_names")
    repo(AshTemplate.Repo)
    migrate?(false)
  end

  attributes do
    integer_primary_key :id
    attribute :privy_user_id, :string, allow_nil?: false, sensitive?: true
    attribute :wallet_address, :string, sensitive?: true
    attribute :wallet_addresses, {:array, :string}, default: [], sensitive?: true
    attribute :display_name, :string, public?: true, constraints: [max_length: 80]
    attribute :avatar, :map
    create_timestamp :created_at
    update_timestamp :updated_at
  end

  relationships do
    has_one :ens_identity, AshTemplate.Accounts.EnsIdentity do
      destination_attribute :human_account_id
    end
  end

  # The ENS name and picture, only while they were read for the account's
  # current wallet.
  calculations do
    calculate :ens_name,
              :string,
              expr(
                if ens_identity.wallet_address == wallet_address do
                  ens_identity.ens_name
                end
              )

    calculate :ens_avatar_url,
              :string,
              expr(
                if ens_identity.wallet_address == wallet_address do
                  ens_identity.ens_avatar_url
                end
              )
  end

  identities do
    identity :unique_privy_user_id, [:privy_user_id]
  end

  actions do
    read :by_privy_did do
      get? true
      argument :privy_did, :string, allow_nil?: false
      filter expr(privy_user_id == ^arg(:privy_did))
      prepare build(load: [:ens_name, :ens_avatar_url])
    end

    read :read_self do
      get? true
      argument :id, :integer, allow_nil?: false
      filter expr(id == ^arg(:id))
      prepare build(load: [:ens_name, :ens_avatar_url])
    end

    create :register_verified do
      accept [:privy_user_id, :wallet_address, :wallet_addresses]
      upsert? true
      upsert_identity :unique_privy_user_id
      upsert_fields []
    end

    update :refresh_verified do
      accept [:wallet_address, :wallet_addresses]
      require_atomic? false
      validate present(:wallet_addresses)
      change load([:ens_name, :ens_avatar_url])
    end
  end

  policies do
    policy action([:by_privy_did, :register_verified, :refresh_verified]) do
      authorize_if actor_attribute_equals(:role, :system)
    end

    policy action(:read_self) do
      authorize_if expr(id == ^actor(:human_account_id))
    end
  end
end
