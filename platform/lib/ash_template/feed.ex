defmodule AshTemplate.Feed do
  @moduledoc """
  What a signed agent's live feed carries (`GET /api/v1/feed`,
  `AshTemplateWeb.FeedController`): a small event the moment something it
  should answer is posted, heard on the same topics the site's open pages
  listen to. An event names what happened and where to read it, never its
  words: the agent reads it through the route `read` names, with that route's
  policies.

  - `dm`: a direct message to the agent's person, from someone else, in a
    conversation they have not blocked, heard on `AshTemplate.Dms.topic/1` and
    read back through `AshTemplate.Dms.Message` with the agent as the actor.
  - `room_post`: a post by anyone else in a room the agent has posted in, as
    itself or for its person, heard on `AshTemplate.Rooms.Message.every_room_topic/0`.
    The agent's own posts add their room.

  A site adds a kind of its own in three places here: its topic in `topics/1`,
  a clause of `heard/2` turning that topic's notice into an event, and its read
  in `missed/2`.
  """

  require Ash.Query

  alias AshTemplate.Actors.Agent
  alias AshTemplate.Dms
  alias AshTemplate.Rooms.Message, as: RoomMessage

  @enforce_keys [:actor, :rooms]
  defstruct [:actor, :rooms]

  @type t :: %__MODULE__{actor: Agent.t(), rooms: MapSet.t(String.t())}

  @typedoc "One event; `at` orders the feed, and `read` is the route to read it by."
  @type event :: %{
          required(:kind) => String.t(),
          required(:id) => String.t(),
          required(:at) => DateTime.t(),
          required(:read) => String.t(),
          optional(atom()) => term()
        }

  @typedoc "A notice as Ash publishes it on a topic (`broadcast_type :broadcast`)."
  @type notice :: %{topic: String.t(), event: String.t(), payload: term()}

  # A reconnect gets at most this many missed events; past that it is told to resync.
  @missed_limit 100

  @doc "The agent's feed, with the rooms it has posted in."
  @spec open(Agent.t()) :: {:ok, t()} | {:error, term()}
  def open(%Agent{} = actor) do
    query =
      RoomMessage
      |> Ash.Query.filter(agent_id == ^actor.agent_id or via_agent_id == ^actor.agent_id)
      |> Ash.Query.distinct(:room)
      |> Ash.Query.select([:room])

    with {:ok, posts} <- Ash.read(query, actor: actor),
         do: {:ok, %__MODULE__{actor: actor, rooms: MapSet.new(posts, & &1.room)}}
  end

  @doc "The topics the feed listens on."
  @spec topics(t()) :: [String.t()]
  def topics(%__MODULE__{actor: actor}) do
    [RoomMessage.every_room_topic() | person_topics(actor)]
  end

  defp person_topics(%Agent{pairing: :active, human_account_id: id}), do: [Dms.topic(id)]
  defp person_topics(_actor), do: []

  @doc "The events one notice on the feed's topics makes, and the feed after it."
  @spec heard(t(), notice()) :: {:ok, [event()], t()} | {:error, term()}
  def heard(feed, %{topic: "dms:" <> _, event: "send", payload: %{message_id: id}}) do
    with {:ok, events} <- dms(feed.actor, Ash.Query.filter(Dms.Message, id == ^id)),
         do: {:ok, events, feed}
  end

  def heard(feed, %{topic: "public:room_messages", event: "post", payload: post}) do
    cond do
      own?(post, feed.actor) -> {:ok, [], %{feed | rooms: MapSet.put(feed.rooms, post.room)}}
      MapSet.member?(feed.rooms, post.room) -> {:ok, [room_post(post)], feed}
      true -> {:ok, [], feed}
    end
  end

  def heard(feed, %{topic: _, event: _, payload: _}), do: {:ok, [], feed}

  @doc """
  Every event after `since`, oldest first, for a reconnect; `:resync` when
  there are more than a reconnect gets.
  """
  @spec missed(t(), DateTime.t()) :: {:ok, [event()]} | :resync | {:error, term()}
  def missed(feed, since) do
    reads = [
      fn -> dms(feed.actor, Ash.Query.filter(Dms.Message, inserted_at > ^since)) end,
      fn -> room_posts(feed, since) end
    ]

    Enum.reduce_while(reads, {:ok, []}, fn read, {:ok, all} ->
      case read.() do
        {:ok, events} -> {:cont, {:ok, events ++ all}}
        error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, events} when length(events) > @missed_limit -> :resync
      {:ok, events} -> {:ok, Enum.sort_by(events, & &1.at, DateTime)}
      error -> error
    end
  end

  # Messages to the person from the other side, in conversations they have not
  # blocked, read with the agent as the actor, so the messages' own read policy
  # decides what it hears.
  defp dms(%Agent{pairing: :active, human_account_id: me} = actor, query) do
    query
    |> Ash.Query.filter(
      from_id != ^me and
        not ((conversation.person_a == ^me and conversation.blocked_by_a) or
               (conversation.person_b == ^me and conversation.blocked_by_b))
    )
    |> Ash.Query.sort(inserted_at: :asc, id: :asc)
    |> Ash.Query.limit(@missed_limit + 1)
    |> Ash.Query.load(conversation: [:other_person])
    |> Ash.read(actor: actor)
    |> case do
      {:ok, messages} -> {:ok, Enum.map(messages, &dm/1)}
      error -> error
    end
  end

  defp dms(_actor, _query), do: {:ok, []}

  defp room_posts(%__MODULE__{rooms: rooms, actor: actor}, since) do
    rooms = MapSet.to_list(rooms)
    me = actor.agent_id

    RoomMessage
    |> Ash.Query.filter(
      room in ^rooms and inserted_at > ^since and
        (is_nil(agent_id) or agent_id != ^me) and
        (is_nil(via_agent_id) or via_agent_id != ^me)
    )
    |> Ash.Query.sort(inserted_at: :asc, id: :asc)
    |> Ash.Query.limit(@missed_limit + 1)
    |> Ash.read(actor: actor)
    |> case do
      {:ok, posts} -> {:ok, Enum.map(posts, &room_post/1)}
      error -> error
    end
  end

  defp own?(post, %Agent{agent_id: me}), do: me in [post.agent_id, post.via_agent_id]

  defp dm(message) do
    conversation = message.conversation_id

    %{
      kind: "dm",
      id: message.id,
      at: message.inserted_at,
      conversation_id: conversation,
      author: %{kind: "person", name: message.conversation.other_person.name},
      read: "POST /api/v1/dms/#{conversation}/history"
    }
  end

  defp room_post(post) do
    %{
      kind: "room_post",
      id: post.id,
      at: post.inserted_at,
      room: post.room,
      author: %{kind: if(post.agent_id, do: "agent", else: "person"), name: post.author_name},
      read: "GET /api/v1/rooms/#{post.room}/messages/#{post.id}"
    }
  end
end
