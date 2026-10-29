defmodule AshTemplate.Rooms.Room do
  @moduledoc """
  A room anyone can read. The site's own rooms, General and Help, are rows the
  migration that made this table wrote, and nobody started them. A signed-in
  person, or an agent they paired acting for them, starts another with a name
  and a topic, a few a day at most (`:room` in `AshTemplate.Limits`). Its slug,
  the name in its address, comes from its name and never changes, so no two
  rooms share an address. Only the person who started a room changes its topic.

  Every new room and every topic change is published on `topic/0`, so each open
  room page shows the room list and the topic as they stand. What is published
  is `public/1`, never the record.
  """

  use Ash.Resource,
    domain: AshTemplate.Rooms,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    notifiers: [Ash.Notifier.PubSub]

  alias AshTemplate.Rooms.Room.SlugFromName

  @shown_text "Use letters, numbers and marks you can see."
  @name_taken "A room with this name is already here."

  postgres do
    table "rooms"
    repo(AshTemplate.Repo)

    # A second room whose name gives the same slug is refused by the primary
    # key, and the refusal is shown under the name.
    unique_index_names([{[:name], "rooms_pkey", @name_taken}])
  end

  attributes do
    attribute :slug, :string, primary_key?: true, allow_nil?: false, public?: true
    attribute :name, :string, allow_nil?: false, public?: true, constraints: [max_length: 40]
    attribute :topic, :string, allow_nil?: false, public?: true, constraints: [max_length: 200]
    create_timestamp :inserted_at, public?: true
  end

  relationships do
    # Who started the room; nobody for the site's own rooms.
    belongs_to :created_by, AshTemplate.Accounts.HumanAccount do
      attribute_type :integer
    end
  end

  actions do
    defaults [:read]

    # The site's own rooms first, then the rest in the order they were started.
    read :list do
      prepare build(sort: [inserted_at: :asc, slug: :asc])
    end

    # The room the actor's person started with this slug, so a retry answers it.
    read :started_by_actor do
      get? true
      argument :slug, :string, allow_nil?: false
      filter expr(slug == ^arg(:slug) and created_by_id == ^actor(:human_account_id))
    end

    # Rooms whose name holds `text`, in any case.
    read :search do
      argument :text, :string, allow_nil?: false, constraints: [min_length: 2, max_length: 100]
      filter expr(contains(string_downcase(name), string_downcase(^arg(:text))))
      prepare build(sort: [inserted_at: :asc], limit: 5)
    end

    create :create do
      primary? true
      accept [:name, :topic]
      change {RegentAgents.RequirePairing, repo: AshTemplate.Repo}
      validate match(:name, RegentFormat.Name.pattern()), message: @shown_text
      validate match(:topic, RegentFormat.Name.pattern()), message: @shown_text
      change SlugFromName
      change set_attribute(:created_by_id, actor(:human_account_id))

      change {AshTemplate.Limits.LimitWrites,
              allowance: :room,
              field: :name,
              message: "You've started as many rooms as you can today. Start another tomorrow."}
    end

    # The rooms as every surface lists them (`public/1`).
    action :rooms_list, :map do
      run fn _input, _context ->
        with {:ok, rooms} <- AshTemplate.Rooms.list_rooms(),
             do: {:ok, %{rooms: Enum.map(rooms, &public/1)}}
      end
    end

    update :set_topic do
      accept [:topic]
      require_atomic? false
      change {RegentAgents.RequirePairing, repo: AshTemplate.Repo}
      validate match(:topic, RegentFormat.Name.pattern()), message: @shown_text
    end
  end

  policies do
    policy action_type(:read) do
      authorize_if always()
    end

    # Anyone lists the rooms, except an app connected to a person's account: its
    # token is for its identity tools alone (`AshTemplate.Agents.Connection`).
    policy action(:rooms_list) do
      forbid_if actor_attribute_equals(:role, :connected_app)
      authorize_if always()
    end

    policy action_type([:create, :update]) do
      authorize_if actor_attribute_equals(:role, :human)
      authorize_if {RegentAgents.Checks.Paired, repo: AshTemplate.Repo}
    end

    policy action(:set_topic) do
      authorize_if expr(created_by_id == ^actor(:human_account_id))
    end
  end

  # Delivered after the transaction commits to `topic/0`: %{event: "create" |
  # "set_topic", payload: public(room)}.
  pub_sub do
    module Phoenix.PubSub
    name AshTemplate.PubSub
    prefix "public"
    broadcast_type :broadcast

    publish :create, ["rooms"], returns: :map, transform: &__MODULE__.public(&1.data)
    publish :set_topic, ["rooms"], returns: :map, transform: &__MODULE__.public(&1.data)
  end

  @doc "The topic every new room and topic change is published on."
  def topic, do: "public:rooms"

  @doc "What anyone may see of a room: its address, its name and its topic."
  def public(room), do: %{slug: room.slug, name: room.name, topic: room.topic}

  @doc "Whether a refused start was refused because another room has its address."
  def name_taken?(%Ash.Error.Invalid{errors: errors}),
    do: Enum.any?(errors, &match?(%{field: :name, message: @name_taken}, &1))

  @doc ~S"""
  The slug a room named `name` gets: letters from A to Z and digits, each run of
  anything else one hyphen, at most 40 characters.

      iex> AshTemplate.Rooms.Room.slug("  Café Pictures!! ")
      "cafe-pictures"
  """
  def slug(name) when is_binary(name) do
    name
    |> String.normalize(:nfkd)
    |> String.replace(~r/\p{Mn}/u, "")
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/, "-")
    |> String.trim("-")
    |> String.slice(0, 40)
    |> String.trim_trailing("-")
  end
end
