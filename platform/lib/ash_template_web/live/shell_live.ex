defmodule AshTemplateWeb.ShellLive do
  @moduledoc """
  One LiveView holds the frame (`AshTemplateWeb.Components.Shell`) across every
  in-app route and patches between them, so the frame never remounts on
  navigation. Besides the page, it keeps the frame's own parts current: the
  account menu's agents, the bell's unread count, the background jobs running,
  and search.
  """

  use AshTemplateWeb, :live_view

  import AshTemplateWeb.Components.Shell

  alias AshTemplate.{Accounts, Activity, Chat, Dms, Notes, Polls, Rooms, SharedReading}
  alias AshTemplate.Accounts.LinkedIdentity.Providers
  alias AshTemplate.Activity.Notification
  alias AshTemplate.Actors.Human
  alias AshTemplate.Notes.Note
  alias AshTemplate.Points.Board
  alias AshTemplate.PublicIdentity
  alias AshTemplate.Rooms.{Message, Mute, Room}

  alias AshTemplateWeb.{
    AccountLive,
    ActivityLive,
    AgentsPanel,
    ChatLive,
    DesignLive,
    DmsLive,
    MenuAgents,
    NotesLive,
    NotFoundError,
    OverviewLive,
    PairingBox,
    PairLive,
    PollsLive,
    Presence,
    PublicDocuments,
    Read,
    RoomsLive,
    RouteCatalog,
    Showcase
  }

  @actions %{"link" => :link, "unlink" => :unlink}
  @refused %{
    tone: :error,
    message: "That connection couldn’t be updated. Refresh the page and try again."
  }

  @kinds %{"Pages" => :page, "Actions" => :action}

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: subscribe_to_own_topics(socket.assigns.access_context)

    {:ok,
     socket
     |> assign(
       shell_instance: System.unique_integer([:positive, :monotonic]),
       room: nil,
       people: [],
       conversation: nil,
       dm: nil,
       poll_id: nil,
       hearing_polls?: false,
       hearing_board?: false,
       pair_start: nil,
       verified_connections: %Read{},
       points: %Read{},
       points_bonus: %Read{},
       points_board: %Read{},
       points_earning: [],
       verified_connections_notice: nil,
       notifications: %Read{},
       mark_read_failed?: false,
       healthy: AshTemplate.Health.database_ready?(),
       search: unsearched()
     )
     |> count_unread()}
  end

  @impl true
  def handle_params(params, uri, socket) do
    action = socket.assigns.live_action
    open!(action)
    room = room_in(action, params)
    conversation = conversation_in(action, params, human_actor(socket))
    dm = dm_in(action, params, human_actor(socket))
    poll_id = poll_in(action, params)
    route_spec = RouteCatalog.fetch!(action, params)

    {:noreply,
     socket
     |> assign(page_meta(room, page_path(action, uri)))
     |> assign(:route_spec, route_spec)
     |> assign(:pair_start, PairLive.start(params))
     |> hear_board(route_spec)
     |> load_points(route_spec)
     |> load_verified_connections(route_spec)
     |> load_notifications(route_spec)
     |> assign(search: unsearched(), mark_read_failed?: false)
     |> enter_room(room)
     |> open_conversation(conversation)
     |> assign(:dm, dm)
     |> hear_polls(route_spec)
     |> assign(:poll_id, poll_id)}
  end

  @impl true
  def handle_event(
        "request_verified_connection",
        %{"action" => action, "provider" => provider},
        socket
      ) do
    with %Human{} <- human_actor(socket),
         {:ok, provider} <- Providers.parse(provider),
         {:ok, action} <- Map.fetch(@actions, action),
         {:ok, request} <-
           identity_request(action, provider, socket.assigns.verified_connections.value) do
      {:noreply,
       socket
       |> assign(
         verified_connections_notice: %{tone: :info, message: connection_started(request)}
       )
       |> push_event("verified-connections:request", request)}
    else
      _refused -> {:noreply, assign(socket, verified_connections_notice: @refused)}
    end
  end

  # The outcome is judged against the connections read after the provider came back.
  def handle_event("refresh_verified_connections", params, socket) do
    socket = read_verified_connections(socket)
    notice = connection_outcome(params, socket.assigns.verified_connections)
    {:noreply, assign(socket, verified_connections_notice: notice)}
  end

  # The Account page saved the person's name in the shared profile. Every event
  # reads the account again first (`AshTemplateWeb.Live.Session`), so the page
  # already shows the new name everywhere it appears.
  def handle_event("public_name_saved", _params, socket), do: {:noreply, socket}

  def handle_event("mark_all_read", _params, socket) do
    failed? =
      case human_actor(socket) do
        %Human{} = actor -> Activity.mark_all_read(actor: actor).status != :success
        nil -> false
      end

    {:noreply, assign(socket, mark_read_failed?: failed?)}
  end

  # A search of the saved notes and messages spends the address's search
  # allowance; past it, the last results stay.
  def handle_event("search", %{"q" => query}, socket) do
    query = String.trim(query)

    if query == "" or AshTemplate.Limits.spend(:search_address, socket.assigns.client_key) == :ok,
      do:
        {:noreply,
         assign(socket, :search, %{query: query, results: search(query, human_actor(socket))})},
      else: {:noreply, socket}
  end

  @impl true
  def handle_async({Read, _name, _generation} = name, result, socket) do
    {:noreply, Read.settle(socket, name, result)}
  end

  # Note changes are published on the writer's own topic; only the notes page
  # shows them, so on any other page they are dropped.
  @impl true
  def handle_info(%{topic: "notes:" <> _, event: event, payload: note}, socket) do
    if socket.assigns.route_spec.route_id == :notes,
      do: send_update(NotesLive, id: "notes", change: {event, note})

    {:noreply, socket}
  end

  # A notification arriving or being read anywhere recounts the bell, and
  # reads the Activity page again when it is open.
  def handle_info(%{topic: "notifications:" <> _}, socket) do
    {:noreply, socket |> count_unread() |> load_notifications(socket.assigns.route_spec)}
  end

  # A points award or correction landed for this account; the Points page follows.
  def handle_info(
        %{topic: "points:" <> _},
        %{assigns: %{route_spec: %{route_id: :points}}} = socket
      ),
      do: {:noreply, read_points(socket)}

  def handle_info(%{topic: "points:" <> _}, socket), do: {:noreply, socket}

  # The board every signed-in reader shares was read again.
  def handle_info(
        {:shared_reading, {:points_board, _program}},
        %{assigns: %{route_spec: %{route_id: :points}}} = socket
      ),
      do: {:noreply, read_points_board(socket)}

  def handle_info({:shared_reading, {:points_board, _program}}, socket), do: {:noreply, socket}

  # An agent paired, checked in or was unpaired, here or on another Regent site.
  # The account menu's agents and the pairing window are on every page; the
  # Agents page also lists the agents.
  def handle_info(:agents_changed, socket) do
    send_update(MenuAgents, id: "shell-agents", agents_changed: true)
    send_update(PairingBox, id: "shell-pairing-box", agents_changed: true)

    if socket.assigns.route_spec.route_id == :account_agents,
      do: send_update(AgentsPanel, id: "account-agents", agents_changed: true)

    if socket.assigns.route_spec.route_id == :pair,
      do: send_update(PairingBox, id: "pair-pairing-box", agents_changed: true)

    {:noreply, socket}
  end

  # A room's posts, edits and deletes reach only the room on screen, so one
  # still in the mailbox from the room just left is dropped.
  def handle_info(%{topic: "public:room:" <> _, event: event, payload: message}, socket) do
    if on_room?(socket, message.room),
      do: send_update(RoomsLive, id: "rooms", change: {event, message})

    {:noreply, socket}
  end

  # A room started or a topic changed anywhere reaches the room page on screen,
  # which keeps its list of rooms and its topic current.
  def handle_info(%{topic: "public:rooms", event: event, payload: room}, socket) do
    if socket.assigns.room,
      do: send_update(RoomsLive, id: "rooms", room_change: {event, room})

    {:noreply, socket}
  end

  def handle_info(%{topic: "room_people:" <> room, event: "presence_diff"}, socket) do
    if on_room?(socket, room),
      do: {:noreply, assign(socket, :people, Presence.people(room))},
      else: {:noreply, socket}
  end

  # Muting or unmuting on any of the person's pages changes what each of their
  # rooms shows.
  def handle_info(%{topic: "mutes:" <> _}, socket) do
    if socket.assigns.room, do: send_update(RoomsLive, id: "rooms", mutes_changed: true)
    {:noreply, socket}
  end

  # The person's own message, the assistant's reply as it starts and ends, and
  # each piece of the reply in between reach only the conversation on screen.
  def handle_info(%{topic: "chat:messages:" <> id, event: "piece", payload: piece}, socket) do
    if on_conversation?(socket, id), do: send_update(ChatLive, id: "chat", piece: piece)
    {:noreply, socket}
  end

  def handle_info(%{topic: "chat:messages:" <> id, payload: message}, socket) do
    if on_conversation?(socket, id),
      do: send_update(ChatLive, id: "chat", change: message)

    {:noreply, socket}
  end

  # A conversation started or named on any of the person's pages joins their
  # list, and renames the one on screen.
  def handle_info(%{topic: "chat:conversations:" <> _, payload: conversation}, socket) do
    if socket.assigns.route_spec.route_id == :chat,
      do: send_update(ChatLive, id: "chat", conversation_change: conversation)

    if on_conversation?(socket, conversation.id),
      do: {:noreply, assign(socket, :conversation, conversation)},
      else: {:noreply, socket}
  end

  # A direct message or a block in one of the person's conversations reaches
  # the messages page; a block also reads the open conversation again.
  def handle_info(%{topic: "dms:" <> _, event: event, payload: payload}, socket) do
    if socket.assigns.route_spec.route_id == :dms,
      do: send_update(DmsLive, id: "dms", change: {event, payload})

    if event != "send" and on_dm?(socket, payload.conversation_id),
      do: {:noreply, assign(socket, :dm, read_dm(payload.conversation_id, human_actor(socket)))},
      else: {:noreply, socket}
  end

  # A start, vote or end anywhere reaches the polls page on screen.
  def handle_info(%{topic: "public:polls", payload: %{poll_id: id}}, socket) do
    if socket.assigns.route_spec.route_id == :polls,
      do: send_update(PollsLive, id: "polls", change: id)

    {:noreply, socket}
  end

  @doc "The search box before anything is typed: every page and action, as suggestions."
  def unsearched, do: %{query: "", results: search("", nil)}

  @impl true
  def render(assigns) do
    ~H"""
    <.shell
      route_spec={@route_spec}
      account_control={@account_control}
      shell_instance={@shell_instance}
      unread={@unread}
      healthy={@healthy}
      search={@search}
    >
      <:agents :if={current_account(@access_context)}>
        <.live_component
          module={MenuAgents}
          id="shell-agents"
          lease={@session_lease}
          account={current_account(@access_context)}
        />
      </:agents>
      <:pairing_panel :if={current_account(@access_context)}>
        <.live_component
          module={PairingBox}
          id="shell-pairing-box"
          lease={@session_lease}
          account={current_account(@access_context)}
        />
      </:pairing_panel>
      <:content>
        <OverviewLive.page
          :if={@route_spec.route_id == :app}
          account_control={@account_control}
          account={current_account(@access_context)}
          lease={@session_lease}
          client_key={@client_key}
        />

        <ActivityLive.page
          :if={@route_spec.route_id == :activity}
          account={current_account(@access_context)}
          notifications={@notifications}
          mark_read_failed?={@mark_read_failed?}
        />

        <.live_component
          :if={@route_spec.route_id == :notes}
          module={NotesLive}
          id="notes"
          lease={@session_lease}
          account={current_account(@access_context)}
        />

        <.live_component
          :if={@route_spec.route_id == :room}
          module={RoomsLive}
          id="rooms"
          lease={@session_lease}
          account={current_account(@access_context)}
          room={@room}
          people={@people}
          client_key={@client_key}
        />

        <.live_component
          :if={@route_spec.route_id == :chat}
          module={ChatLive}
          id="chat"
          lease={@session_lease}
          account={current_account(@access_context)}
          conversation={@conversation}
        />

        <.live_component
          :if={@route_spec.route_id == :dms}
          module={DmsLive}
          id="dms"
          lease={@session_lease}
          account={current_account(@access_context)}
          conversation={@dm}
        />

        <.live_component
          :if={@route_spec.route_id == :polls}
          module={PollsLive}
          id="polls"
          lease={@session_lease}
          account={current_account(@access_context)}
          poll_id={@poll_id}
        />

        <DesignLive.page :if={@route_spec.route_id == :design} />

        <AccountLive.profile
          :if={@route_spec.route_id == :account}
          signed_out_reason={@signed_out_reason}
          account={current_account(@access_context)}
          account_control={@account_control}
        />

        <AccountLive.agents
          :if={@route_spec.route_id == :account_agents}
          signed_out_reason={@signed_out_reason}
          lease={@session_lease}
          account={current_account(@access_context)}
        />

        <AshTemplateWeb.PointsLive.page
          :if={@route_spec.route_id == :points}
          signed_out_reason={@signed_out_reason}
          account={current_account(@access_context)}
          points={@points}
          board={@points_board}
          bonus={@points_bonus}
          earning={@points_earning}
        />

        <AccountLive.wallets
          :if={@route_spec.route_id == :wallets}
          signed_out_reason={@signed_out_reason}
          account={current_account(@access_context)}
          sign_in_wallets={@sign_in_wallets}
        />

        <PairLive.page
          :if={@route_spec.route_id == :pair}
          account={current_account(@access_context)}
          lease={@session_lease}
          start={@pair_start}
        />

        <AccountLive.connections
          :if={@route_spec.route_id == :connections}
          signed_out_reason={@signed_out_reason}
          account={current_account(@access_context)}
          verified_connections={@verified_connections}
          verified_connections_notice={@verified_connections_notice}
        />
      </:content>
    </.shell>
    """
  end

  defp subscribe_to_own_topics(%{principal: {:human, account}}) do
    Phoenix.PubSub.subscribe(AshTemplate.PubSub, "points:#{account.id}")
    Phoenix.PubSub.subscribe(AshTemplate.PubSub, Note.topic(account.id))
    Phoenix.PubSub.subscribe(AshTemplate.PubSub, Mute.topic(account.id))
    Phoenix.PubSub.subscribe(AshTemplate.PubSub, Notification.topic(account.id))
    Phoenix.PubSub.subscribe(AshTemplate.PubSub, "chat:conversations:#{account.id}")
    Phoenix.PubSub.subscribe(AshTemplate.PubSub, Dms.topic(account.id))
    Phoenix.PubSub.subscribe(AshTemplate.PubSub, RegentAgents.topic(account.privy_user_id))
  end

  defp subscribe_to_own_topics(_access_context), do: :ok

  # The Design page exists while the design pages do.
  defp open!(:design), do: Showcase.linked?() or raise(NotFoundError)
  defp open!(_action), do: true

  defp room_in(:room, %{"room" => slug}) do
    case Rooms.get_room(slug) do
      {:ok, %Room{} = room} -> room
      {:ok, nil} -> raise NotFoundError
    end
  end

  defp room_in(_action, _params), do: nil

  # A conversation opens only for the person it belongs to; a visitor sees the
  # chat page's sign-in prompt instead.
  defp conversation_in(:conversation, %{"conversation_id" => id}, %Human{} = actor) do
    case Chat.get_conversation(id, actor: actor) do
      {:ok, conversation} -> conversation
      {:error, _not_theirs} -> raise NotFoundError
    end
  end

  defp conversation_in(_action, _params, _actor), do: nil

  # A direct-message conversation opens only for its two people; a visitor
  # sees the messages page's sign-in prompt instead.
  defp dm_in(:dm, %{"conversation_id" => id}, %Human{} = actor),
    do: read_dm(id, actor) || raise(NotFoundError)

  defp dm_in(_action, _params, _actor), do: nil

  defp read_dm(id, actor) do
    case Dms.get_conversation(id, actor: actor, load: [:other_person, :blocked]) do
      {:ok, conversation} -> conversation
      {:error, %Ash.Error.Invalid{}} -> nil
    end
  end

  # A poll anyone may read; an id that names none is not found.
  defp poll_in(:poll, %{"poll_id" => id}) do
    case Polls.get_poll(id) do
      {:ok, %{id: id}} -> id
      _none -> raise NotFoundError
    end
  end

  defp poll_in(_action, _params), do: nil

  # The page hears the shared Points board while the Points page is open, and
  # not elsewhere.
  defp hear_board(socket, %{route_id: route}) do
    hearing? = socket.assigns.hearing_board?
    wanted? = route == :points

    if connected?(socket) and hearing? != wanted? do
      if wanted?,
        do: SharedReading.subscribe(Board.key()),
        else: SharedReading.unsubscribe(Board.key())

      assign(socket, :hearing_board?, wanted?)
    else
      socket
    end
  end

  # The page hears every poll while the polls page is open, and none elsewhere.
  defp hear_polls(socket, %{route_id: route}) do
    hearing? = socket.assigns.hearing_polls?
    wanted? = route == :polls

    if connected?(socket) and hearing? != wanted? do
      if wanted?,
        do: Phoenix.PubSub.subscribe(AshTemplate.PubSub, Polls.topic()),
        else: Phoenix.PubSub.unsubscribe(AshTemplate.PubSub, Polls.topic())

      assign(socket, :hearing_polls?, wanted?)
    else
      socket
    end
  end

  defp on_dm?(%{assigns: %{dm: %{id: id}}}, id), do: true
  defp on_dm?(_socket, _id), do: false

  # A room's title and description are its own name and topic.
  defp page_meta(%Room{} = room, _path),
    do: [page_title: "#{room.name} room", page_description: room.topic]

  defp page_meta(nil, path), do: PublicDocuments.page(path)

  # Every conversation shares the chat page's title.
  defp page_path(:conversation, _uri), do: "/chat"
  defp page_path(:dm, _uri), do: "/dms"
  defp page_path(:poll, _uri), do: "/polls"
  defp page_path(_action, uri), do: URI.parse(uri).path

  defp on_conversation?(%{assigns: %{conversation: %{id: id}}}, id), do: true
  defp on_conversation?(_socket, _id), do: false

  # The page hears the conversation it shows. The renamed copy of the same one
  # replaces it without hearing it twice.
  defp open_conversation(
         %{assigns: %{conversation: %{id: id}}} = socket,
         %{id: id} = conversation
       ),
       do: assign(socket, :conversation, conversation)

  defp open_conversation(socket, conversation) do
    if connected?(socket) do
      with %{id: id} <- socket.assigns.conversation,
           do: Phoenix.PubSub.unsubscribe(AshTemplate.PubSub, "chat:messages:#{id}")

      with %{id: id} <- conversation,
           do: Phoenix.PubSub.subscribe(AshTemplate.PubSub, "chat:messages:#{id}")
    end

    assign(socket, :conversation, conversation)
  end

  defp on_room?(%{assigns: %{room: %{slug: slug}}}, room), do: slug == room
  defp on_room?(_socket, _room), do: false

  # The page hears the room it shows, and a signed-in person is listed as here
  # while it is open. Patching to another room, or away, leaves the last one.
  defp enter_room(%{assigns: %{room: room}} = socket, room), do: socket

  defp enter_room(socket, room) do
    if connected?(socket) do
      leave_room(socket.assigns.room, human_actor(socket))
      join_room(room, human_actor(socket))
    end

    assign(socket, room: room, people: people(room))
  end

  defp join_room(nil, _human), do: :ok

  defp join_room(room, human) do
    Phoenix.PubSub.subscribe(AshTemplate.PubSub, Room.topic())
    Phoenix.PubSub.subscribe(AshTemplate.PubSub, Message.topic(room.slug))
    Phoenix.PubSub.subscribe(AshTemplate.PubSub, Presence.topic(room.slug))
    if human, do: Presence.join(room.slug, human)
  end

  defp leave_room(nil, _human), do: :ok

  defp leave_room(room, human) do
    Phoenix.PubSub.unsubscribe(AshTemplate.PubSub, Room.topic())
    Phoenix.PubSub.unsubscribe(AshTemplate.PubSub, Message.topic(room.slug))
    Phoenix.PubSub.unsubscribe(AshTemplate.PubSub, Presence.topic(room.slug))
    if human, do: Presence.leave(room.slug, human)
  end

  defp people(nil), do: []
  defp people(room), do: Presence.people(room.slug)

  defp current_account(%{principal: {:human, account}}), do: account
  defp current_account(_access_context), do: nil

  defp human_actor(%{assigns: %{access_context: %{principal: {:human, account}}}}),
    do: Human.for_account(account)

  defp human_actor(_socket), do: nil

  defp count_unread(socket) do
    with %Human{} = actor <- human_actor(socket),
         {:ok, count} <- Activity.count_unread(actor: actor) do
      assign(socket, :unread, count)
    else
      nil -> assign(socket, :unread, nil)
      {:error, _error} -> assign_new(socket, :unread, fn -> 0 end)
    end
  end

  defp load_notifications(socket, %{route_id: :activity}) do
    case human_actor(socket) do
      %Human{} = actor ->
        Read.now(socket, :notifications, actor.human_account_id, fn ->
          latest_notifications(actor)
        end)

      nil ->
        Read.clear(socket, :notifications)
    end
  end

  defp load_notifications(socket, _route_spec), do: Read.clear(socket, :notifications)

  # The activity page shows the newest page of notifications.
  defp latest_notifications(actor) do
    with {:ok, page} <- Activity.list_my_notifications(actor: actor, page: [limit: 50]),
         do: {:ok, page.results}
  end

  # Pages and actions match their names; rooms match their names, and the
  # person's notes and the room messages they can read their text, from two
  # characters on.
  defp search("", _actor), do: RouteCatalog.search_entries() |> Enum.map(&live_items/1)

  defp search(query, actor) do
    needle = String.downcase(query)

    named =
      for {group, entries} <- RouteCatalog.search_entries(),
          matches = Enum.filter(entries, &String.contains?(String.downcase(&1.label), needle)),
          matches != [],
          do: live_items({group, matches})

    named ++ found_rooms(query) ++ found_notes(query, actor) ++ found_messages(query, actor)
  end

  defp live_items({group, entries}) do
    kind = Map.fetch!(@kinds, group)

    {group,
     Enum.map(entries, &Map.merge(&1, %{kind: kind, live?: RouteCatalog.live_path?(&1.path)}))}
  end

  defp found_rooms(query) when byte_size(query) >= 2 do
    case Rooms.search_rooms(query) do
      {:ok, [_ | _] = rooms} ->
        items =
          for room <- rooms do
            %{kind: :page, label: "#{room.name} room", path: "/rooms/#{room.slug}", live?: true}
          end

        [{"Rooms", items}]

      _none ->
        []
    end
  end

  defp found_rooms(_query), do: []

  defp found_notes(query, %Human{} = actor) when byte_size(query) >= 2 do
    case Notes.search_my_notes(query, actor: actor) do
      {:ok, [_ | _] = notes} ->
        items =
          for note <- notes do
            %{
              kind: :note,
              label: note.title,
              detail: excerpt(note.body, query),
              path: "/notes",
              live?: true
            }
          end

        [{"Notes", items}]

      _none ->
        []
    end
  end

  defp found_notes(_query, _actor), do: []

  defp found_messages(query, actor) when byte_size(query) >= 2 do
    case Rooms.search_messages(query, actor: actor) do
      {:ok, [_ | _] = messages} ->
        items =
          for message <- messages do
            %{
              kind: :message,
              label:
                "#{message |> Message.author() |> PublicIdentity.words()} in #{message.in_room.name}",
              detail: excerpt(message.body, query),
              path: "/rooms/#{message.room}",
              live?: true
            }
          end

        [{"Room messages", items}]

      _none ->
        []
    end
  end

  defp found_messages(_query, _actor), do: []

  @excerpt_length 90

  # A long text is cut to about ninety characters, starting a little before
  # its first match so the match is in view.
  defp excerpt(nil, _query), do: nil

  defp excerpt(text, query) do
    length = String.length(text)

    start =
      case Regex.run(~r/#{Regex.escape(query)}/iu, text, return: :index) do
        [{at, _size}] -> text |> binary_part(0, at) |> String.length() |> Kernel.-(30) |> max(0)
        nil -> 0
      end

    start = min(start, max(length - @excerpt_length, 0))
    lead = if start > 0, do: "…", else: ""
    tail = if start + @excerpt_length < length, do: "…", else: ""
    lead <> String.slice(text, start, @excerpt_length) <> tail
  end

  # The NFT tier is read from Base once per page open, never on each award
  # notice, and not at all while nothing earns.
  defp load_points(socket, %{route_id: :points}) do
    socket
    |> assign(:points_earning, RegentPoints.Rules.active())
    |> read_points()
    |> read_points_board()
    |> read_points_bonus()
  end

  defp load_points(socket, _),
    do: socket |> Read.clear(:points) |> Read.clear(:points_board) |> Read.clear(:points_bonus)

  defp read_points(socket) do
    case human_actor(socket) do
      %Human{} = actor ->
        Read.now(socket, :points, actor.human_account_id, fn ->
          RegentPoints.summary(actor: actor)
        end)

      nil ->
        Read.clear(socket, :points)
    end
  end

  # The board every signed-in reader shares (AshTemplate.Points.Board). The
  # reader's own row and place are found from it, and their own total, as the
  # page renders.
  defp read_points_board(socket) do
    case human_actor(socket) do
      %Human{} -> assign(socket, :points_board, board_read(SharedReading.fetch(Board.key())))
      nil -> Read.clear(socket, :points_board)
    end
  end

  # Loading until the board is first read, an error when that first read failed,
  # and behind while the last read failed.
  defp board_read(:error), do: %Read{state: :loading}
  defp board_read({:ok, %{reading: nil}}), do: %Read{state: :error, error: :not_read}

  defp board_read({:ok, %{reading: board, at: at, degraded?: true}}),
    do: %Read{state: :stale, value: board, read_at: at, error: :not_read}

  defp board_read({:ok, %{reading: board, at: at}}),
    do: %Read{state: :ready, value: board, read_at: at}

  defp read_points_bonus(%{assigns: %{points_earning: []}} = socket),
    do: Read.clear(socket, :points_bonus)

  defp read_points_bonus(socket) do
    case human_actor(socket) do
      %Human{human_account_id: id} ->
        Read.start(socket, :points_bonus, id, fn -> points_bonus(id) end)

      nil ->
        Read.clear(socket, :points_bonus)
    end
  end

  # Base is read for the person's NFTs, counted against the same per-account
  # allowance as the Buy panel's reads.
  defp points_bonus(id) do
    case AshTemplate.Limits.spend(:wallet_read, {:human, id}) do
      :ok -> RegentPoints.Bonus.current(id)
      :limited -> {:error, :limited}
    end
  end

  defp load_verified_connections(socket, %{route_id: :connections}),
    do: read_verified_connections(socket)

  defp load_verified_connections(socket, _route_spec) do
    socket
    |> Read.clear(:verified_connections)
    |> assign(verified_connections_notice: nil)
  end

  # The account's own record is the only thing a connection is read from, so
  # nothing the browser reports can name a connection the record does not hold.
  defp read_verified_connections(socket) do
    case human_actor(socket) do
      %Human{} = actor ->
        Read.now(socket, :verified_connections, actor.human_account_id, fn ->
          Accounts.list_my_linked_identities(actor: actor)
        end)

      nil ->
        Read.clear(socket, :verified_connections)
    end
  end

  defp identity_request(:link, provider, _identities),
    do: {:ok, %{action: :link, provider: provider}}

  defp identity_request(:unlink, provider, identities) when is_list(identities) do
    case Enum.find(identities, &(&1.provider == provider)) do
      nil -> :error
      identity -> {:ok, %{action: :unlink, provider: provider, subject: identity.subject}}
    end
  end

  defp identity_request(_action, _provider, _identities), do: :error

  # X and GitHub take the whole tab to their own approval page and bring it
  # back; Farcaster asks for a scan here.
  defp connection_started(%{action: :link, provider: :farcaster}),
    do: "Scan the code with Farcaster to approve the connection."

  defp connection_started(%{action: :link, provider: provider}),
    do: "Taking you to #{Providers.label(provider)} to approve the connection."

  defp connection_started(%{action: :unlink, provider: provider}),
    do: "Disconnecting #{Providers.label(provider)}…"

  defp connection_outcome(%{"error" => "already-connected"}, _read),
    do: %{tone: :error, message: "That account is already connected to another account here."}

  defp connection_outcome(%{"error" => error}, _read) when is_binary(error) and error != "",
    do: %{tone: :error, message: "That connection couldn’t be verified. Try again."}

  defp connection_outcome(params, %Read{state: state, value: identities})
       when state in [:ready, :empty] do
    with {:ok, provider} <- Providers.parse(params["provider"]),
         {:ok, action} <- Map.fetch(@actions, params["action"]) do
      label = Providers.label(provider)

      case {action, Enum.any?(identities, &(&1.provider == provider))} do
        {:link, true} ->
          %{tone: :success, message: "#{label} connected."}

        {:link, false} ->
          %{tone: :error, message: "#{label} didn’t come back connected. Try again."}

        {:unlink, false} ->
          %{tone: :success, message: "#{label} disconnected."}

        {:unlink, true} ->
          %{tone: :error, message: "#{label} is still connected. Try again."}
      end
    else
      :error -> nil
    end
  end

  defp connection_outcome(_params, _read), do: nil
end
