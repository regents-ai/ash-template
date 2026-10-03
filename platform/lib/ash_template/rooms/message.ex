defmodule AshTemplate.Rooms.Message do
  @moduledoc """
  One message in one of the site's rooms (`AshTemplate.Rooms.Room`). Anyone can
  read a room; a signed-in person can post, a few times a minute at most, and
  only a message's author can change or delete it. A signed-in reader never
  sees messages from anyone they muted (`AshTemplate.Rooms.Mute`). Every post,
  edit and delete is published on the room's topic, so each open page of that
  room shows it at once.
  """

  use Ash.Resource,
    domain: AshTemplate.Rooms,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    notifiers: [Ash.Notifier.PubSub]

  alias AshTemplate.Rooms.Message.{LeaveOutMuted, LimitPosts}
  alias AshTemplate.Rooms.{Mute, Room}

  postgres do
    table "room_messages"
    repo(AshTemplate.Repo)

    custom_indexes do
      index([:room, :inserted_at])
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :room, :atom, allow_nil?: false, public?: true, constraints: [one_of: Room.slugs()]
    attribute :body, :string, allow_nil?: false, public?: true, constraints: [max_length: 2000]

    # The author's display name, or their short wallet address, when they posted.
    # Other people's accounts are private, so the name is kept with the message.
    attribute :author_name, :string, allow_nil?: false, public?: true
    attribute :edited_at, :utc_datetime_usec, public?: true
    create_timestamp :inserted_at, public?: true
  end

  relationships do
    belongs_to :human_account, AshTemplate.Accounts.HumanAccount do
      allow_nil? false
      attribute_type :integer
    end

    # Every mute of this message's author, so a read can leave out the reader's.
    has_many :author_mutes, Mute do
      source_attribute :human_account_id
      destination_attribute :muted_account_id
    end
  end

  actions do
    defaults [:read, :destroy]

    # Newest first, a page at a time.
    read :in_room do
      argument :room, :atom, allow_nil?: false, constraints: [one_of: Room.slugs()]
      filter expr(room == ^arg(:room))
      prepare LeaveOutMuted
      prepare build(sort: [inserted_at: :desc, id: :desc])
      pagination keyset?: true, default_limit: 50
    end

    create :post do
      accept [:room, :body]
      change set_attribute(:human_account_id, actor(:human_account_id))
      change set_attribute(:author_name, actor(:name))
      change LimitPosts
    end

    update :edit do
      accept [:body]
      change atomic_update(:edited_at, expr(now()))
    end
  end

  policies do
    policy action_type(:read) do
      authorize_if always()
    end

    policy action(:post) do
      authorize_if actor_attribute_equals(:role, :human)
    end

    policy action_type([:update, :destroy]) do
      authorize_if expr(human_account_id == ^actor(:human_account_id))
    end
  end

  # Delivered after the transaction commits, as %{event: "post" | "edit" |
  # "destroy", payload: message}, to `topic/1` of the message's room.
  pub_sub do
    module Phoenix.PubSub
    name AshTemplate.PubSub
    prefix "rooms"
    broadcast_type :broadcast
    transform & &1.data

    publish :post, [:room]
    publish :edit, [:room]
    publish :destroy, [:room]
  end

  @doc "The topic every post, edit and delete in `room` is published on."
  def topic(room), do: "rooms:#{room}"
end
