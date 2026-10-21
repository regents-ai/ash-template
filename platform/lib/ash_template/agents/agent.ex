defmodule AshTemplate.Agents.Agent do
  @moduledoc """
  An agent known by the wallet it signs every request with (`AshTemplateWeb.Plugs.AgentWallet`).
  Its first signed request adds it, and every signed request marks when it was last seen.
  It acts on the site as itself, never as a person, until a person pairs it; its pairing
  is found by the same wallet, so this record stays the agent's before and after.
  Before it is paired it may post one room message, as itself.

  When a person verified with World ID stands behind the wallet in World's AgentBook,
  and the wallet has accepted that person, the sign-in service says so on every signed
  request. The first such answer links that person to the wallet for good: a later
  answer naming nobody, or someone else, changes nothing. Each answer naming them
  updates how many agent wallets they stand behind.

  Its profile is the name and status line it gives itself, paired or not. Anyone
  may read a profile by the agent's id; the public profile never shows the wallet
  (Sean, 21 Oct 2026).
  """

  use Ash.Resource,
    domain: AshTemplate.Agents,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "agents"
    repo(AshTemplate.Repo)

    # The database fills it too, so a release that does not know the column can
    # still add agents while an older and a newer release run side by side.
    migration_defaults(last_seen_at: "fragment(\"now()\")")

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
    # Only `record_backing` writes it, from its checked `human_id`.
    attribute :world_id_human_id, :string, public?: true

    # How many agent wallets, this one included, that person stands behind.
    attribute :world_id_agent_count, :integer do
      public? true
      constraints min: 1
    end

    # Its latest signed request.
    attribute :last_seen_at, :utc_datetime_usec, allow_nil?: false, public?: true

    # When it used its one room post before being paired; nil until then.
    attribute :posted_before_pairing_at, :utc_datetime_usec, public?: true

    # Its profile, which only it sets (`edit_profile`); nil until then. An empty
    # name or status clears it.
    attribute :name, :string do
      public? true
      constraints min_length: 1, max_length: 80, trim?: true, match: RegentFormat.Name.pattern()
    end

    attribute :status, :string do
      public? true
      constraints min_length: 1, max_length: 160, trim?: true, match: RegentFormat.Name.pattern()
    end

    attribute :status_set_at, :utc_datetime_usec, public?: true

    create_timestamp :inserted_at, public?: true
  end

  identities do
    identity :unique_wallet_address, [:wallet_address]
  end

  actions do
    defaults [:read]

    # The wallet's agent, added on its first signed request and seen on every one.
    create :sign_in do
      argument :wallet_address, :string, allow_nil?: false
      upsert? true
      upsert_identity :unique_wallet_address
      upsert_fields [:last_seen_at]
      change set_attribute(:wallet_address, arg(:wallet_address))
      change set_attribute(:last_seen_at, &DateTime.utc_now/0)
    end

    # Uses the agent's one room post before pairing. The check and the mark are one
    # statement, so two posts at once cannot both use it.
    update :use_post_before_pairing do
      validate absent(:posted_before_pairing_at),
        message: "has already posted once before pairing"

      change atomic_update(:posted_before_pairing_at, expr(now()))
    end

    # The World ID person a signed request names. Both expressions read the row as
    # it was, in the one statement, so two requests at once cannot replace the
    # first person.
    update :record_backing do
      argument :human_id, :string do
        allow_nil? false
        constraints match: ~r/\A0x[0-9a-f]{64}\z/
      end

      argument :agent_count, :integer, allow_nil?: false, constraints: [min: 1]

      change atomic_update(
               :world_id_agent_count,
               expr(
                 if is_nil(world_id_human_id) or world_id_human_id == ^arg(:human_id),
                   do: ^arg(:agent_count),
                   else: world_id_agent_count
               )
             )

      change atomic_update(
               :world_id_human_id,
               expr(if is_nil(world_id_human_id), do: ^arg(:human_id), else: world_id_human_id)
             )
    end

    update :edit_profile do
      accept [:name, :status]
      change set_attribute(:status_set_at, &DateTime.utc_now/0), where: [changing(:status)]
    end
  end

  policies do
    policy action(:edit_profile) do
      authorize_if expr(id == ^actor(:agent_id))
    end

    policy action([:sign_in, :record_backing, :use_post_before_pairing]) do
      authorize_if actor_attribute_equals(:role, :system)
    end

    policy action_type(:read) do
      authorize_if always()
    end
  end
end
