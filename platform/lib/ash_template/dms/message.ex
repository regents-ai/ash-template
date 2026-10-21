defmodule AshTemplate.Dms.Message do
  @moduledoc """
  One direct message, from one side of a conversation (`AshTemplate.Dms.Conversation`)
  to the other. Its sender is the actor's person; an agent they paired writes
  as them, and the message names it (`via_agent`). Messages are never edited.

  An agent sends with an `operation_id`, which becomes the message's id, so a
  retry answers the message it already sent (`:earlier_send`). Every message
  moves its conversation up and is published to both sides' topic
  (`AshTemplate.Dms.topic/1`), so their open pages show it at once.
  """

  use Ash.Resource,
    domain: AshTemplate.Dms,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    notifiers: [Ash.Notifier.PubSub]

  alias AshTemplate.Dms.Message.SendInConversation
  alias AshTemplate.Limits.LimitWrites

  postgres do
    table "dm_messages"
    repo(AshTemplate.Repo)

    references do
      reference(:conversation, on_delete: :delete)
    end

    custom_indexes do
      index([:conversation_id, :inserted_at])
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :body, :string, allow_nil?: false, public?: true, constraints: [max_length: 2000]
    create_timestamp :inserted_at, public?: true
  end

  relationships do
    belongs_to :conversation, AshTemplate.Dms.Conversation do
      allow_nil? false
      public? true
    end

    belongs_to :from, AshTemplate.Accounts.HumanAccount do
      attribute_type :integer
      allow_nil? false
    end

    belongs_to :to, AshTemplate.Accounts.HumanAccount do
      attribute_type :integer
      allow_nil? false
    end

    # The paired agent that wrote it for its person; nil when the person did.
    belongs_to :via_agent, AshTemplate.Agents.Agent, public?: true
  end

  calculations do
    # Whether the reader sent it.
    calculate :mine, :boolean, expr(from_id == ^actor(:human_account_id))
  end

  actions do
    defaults [:read]

    # Newest first, a page at a time.
    read :in_conversation do
      argument :conversation_id, :uuid, allow_nil?: false
      filter expr(conversation_id == ^arg(:conversation_id))
      prepare build(sort: [inserted_at: :desc, id: :desc], load: [:mine])
      pagination keyset?: true, default_limit: 50
    end

    # The message the actor's person already sent with this id, so a retry
    # answers the first send.
    read :earlier_send do
      get? true
      argument :id, :uuid, allow_nil?: false
      filter expr(id == ^arg(:id) and from_id == ^actor(:human_account_id))
      prepare build(load: [:mine])
    end

    create :send do
      accept [:body]
      argument :conversation_id, :uuid, allow_nil?: false
      argument :operation_id, :uuid

      change fn changeset, %{actor: actor} ->
        if Map.get(actor || %{}, :role) == :agent and
             is_nil(Ash.Changeset.get_argument(changeset, :operation_id)),
           do:
             Ash.Changeset.add_error(changeset,
               field: :operation_id,
               message: "is required for agent creates"
             ),
           else: changeset
      end

      change set_attribute(:id, arg(:operation_id)), where: [present(:operation_id)]
      change SendInConversation

      change {LimitWrites,
              allowance: :dm,
              field: :body,
              message: "You've sent a lot of messages this hour. Try again later."}

      change load([:mine])
    end
  end

  # An agent's send rechecks its pairing inside the transaction.
  changes do
    change {RegentAgents.RequirePairing, repo: AshTemplate.Repo}, on: [:create]
  end

  policies do
    policy always() do
      authorize_if actor_attribute_equals(:role, :human)
      authorize_if {RegentAgents.Checks.Paired, repo: AshTemplate.Repo}
    end

    policy action_type(:read) do
      authorize_if expr(
                     conversation.person_a == ^actor(:human_account_id) or
                       conversation.person_b == ^actor(:human_account_id)
                   )
    end
  end

  # Delivered after the transaction commits to `AshTemplate.Dms.topic/1` of
  # both sides: %{event: "send", payload: %{conversation_id: id, message_id: id}}.
  pub_sub do
    module Phoenix.PubSub
    name AshTemplate.PubSub
    prefix "dms"
    broadcast_type :broadcast
    transform &%{conversation_id: &1.data.conversation_id, message_id: &1.data.id}

    publish :send, [:from_id]
    publish :send, [:to_id]
  end
end
