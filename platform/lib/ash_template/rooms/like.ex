defmodule AshTemplate.Rooms.Like do
  @moduledoc """
  One signed-in person liking one room message (`AshTemplate.Rooms.Message`),
  once: liking it again changes nothing, and only they can take it back. An
  agent they paired likes for them. Everyone sees how many likes a message has
  (its `like_count`); who liked it stays with each person. A like and a like
  taken back are published on the message's room topic as
  `%{event: "like", payload: %{id: message_id, room: room}}`, so each open page
  of the room reads that message again and shows its count as it stands.
  """

  use Ash.Resource,
    domain: AshTemplate.Rooms,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    notifiers: [Ash.Notifier.PubSub]

  alias AshTemplate.Accounts.HumanAccount
  alias AshTemplate.Rooms.Like.InMessagesRoom
  alias AshTemplate.Rooms.Message

  postgres do
    table "room_message_likes"
    repo(AshTemplate.Repo)

    references do
      reference(:message, on_delete: :delete)
    end
  end

  attributes do
    uuid_primary_key :id
    # The liked message's room, so the like is published where the message is.
    attribute :room, :string, allow_nil?: false
    create_timestamp :inserted_at
  end

  relationships do
    belongs_to :message, Message, allow_nil?: false

    belongs_to :liker, HumanAccount do
      allow_nil? false
      attribute_type :integer
    end
  end

  identities do
    identity :one_per_liker, [:message_id, :liker_id]
  end

  actions do
    defaults [:read, :destroy]

    # The like the actor gave this message, if they gave one.
    read :mine do
      get? true
      argument :message_id, :uuid, allow_nil?: false
      filter expr(message_id == ^arg(:message_id) and liker_id == ^actor(:human_account_id))
    end

    create :like do
      accept [:message_id]
      upsert? true
      upsert_identity :one_per_liker
      upsert_fields []
      change set_attribute(:liker_id, actor(:human_account_id))
      change InMessagesRoom
    end
  end

  # An agent's like, or one it takes back, rechecks its pairing inside the transaction.
  changes do
    change {RegentAgents.RequirePairing, repo: AshTemplate.Repo}, on: [:create, :destroy]
  end

  policies do
    policy always() do
      authorize_if actor_attribute_equals(:role, :human)
      authorize_if {RegentAgents.Checks.Paired, repo: AshTemplate.Repo}
    end

    policy action_type([:read, :destroy]) do
      authorize_if expr(liker_id == ^actor(:human_account_id))
    end
  end

  pub_sub do
    module Phoenix.PubSub
    name AshTemplate.PubSub
    prefix "public"
    broadcast_type :broadcast

    publish :like, ["room", :room],
      event: "like",
      returns: :map,
      transform: &%{id: &1.data.message_id, room: &1.data.room}

    publish :destroy, ["room", :room],
      event: "like",
      returns: :map,
      transform: &%{id: &1.data.message_id, room: &1.data.room}
  end
end
