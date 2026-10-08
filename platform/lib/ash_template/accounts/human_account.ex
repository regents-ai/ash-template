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
    attribute :avatar, :map
    create_timestamp :created_at
    update_timestamp :updated_at
  end

  relationships do
    has_one :ens_identity, AshTemplate.Accounts.EnsIdentity do
      destination_attribute :human_account_id
    end
  end

  calculations do
    # The name set in the person's shared Regent profile.
    calculate :display_name, :string, AshTemplate.Accounts.HumanAccount.ProfileName, public?: true

    # The ENS name and picture, only while they were read for the account's
    # current wallet.
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
    # Loading the name and picture after sign-in writes the account reads it
    # again through the primary read.
    read :read do
      primary? true
    end

    read :points_account do
      get? true
      argument :id, :integer, allow_nil?: false
      filter expr(id == ^arg(:id))
    end

    read :points_wallet_holders do
      argument :wallets, {:array, :string}, allow_nil?: false

      filter expr(
               wallet_address in ^arg(:wallets) or
                 fragment("? && ?::text[]", wallet_addresses, ^arg(:wallets))
             )
    end

    read :by_privy_did do
      get? true
      argument :privy_did, :string, allow_nil?: false
      filter expr(privy_user_id == ^arg(:privy_did))
      prepare build(load: [:display_name, :ens_name, :ens_avatar_url])
    end

    read :read_self do
      get? true
      argument :id, :integer, allow_nil?: false
      filter expr(id == ^arg(:id))
      prepare build(load: [:display_name, :ens_name, :ens_avatar_url])
    end

    create :register_verified do
      accept [:privy_user_id, :wallet_address, :wallet_addresses]
      upsert? true
      upsert_identity :unique_privy_user_id
      upsert_fields []
      change load([:display_name])
    end

    update :refresh_verified do
      accept [:wallet_address, :wallet_addresses]
      require_atomic? false
      validate present(:wallet_addresses)
      change load([:display_name, :ens_name, :ens_avatar_url])
      change AshTemplate.Points.TrackWallets
    end
  end

  policies do
    policy action([
             :read,
             :by_privy_did,
             :register_verified,
             :refresh_verified,
             :points_account,
             :points_wallet_holders
           ]) do
      authorize_if actor_attribute_equals(:role, :system)
    end

    policy action(:read_self) do
      authorize_if expr(id == ^actor(:human_account_id))
    end
  end
end
