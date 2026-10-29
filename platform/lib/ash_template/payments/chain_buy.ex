defmodule AshTemplate.Payments.ChainBuy do
  @moduledoc """
  One purchase on the chain the site's buying wallet makes for a person, who
  pays for it in purchased Credits, one Credit per USDC. What is bought goes
  straight to the person's wallet. Agents buy for their person the same way,
  within the limits the person set for them.

  `:buy` reads the price from the sale before its transaction (`Quote`). In
  it, the day's buying lock is taken, a buy past the site's daily limit is
  refused, the price is held in the person's purchased Credits under the
  buy's id (`Reserve`) and the send is queued.

  The send runs once and one at a time, since every buy uses the wallet's
  next nonce (`Send`): it approves exactly the price to the sale, then sends
  the sale's call. A buy that went through charges the Credits. A refused
  approval, or a call the sale refused, gives them back. A call that may
  still land keeps them held while `CheckReceipt` reads its receipt; it is
  never sent again. A send that stops part way is left `:unknown`, its
  Credits held, for a person to look up on the chain; so is one whose
  machine stopped mid-send, which stays `:sending`.
  """

  use Ash.Resource,
    domain: AshTemplate.Payments,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshOban]

  alias AshTemplate.Payments.ChainBuy.{CloseHold, Quote, Receiver, Reserve, Send}

  postgres do
    table "chain_buys"
    repo(AshTemplate.Repo)

    custom_indexes do
      # The daily limit adds up today's buys; a person reads their own.
      index([:inserted_at])
      index([:privy_user_id, :inserted_at])
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :privy_user_id, :string, allow_nil?: false, public?: true

    # The agent that bought, and under which pairing, when an agent did.
    attribute :agent_address, :string, public?: true
    attribute :pairing_id, :uuid, public?: true

    # What was bought, in the sale's own words, and the wallet it went to.
    attribute :item, :string, allow_nil?: false, public?: true
    attribute :receiver, :string, allow_nil?: false, public?: true

    # The sale contract and its price in USDC millionths, read when it was bought.
    attribute :sale, :string, allow_nil?: false, public?: true
    attribute :price_atomic, :integer, allow_nil?: false, public?: true

    attribute :state, :atom,
      allow_nil?: false,
      default: :sending,
      public?: true,
      constraints: [one_of: [:sending, :bought, :failed, :unknown]]

    attribute :approval_hash, :string, public?: true
    attribute :call_hash, :string, public?: true
    attribute :failure, :string, public?: true

    create_timestamp :inserted_at, public?: true
    update_timestamp :updated_at, public?: true
  end

  actions do
    defaults [:read]

    create :buy do
      accept [:item, :receiver]
      validate Receiver
      change set_attribute(:privy_user_id, actor(:privy_user_id))
      change set_attribute(:agent_address, actor(:agent_address))
      change set_attribute(:pairing_id, actor(:pairing_id))
      change Quote
      change Reserve
      change run_oban_trigger(:send)
    end

    update :send do
      require_atomic? false
      change Send
      change CloseHold
    end

    update :settle do
      require_atomic? false
      argument :outcome, :atom, allow_nil?: false, constraints: [one_of: [:ok, :reverted]]
      validate attribute_equals(:state, :unknown)

      change fn changeset, _context ->
        case Ash.Changeset.get_argument(changeset, :outcome) do
          :ok ->
            Ash.Changeset.force_change_attribute(changeset, :state, :bought)

          :reverted ->
            Ash.Changeset.force_change_attributes(changeset, %{
              state: :failed,
              failure: "The sale refused the purchase."
            })
        end
      end

      change CloseHold
    end

    update :stopped do
      argument :error, :term
      change set_attribute(:state, :unknown)

      change set_attribute(
               :failure,
               "The send stopped part way. Look the wallet up on the chain."
             )
    end
  end

  oban do
    triggers do
      trigger :send do
        action :send
        where expr(state == :sending)
        queue :chain_buys
        max_attempts 1
        on_error :stopped
        log_errors? false
        lock_for_update? false
        scheduler_cron false
        worker_module_name AshTemplate.Payments.ChainBuy.Workers.Send
      end
    end
  end

  policies do
    bypass AshOban.Checks.AshObanInteraction do
      authorize_if always()
    end

    # The buyer is a Credits actor (`RegentCredits.Actor`) the caller built
    # from its own sign-in: a person, or a paired agent within its limits.
    policy action(:buy) do
      forbid_unless actor_attribute_equals(:__struct__, RegentCredits.Actor)
      authorize_if actor_attribute_equals(:role, :person)
      authorize_if actor_attribute_equals(:role, :agent)
    end

    policy action_type(:read) do
      authorize_if expr(privy_user_id == ^actor(:privy_user_id))
    end
  end
end
