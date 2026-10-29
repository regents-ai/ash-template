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

  alias AshTemplate.Agents.NotPaired
  alias AshTemplate.Limits.LimitWrites
  alias AshTemplate.Rooms

  alias AshTemplate.Rooms.Message.{
    AgentPost,
    AuthorPicture,
    ByAuthorKind,
    LeaveOutMuted,
    RoomMessages,
    SetAuthor,
    SquashBlankLines
  }

  alias AshTemplate.Rooms.{Like, Mute, Refused, Room}

  @room "The room's name, as rooms_list gives it, such as general."
  @message_id "The message's id, from rooms_messages."

  # What every room read and write loads for `public/1`.
  @shown [:agent, :via_agent, :author_picture, :like_count]

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

    # The author's display name, or their short wallet address, when they posted.
    # Other people's accounts are private, so the name is kept with the message.
    # An agent's is its profile name, or "Unnamed agent"; never its wallet.
    attribute :author_name, :string, allow_nil?: false, public?: true
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
    calculate :author_picture, :map, AuthorPicture
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
      prepare build(sort: [inserted_at: :desc, id: :desc], limit: 5, load: [:in_room])
    end

    # A page of a room's messages, as every surface answers it (`RoomMessages`).
    action :room_messages, :map do
      argument :room, :string,
        allow_nil?: false,
        description: "The room's name, as rooms_list gives it, such as general."

      argument :author_kind, :atom,
        constraints: [one_of: [:person, :agent]],
        description:
          "person for people's messages (with what their agents wrote for them), agent for agents' own. Leave it out for everyone's."

      argument :limit, :integer,
        constraints: [min: 1, max: 50],
        description: "Messages a page, 1 to 50; 50 when left out."

      argument :after, :string,
        constraints: [max_length: 2048],
        description: "The previous page's pagination.next_cursor, for older messages."

      run RoomMessages
    end

    # An agent's post, its operation_id spent once, as every surface answers it
    # (`AgentPost`).
    action :agent_post, :map do
      argument :room, :string,
        allow_nil?: false,
        description: "The room's name, as rooms_list gives it, such as general."

      argument :body, :string,
        allow_nil?: false,
        constraints: [max_length: 2000],
        description: "The message, 1 to 2,000 characters."

      argument :operation_id, :uuid,
        allow_nil?: false,
        description:
          "A UUID you make for this message. Keep it when retrying: a retry answers the first post, and a UUID already used for another message is refused."

      run AgentPost
    end

    # One message of a room by its id, as its room shows a signed-out reader,
    # whoever asks.
    action :rooms_message, :map do
      argument :room, :string, allow_nil?: false, description: @room
      argument :id, :uuid, allow_nil?: false, description: @message_id

      run fn %{arguments: %{room: slug, id: id}}, _context ->
        with {:ok, message} <- AshTemplate.Rooms.Message.in_room(slug, id, nil),
             do: {:ok, %{message: AshTemplate.Rooms.Message.present(message)}}
      end
    end

    # The agent's person's own message, changed or deleted; any other reads as
    # absent (`mine/3`).
    action :rooms_edit, :map do
      argument :room, :string, allow_nil?: false, description: @room
      argument :id, :uuid, allow_nil?: false, description: @message_id

      argument :body, :string,
        allow_nil?: false,
        constraints: [max_length: 2000],
        description: "The new text, 1 to 2,000 characters."

      run fn %{arguments: %{room: slug, id: id, body: body}}, %{actor: actor} ->
        with {:ok, message} <- AshTemplate.Rooms.Message.mine(slug, id, actor) do
          case Rooms.edit_message(message, %{body: body}, actor: actor) do
            {:ok, message} ->
              {:ok, %{message: AshTemplate.Rooms.Message.present(message)}}

            {:error, %Ash.Error.Invalid{} = error} ->
              {:error, Refused.exception(code: "invalid_message", error: error)}

            error ->
              NotPaired.ended(error, actor)
          end
        end
      end
    end

    action :rooms_delete, :map do
      argument :room, :string, allow_nil?: false, description: @room
      argument :id, :uuid, allow_nil?: false, description: @message_id

      run fn %{arguments: %{room: slug, id: id}}, %{actor: actor} ->
        with {:ok, message} <- AshTemplate.Rooms.Message.mine(slug, id, actor),
             :ok <- NotPaired.ended(Rooms.delete_message(message, actor: actor), actor),
             do: {:ok, %{deleted: true, id: message.id}}
      end
    end

    # A like, and a like taken back, answer the message as it stands and whether
    # the agent's person likes it now. Liking twice, or taking back a like never
    # given, changes nothing.
    action :rooms_like, :map do
      argument :room, :string, allow_nil?: false, description: @room
      argument :id, :uuid, allow_nil?: false, description: @message_id

      run fn %{arguments: %{room: slug, id: id}}, %{actor: actor} ->
        with :ok <- NotPaired.check(actor),
             {:ok, message} <- AshTemplate.Rooms.Message.in_room(slug, id, actor) do
          case Rooms.like_message(message.id, actor: actor) do
            {:ok, _like} ->
              AshTemplate.Rooms.Message.liked(message, actor)

            # The message was deleted since it was read.
            {:error, %Ash.Error.Invalid{}} ->
              {:error, Refused.exception(code: "public_message_not_found")}

            error ->
              NotPaired.ended(error, actor)
          end
        end
      end
    end

    action :rooms_unlike, :map do
      argument :room, :string, allow_nil?: false, description: @room
      argument :id, :uuid, allow_nil?: false, description: @message_id

      run fn %{arguments: %{room: slug, id: id}}, %{actor: actor} ->
        with :ok <- NotPaired.check(actor),
             {:ok, message} <- AshTemplate.Rooms.Message.in_room(slug, id, actor),
             {:ok, like} <- NotPaired.ended(Rooms.get_my_like(message.id, actor: actor), actor),
             :ok <- AshTemplate.Rooms.Message.take_back(like, actor),
             do: AshTemplate.Rooms.Message.liked(message, actor)
      end
    end

    # Reporting a message again answers the first report, with its first reason.
    action :rooms_report, :map do
      argument :room, :string, allow_nil?: false, description: @room
      argument :id, :uuid, allow_nil?: false, description: @message_id

      argument :reason, AshTemplate.Rooms.Report.Reason,
        allow_nil?: false,
        description: "Why: spam, abuse, steers_agents (text that tries to steer agents) or other."

      run fn %{arguments: %{room: slug, id: id, reason: reason}}, %{actor: actor} ->
        with :ok <- NotPaired.check(actor),
             {:ok, message} <- AshTemplate.Rooms.Message.in_room(slug, id, actor) do
          case Rooms.report_message(message.id, reason, actor: actor) do
            {:ok, report} ->
              {:ok, %{report: AshTemplate.Rooms.Report.public(report)}}

            {:error, %Ash.Error.Invalid{} = error} ->
              {:error, Refused.exception(code: "invalid_report", error: error)}

            error ->
              NotPaired.ended(error, actor)
          end
        end
      end
    end

    # Up to 5 messages from every room that hold `text`, newest first, for an
    # agent acting for its person.
    action :rooms_search, :map do
      argument :text, :string,
        allow_nil?: false,
        constraints: [min_length: 2, max_length: 100],
        description: "Words to look for, 2 to 100 characters, in any case."

      run fn %{arguments: %{text: text}}, %{actor: actor} ->
        with :ok <- NotPaired.check(actor),
             {:ok, messages} <- Rooms.search_messages(text, actor: actor) do
          {:ok,
           %{
             messages:
               Enum.map(
                 messages,
                 &Map.take(&1, [:id, :room, :body, :author_name, :inserted_at, :edited_at])
               )
           }}
        end
      end
    end

    create :post do
      accept [:room, :body]
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

    # Anyone reads a room, except an app connected to a person's account: its
    # token is for its identity tools alone (`AshTemplate.Agents.Connection`).
    policy action(:room_messages) do
      forbid_if actor_attribute_equals(:role, :connected_app)
      authorize_if always()
    end

    policy action(:post) do
      authorize_if actor_attribute_equals(:role, :human)
      authorize_if actor_attribute_equals(:role, :agent)
    end

    policy action(:agent_post) do
      authorize_if actor_attribute_equals(:role, :human)
      authorize_if actor_attribute_equals(:role, :agent)
    end

    # Changing, liking and reporting act for the agent's person, or as the account
    # it owns: an agent that does neither is told why (`NotPaired`).
    policy action([:rooms_edit, :rooms_delete, :rooms_like, :rooms_unlike, :rooms_report]) do
      authorize_if actor_attribute_equals(:role, :human)
      authorize_if actor_attribute_equals(:role, :agent)
    end

    policy action(:rooms_message) do
      forbid_if actor_attribute_equals(:role, :connected_app)
      authorize_if always()
    end

    # Search acts for the agent's person, or as the account it owns: an agent that
    # does neither is told why (`NotPaired`).
    policy action(:rooms_search) do
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
  `author_squares` and `author_picture` are the picture the author's account
  shows (`AuthorPicture`). What `@shown` names must be loaded, as every room
  read and write loads it.
  """
  def public(message) do
    %{
      id: message.id,
      room: message.room,
      body: message.body,
      author_name: message.author_name,
      human_account_id: message.human_account_id,
      agent_id: message.agent_id,
      via_agent_id: message.via_agent_id,
      inserted_at: message.inserted_at,
      edited_at: message.edited_at,
      like_count: message.like_count,
      backed_agents: message.agent && message.agent.world_id_agent_count,
      via_agent_name: message.via_agent && message.via_agent.name,
      author_squares: message.author_picture.squares,
      author_picture: message.author_picture.picture
    }
  end

  @doc """
  A message as the rooms API, the agent tools and the CLI answer it: its author
  as `author_kind`, the agent a person paired that wrote it (`via_agent`, by its
  profile name, never its wallet) and whether a person verified with World ID
  stands behind the agent that wrote it. What `@shown` names must be loaded.
  """
  def present(message) do
    %{
      id: message.id,
      room: message.room,
      author_name: message.author_name,
      author_kind: if(message.agent_id, do: "agent", else: "person"),
      agent_id: message.agent_id,
      author_human_backed: human_backed?(message),
      via_agent: message.via_agent && %{id: message.via_agent.id, name: message.via_agent.name},
      body: message.body,
      like_count: message.like_count,
      inserted_at: message.inserted_at,
      edited_at: message.edited_at
    }
  end

  @doc """
  The message `id` of the room `slug`, as the room shows `actor`: `room_not_found`
  or `public_message_not_found` when there is none.
  """
  def in_room(slug, id, actor) do
    with {:ok, room} <- Room.named(slug) do
      case Rooms.get_room_message(room.slug, id, actor: actor) do
        {:ok, nil} -> {:error, Refused.exception(code: "public_message_not_found")}
        result -> result
      end
    end
  end

  @doc """
  The message `id` of the room `slug` that the actor's person wrote, or that an
  agent wrote as them; any other, or none, is `message_not_found`.
  """
  def mine(slug, id, actor) do
    with :ok <- NotPaired.check(actor),
         {:ok, room} <- Room.named(slug) do
      case Rooms.get_message(id, actor: actor) do
        {:ok, %__MODULE__{room: room_slug, human_account_id: author} = message}
        when room_slug == room.slug and author == actor.human_account_id ->
          {:ok, message}

        {:ok, _absent} ->
          {:error, Refused.exception(code: "message_not_found")}

        error ->
          error
      end
    end
  end

  @doc "The message as it stands after a like or one taken back, and whether `actor`'s person likes it."
  def liked(message, actor) do
    with {:ok, message} <- in_room(message.room, message.id, actor),
         do: {:ok, %{message: present(message), liked: message.liked_by_me}}
  end

  @doc "Takes back `like`, `actor`'s person's like, when they gave one."
  def take_back(nil, _actor), do: :ok
  def take_back(like, actor), do: NotPaired.ended(Rooms.unlike(like, actor: actor), actor)

  defp human_backed?(%{agent: %{world_id_human_id: id}}), do: is_binary(id)
  defp human_backed?(_message), do: false
end
