defmodule AshTemplate.Accounts.EnsIdentity do
  @moduledoc """
  The ENS name and picture Ethereum mainnet publishes for an account's wallet.

  This is a copy of public chain state, not identity evidence: the account's
  own row keeps the verified Privy identity and wallet. Each sign-in asks again
  (`:request_lookup`), and one job, queued in the same transaction, reads the
  chain outside any transaction (`LookUp`). A wallet with no verified name is
  stored with none; a lookup that keeps failing leaves the last name standing.

  The row is written only when it changes, and the account's open pages are
  told only when its name or picture does. A sign-in with the wallet the row
  was read for writes nothing, and an answer the same as the stored one writes
  and announces nothing, so those pages stay exactly as the person left them.

  `wallet_address` is the wallet the row was read for, so an account whose
  wallet has since changed is never shown the old wallet's name. A sign-in with
  another wallet clears the name and picture at once, and its own lookup fills
  them in.

  Lookups run only while the server has an Ethereum endpoint
  (`ETHEREUM_READ_RPC_URL`).
  """

  use Ash.Resource,
    domain: AshTemplate.Accounts,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    notifiers: [Ash.Notifier.PubSub],
    extensions: [AshOban]

  alias AshTemplate.Accounts.EnsIdentity.LookUp

  postgres do
    table "account_ens_identities"
    repo(AshTemplate.Repo)
  end

  attributes do
    uuid_primary_key :id
    attribute :wallet_address, :string, allow_nil?: false
    attribute :ens_name, :string, public?: true
    attribute :ens_avatar_url, :string, public?: true

    timestamps()
  end

  relationships do
    belongs_to :human_account, AshTemplate.Accounts.HumanAccount do
      allow_nil? false
      attribute_type :integer
    end
  end

  identities do
    identity :unique_human_account, [:human_account_id]
  end

  actions do
    defaults [:read]

    # Every sign-in queues a lookup. The row is written only for a wallet it was
    # not read for, which starts it again with no name or picture; for the same
    # wallet the upsert is skipped and the stored row comes back.
    create :request_lookup do
      accept [:human_account_id, :wallet_address]
      change set_attribute(:ens_name, nil, set_when_nil?: true)
      change set_attribute(:ens_avatar_url, nil, set_when_nil?: true)
      change run_oban_trigger(:look_up)
      upsert? true
      upsert_identity :unique_human_account
      upsert_fields [:wallet_address, :ens_name, :ens_avatar_url, :updated_at]
      upsert_condition expr(wallet_address != upsert_conflict(:wallet_address))
      return_skipped_upsert? true
    end

    update :look_up do
      transaction? false
      require_atomic? false
      change LookUp
    end
  end

  oban do
    triggers do
      # Every sign-in queues its own job, so there is no sweep to find missed ones.
      # One waits at a time, not one runs at a time: a sign-in with another wallet
      # while a lookup runs queues the lookup for its wallet, and the running one,
      # read for the old wallet, stops without writing (`LookUp`).
      trigger :look_up do
        action :look_up
        queue :ens
        max_attempts 3
        worker_opts unique: [period: :infinity, states: [:available, :scheduled, :retryable]]
        # A job that gives up logs one safe line (RegentHttp.UnexpectedFailure), not raw text.
        log_errors? false
        log_final_error? false
        lock_for_update? false
        scheduler_cron false
        worker_module_name AshTemplate.Accounts.EnsIdentity.Workers.LookUp
      end
    end
  end

  policies do
    bypass AshOban.Checks.AshObanInteraction do
      authorize_if always()
    end

    policy action(:request_lookup) do
      authorize_if actor_attribute_equals(:role, :system)
    end

    # Chain state anyone can read for themselves, so the account it belongs to
    # is what protects it, not this row.
    policy action(:read) do
      authorize_if always()
    end
  end

  # A lookup that changed the name or picture reaches the open pages of the
  # account it belongs to. One that found them as stored writes nothing and is
  # not announced.
  pub_sub do
    module Phoenix.PubSub
    name AshTemplate.PubSub
    prefix "ens_identity"
    broadcast_type :broadcast
    transform & &1.data

    publish :look_up, [:human_account_id],
      filter: fn %{changeset: changeset} ->
        Ash.Changeset.changing_attribute?(changeset, :ens_name) or
          Ash.Changeset.changing_attribute?(changeset, :ens_avatar_url)
      end
  end

  @doc "The topic a lookup that changed `human_account_id`'s name or picture is published on."
  def topic(human_account_id), do: "ens_identity:#{human_account_id}"

  @doc "The Ethereum mainnet endpoint lookups read from, or nil while the server has none."
  def rpc_url, do: Application.get_env(:ash_template, :ethereum_read_rpc_url)
end
