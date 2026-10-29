defmodule AshTemplate.ProductEvents.Event do
  @moduledoc """
  One thing a person or agent reached on this site (`AshTemplate.ProductEvents`
  names them), kept for good: rows are only created and read, never changed or
  deleted. A row names the account, the agent or both by the site's own ids, the
  surface it came through, a `kind` for the events that have one and, on
  `account_created` alone, where the browser first came from. It holds nothing a
  person wrote.
  """

  use Ash.Resource,
    domain: AshTemplate.ProductEvents,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  alias AshTemplate.ProductEvents

  @names [
    :account_created,
    :signed_in,
    :visited,
    :agent_paired,
    :agent_acted,
    :value_reached,
    :credits_bought
  ]

  # Credits' signals reach this resource in a job, after the credit has committed,
  # so a failure here never takes a credit back.
  @after_commit {AshOban.Signals, queue: :default, max_attempts: 3}

  postgres do
    table "product_events"
    repo(AshTemplate.Repo)

    identity_wheres_to_sql(one_account_created: "name = 'account_created'")

    custom_indexes do
      # Cohorts read each account's events in order, and each name's by day.
      index([:human_account_id, :inserted_at])
      index([:name, :inserted_at])
    end
  end

  attributes do
    # Writable for `credits_bought`, whose row takes the purchase's own id.
    uuid_v7_primary_key :id, writable?: true

    attribute :name, :atom, allow_nil?: false, public?: true, constraints: [one_of: @names]

    # The value action, the agent's route, the paired agent's harness or how
    # Credits were paid.
    attribute :kind, :string,
      public?: true,
      constraints: [max_length: 120, match: ~r/\A[A-Za-z0-9_.:\/@* -]{1,120}\z/]

    attribute :human_account_id, :integer, public?: true
    attribute :agent_id, :uuid, public?: true

    attribute :surface, :atom,
      public?: true,
      constraints: [one_of: [:page, :webmcp, :cli, :agent_http, :job]]

    # Where the account's browser first came from, as its arrival named it
    # (`AshTemplateWeb.VisitLog`), and the link's `utm_campaign`. Never an address.
    attribute :source, :string, public?: true, constraints: [match: ~r/\A[a-z_]{1,32}\z/]

    attribute :campaign, :string,
      public?: true,
      constraints: [match: ~r/\A[a-z0-9][a-z0-9_-]{0,47}\z/]

    create_timestamp :inserted_at, public?: true
  end

  identities do
    identity :one_account_created, [:human_account_id], where: expr(name == :account_created)
  end

  validations do
    validate present([:human_account_id, :agent_id], at_least: 1)
  end

  signals_in do
    from RegentCredits.Signals do
      on :purchase_credited, :usdc_credited, delivery: @after_commit
      on :purchase_attributed, :usdc_attributed, action: :usdc_credited, delivery: @after_commit
      on :card_purchase_credited, :card_credited, delivery: @after_commit
    end
  end

  actions do
    defaults [:read]

    create :record do
      accept [:name, :kind, :human_account_id, :agent_id, :surface]
      validate one_of(:name, [:signed_in, :visited, :agent_paired, :agent_acted, :value_reached])
    end

    # An account's first sign-in here, once: a later one finds this row and
    # leaves it as it is.
    create :account_created do
      accept [:human_account_id, :surface, :source, :campaign]
      change set_attribute(:name, :account_created)
      upsert? true
      upsert_identity :one_account_created
      upsert_fields []
    end

    # One row per Credits purchase, under the purchase's id, so a job that runs
    # again writes nothing new.
    create :credits_bought do
      accept [:id, :kind, :human_account_id, :surface]
      change set_attribute(:name, :credits_bought)
      upsert? true
      upsert_fields []
    end

    action :usdc_credited do
      argument :signal, :struct, allow_nil?: false
      run fn %{arguments: %{signal: signal}}, _context ->
        ProductEvents.credited(signal, "usdc")
      end
    end

    action :card_credited do
      argument :signal, :struct, allow_nil?: false
      run fn %{arguments: %{signal: signal}}, _context ->
        ProductEvents.credited(signal, "card")
      end
    end
  end

  policies do
    # Only the site's own code writes and reads events.
    policy action_type([:create, :read]) do
      authorize_if actor_attribute_equals(:role, :system)
    end

    # Reached only through Credits' signals above, after the credit was allowed,
    # in a job that carries no actor; each writes as the system.
    policy action_type(:action) do
      authorize_if always()
    end
  end

  @doc "Every event name, the same on every site."
  def names, do: @names
end
