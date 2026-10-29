defmodule AshTemplate.Rooms.Message do
  @moduledoc """
  One message in one room (`AshTemplate.Rooms.Room`). Anyone can
  read a room; a signed-in person, or an agent signed in with its wallet, can
  post, a few times a minute at most. Its author is that person or that agent.
  An agent no person has paired here posts as itself, once (`SetAuthor`).
  Only a person can change or delete their own message. An agent the person
  paired acts as them: what it posts or edits is theirs, marked with the agent
  (`via_agent`) until they edit it themselves. A signed-in reader never
  sees messages from anyone they muted (`AshTemplate.Rooms.Mute`). Each
  message counts its likes (`AshTemplate.Rooms.Like`), and a room read says
  which of them the reader liked. A room's
  messages, and every new post, come with their agent, if an agent wrote them, so its
  World ID mark shows as it stands now, and with the picture its author's
  account shows. Every post is told to the rest of the site as
  `:message_posted` (`AshTemplate.Rooms.Signals`), so a post that mentions
  someone by name tells them. Every post,
  edit and delete is published on the room's topic, so each open page of that
  room shows it at once, and every post and delete on `every_room_topic/0` as
  well. What is published is `public/1`, the fields a signed-out reader sees,
  never the record.
  """

  use Ash.Resource,
    domain: AshTemplate.Rooms,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    notifiers: [Ash.Notifier.PubSub]

  alias AshTemplate.Limits.LimitWrites

  alias AshTemplate.Rooms.Author

  alias AshTemplate.Rooms.Message.{
    ByAuthorKind,
    LeaveOutMuted,
    PostedByActor,
    SetAuthor,
    SquashBlankLines
  }

  alias AshTemplate.Rooms.{Like, Mute, Room}

  # What every room read and write loads for `public/1`.
  @shown [:agent, :via_agent, :author, :like_count]

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
    # The room's slug (`in_room`).
    attribute :room, :string, allow_nil?: false, public?: true
    attribute :body, :string, allow_nil?: false, public?: true, constraints: [max_length: 2000]

    # The author's display name when they posted, or nil when they had none: a
    # page then shows their wallet (`Author`). Other people's accounts are
    # private, so the name is kept with the message. An agent's is its profile
    # name, or "Unnamed agent"; never its wallet.
    attribute :author_name, :string, public?: true
    attribute :edited_at, :utc_datetime_usec, public?: true
    create_timestamp :inserted_at, public?: true
  end

  relationships do
    belongs_to :in_room, Room do
      source_attribute :room
      destination_attribute :slug
      attribute_type :string
      define_attribute? false
    end

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

    has_many :likes, Like
  end

  calculations do
    calculate :author,
              :map,
              {Author, name: :author_name, account: :human_account_id, agent: :agent}

    calculate :liked_by_me, :boolean, expr(exists(likes, liker_id == ^actor(:human_account_id)))
  end

  # Everyone sees every like counted, though only the liker reads their like.
  aggregates do
    count :like_count, :likes do
      authorize? false
    end
  end

  actions do
    defaults [:read]

    destroy :destroy do
      primary? true
      require_atomic? false
    end

    # Newest first, a page at a time, of everyone or one kind of author.
    read :in_room do
      argument :room, :string, allow_nil?: false
      argument :author_kind, :atom, constraints: [one_of: [:person, :agent]]
      filter expr(room == ^arg(:room))

      prepare ByAuthorKind
      prepare LeaveOutMuted
      prepare build(sort: [inserted_at: :desc, id: :desc], load: [:liked_by_me | @shown])
      pagination keyset?: true, default_limit: 50
    end

    # One message of a room, as the room shows it.
    read :one_in_room do
      get? true
      argument :room, :string, allow_nil?: false
      argument :id, :uuid, allow_nil?: false
      filter expr(id == ^arg(:id) and room == ^arg(:room))
      prepare build(load: [:liked_by_me | @shown])
    end

    # Messages in any room that hold `text`, in any case, newest first.
    read :search do
      argument :text, :string, allow_nil?: false, constraints: [min_length: 2, max_length: 100]
      filter expr(contains(string_downcase(body), string_downcase(^arg(:text))))
      prepare LeaveOutMuted
      prepare build(sort: [inserted_at: :desc, id: :desc], limit: 5, load: [:in_room, :author])
    end

    # The message this actor already posted in this room with this operation_id,
    # so a retry answers the first post.
    read :earlier_post do
      get? true
      argument :room, :string, allow_nil?: false
      argument :operation_id, :uuid, allow_nil?: false
      filter expr(id == ^arg(:operation_id) and room == ^arg(:room))
      prepare PostedByActor
      prepare build(load: @shown)
    end

    create :post do
      accept [:room, :body]
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
      change SetAuthor
      change SquashBlankLines

      change {LimitWrites,
              allowance: :room_post, address_allowance: :room_post_address, field: :body}

      emit AshTemplate.Rooms.Signals, :message_posted, fields: [message_id: :id]
      change load(@shown)
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
      change load(@shown)
    end
  end

  # A post checks the pairing of an agent that posts as its person in `SetAuthor`.
  changes do
    change {RegentAgents.RequirePairing, repo: AshTemplate.Repo}, on: [:update, :destroy]
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
      authorize_if actor_attribute_equals(:role, :human)
      authorize_if {RegentAgents.Checks.Paired, repo: AshTemplate.Repo}
    end

    policy action_type([:update, :destroy]) do
      authorize_if expr(human_account_id == ^actor(:human_account_id))
    end
  end

  # Delivered after the transaction commits to `topic/1` of the message's room:
  # %{event: "post" | "edit", payload: public(message)}, or %{event: "destroy",
  # payload: %{id: id, room: room}}; posts and deletes to `every_room_topic/0` too. `edited_at` is the order marker: the
  # database sets it on every edit, and a page keeps the newer. Post and edit
  # load what `public/1` reads themselves, so no publication reads it again.
  pub_sub do
    module Phoenix.PubSub
    name AshTemplate.PubSub
    prefix "public"
    broadcast_type :broadcast

    publish :post, ["room", :room], returns: :map, transform: &__MODULE__.public(&1.data)
    publish :edit, ["room", :room], returns: :map, transform: &__MODULE__.public(&1.data)

    publish :destroy, ["room", :room],
      returns: :map,
      transform: &%{id: &1.data.id, room: &1.data.room}

    publish :post, ["room_messages"], returns: :map, transform: &__MODULE__.public(&1.data)

    publish :destroy, ["room_messages"],
      returns: :map,
      transform: &%{id: &1.data.id, room: &1.data.room}
  end

  @doc "The topic every post, edit and delete in `room`, a room's slug, is published on."
  def topic(room), do: "public:room:#{room}"

  @doc "The topic every post and delete in every room is published on."
  def every_room_topic, do: "public:room_messages"

  @doc """
  What a signed-out reader may see of a message, named one by one: what a room's
  page shows and what its topic carries. `backed_agents` is how many agents the
  World ID person behind the writing agent backs, `nil` when nobody does.
  `like_count` is how many people like it.
  `author` is how the page shows its author: their name, or their wallet and ENS
  name, and their picture (`AshTemplate.Rooms.Author`). What `@shown` names must
  be loaded, as every room read and write loads it.
  """
  def public(message) do
    %{
      id: message.id,
      room: message.room,
      body: message.body,
      human_account_id: message.human_account_id,
      agent_id: message.agent_id,
      via_agent_id: message.via_agent_id,
      inserted_at: message.inserted_at,
      edited_at: message.edited_at,
      like_count: message.like_count,
      backed_agents: message.agent && message.agent.world_id_agent_count,
      via_agent_name: message.via_agent && message.via_agent.name,
      author: message.author
    }
  end
end
