defmodule AshTemplate.Rooms.Like do
  @moduledoc """
  One signed-in person liking one room message (`AshTemplate.Rooms.Message`),
  once: liking it again changes nothing, and only they can take it back. An
  agent they paired likes for them. Everyone sees how many likes a message has
  (its `like_count`); who liked it stays with each person. A like and a like
  taken back move that count in their own transaction (`CountLike`), and the
  message publishes the count it moved to, so no open page reads it again.

  Liking and taking back share one allowance for each person and one for each
  client address (`AshTemplate.Limits.LimitWrites`): far more than anyone liking
  their way through a room, far fewer than a script toggling a like many times a
  second, which every open page of the room would hear.
  """

  use Ash.Resource,
    domain: AshTemplate.Rooms,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  alias AshTemplate.Accounts.HumanAccount
  alias AshTemplate.Limits.LimitWrites
  alias AshTemplate.Rooms
  alias AshTemplate.Rooms.Like.CountLike
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
    # The liked message's room, as the message has it.
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
    defaults [:read]

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

      change {LimitWrites, allowance: :like, address_allowance: :like_address, field: :message_id}

      # Filed under the room of the message named, while that message is still
      # here. It is read inside the transaction, so a like past the allowance
      # reads nothing.
      change fn changeset, context ->
        Ash.Changeset.before_action(changeset, fn changeset ->
          message_id = Ash.Changeset.get_attribute(changeset, :message_id)

          case Rooms.get_message(message_id, Ash.Context.to_opts(context)) do
            {:ok, %Message{room: room}} ->
              Ash.Changeset.force_change_attribute(changeset, :room, room)

            _gone ->
              Ash.Changeset.add_error(changeset,
                field: :message_id,
                message: "That message is no longer here."
              )
          end
        end)
      end

      change {CountLike, by: 1}
    end

    # The allowance is spent before the transaction opens, so a take-back is not
    # a single atomic statement.
    destroy :destroy do
      primary? true
      require_atomic? false
      change {LimitWrites, allowance: :like, address_allowance: :like_address, field: :message_id}
      change {CountLike, by: -1}
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
end
