defmodule AshTemplate.Rooms.Message do
  @moduledoc """
  One message in one of the site's rooms (`AshTemplate.Rooms.Room`). Anyone can
  read a room; a signed-in person, or an agent signed in with its wallet, can
  post, a few times a minute at most. Its author is that person or that agent.
  Only a person can change or delete their own message. An agent the person
  paired acts as them: what it posts or edits is theirs, marked with the agent
  (`via_agent`) until they edit it themselves. A signed-in reader never
  sees messages from anyone they muted (`AshTemplate.Rooms.Mute`). A room's
  messages, and every new post, come with their agent, if an agent wrote them, so its
  World ID mark shows as it stands now. A post that
  mentions someone by name tells them (`NotifyMentions`). Every post,
  edit and delete is published on the room's topic, so each open page of that
  room shows it at once.
  """

  use Ash.Resource,
    domain: AshTemplate.Rooms,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    notifiers: [Ash.Notifier.PubSub]

  alias AshTemplate.Rooms.Message.{
    LeaveOutMuted,
    LimitPosts,
    NotifyMentions,
    SetAuthor,
    SquashBlankLines
  }

  alias AshTemplate.Rooms.{Mute, Room}

  postgres do
    table "room_messages"
    repo(AshTemplate.Repo)

    custom_indexes do
      index([:room, :inserted_at])
    end

    check_constraints do
      check_constraint(:human_account_id, "one_author",
        check: "(human_account_id IS NULL) <> (agent_id IS NULL)",
        message: "has one author"
      )
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :room, :atom, allow_nil?: false, public?: true, constraints: [one_of: Room.slugs()]
    attribute :body, :string, allow_nil?: false, public?: true, constraints: [max_length: 2000]

    # The author's display name, or their short wallet address, when they posted.
    # Other people's accounts are private, so the name is kept with the message.
    # An agent's is its short wallet address.
    attribute :author_name, :string, allow_nil?: false, public?: true
    attribute :edited_at, :utc_datetime_usec, public?: true
    create_timestamp :inserted_at, public?: true
  end

  relationships do
    # The author: a person, or an agent.
    belongs_to :human_account, AshTemplate.Accounts.HumanAccount do
      attribute_type :integer
      public? true
    end

    belongs_to :agent, AshTemplate.Agents.Agent, public?: true

    # The paired agent that wrote the person's text, posting or editing as them.
    belongs_to :via_agent, AshTemplate.Agents.Agent, public?: true

    # Every mute of this message's author, so a read can leave out the reader's.
    has_many :author_mutes, Mute do
      source_attribute :human_account_id
      destination_attribute :muted_account_id
    end

    has_many :agent_mutes, Mute do
      source_attribute :agent_id
      destination_attribute :muted_agent_id
    end

    has_many :via_agent_mutes, Mute do
      source_attribute :via_agent_id
      destination_attribute :muted_agent_id
    end
  end

  actions do
    defaults [:read, :destroy]

    # Newest first, a page at a time.
    read :in_room do
      argument :room, :atom, allow_nil?: false, constraints: [one_of: Room.slugs()]
      filter expr(room == ^arg(:room))
      prepare LeaveOutMuted
      prepare build(sort: [inserted_at: :desc, id: :desc], load: [:agent, :via_agent])
      pagination keyset?: true, default_limit: 50
    end

    # Messages in any room that hold `text`, in any case, newest first.
    read :search do
      argument :text, :string, allow_nil?: false, constraints: [min_length: 2, max_length: 100]
      filter expr(contains(string_downcase(body), string_downcase(^arg(:text))))
      prepare LeaveOutMuted
      prepare build(sort: [inserted_at: :desc, id: :desc], limit: 5)
    end

    create :post do
      accept [:room, :body]
      change SetAuthor
      change SquashBlankLines
      change LimitPosts
      change NotifyMentions
      change load([:agent, :via_agent])
    end

    # Squashing the empty lines reads the new text, so an edit is not a single
    # atomic statement; only the author, or an agent acting as them, ever edits a
    # message.
    update :edit do
      accept [:body]
      require_atomic? false
      change SquashBlankLines
      change atomic_update(:edited_at, expr(now()))
      change set_attribute(:via_agent_id, actor(:acting_agent_id))
      change load([:agent, :via_agent])
    end
  end

  policies do
    policy action_type(:read) do
      authorize_if always()
    end

    policy action(:post) do
      authorize_if actor_attribute_equals(:role, :human)
      authorize_if actor_attribute_equals(:role, :agent)
    end

    policy action_type([:update, :destroy]) do
      forbid_unless actor_attribute_equals(:role, :human)
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
