defmodule AshTemplateWeb.ShellLive do
  @moduledoc """
  One LiveView holds the frame (`AshTemplateWeb.Components.Shell`) across every
  in-app route and patches between them, so the frame never remounts on
  navigation. Besides the page, it keeps the frame's own parts current: the
  Get started checklist, the bell's unread count, the background jobs running,
  search and the assistant box.
  """

  use AshTemplateWeb, :live_view

  import AshTemplateWeb.Components.Shell

  require Ash.Query

  alias AshTemplate.{Accounts, Activity, Chat, JobsRunning, Notes, Rooms}
  alias AshTemplate.Accounts.LinkedIdentity.Providers
  alias AshTemplate.Activity.Notification
  alias AshTemplate.Actors.Human
  alias AshTemplate.Notes.Note
  alias AshTemplate.Rooms.{Message, Mute, Room}

  alias AshTemplateWeb.{
    AccountLive,
    ActivityLive,
    ChatLive,
    NotesLive,
    NotFoundError,
    OverviewLive,
    Presence,
    PublicDocuments,
    Read,
    RoomsLive,
    RouteCatalog
  }

  @actions %{"link" => :link, "unlink" => :unlink}
  @refused %{
    tone: :error,
    message: "That connection couldn’t be updated. Refresh the page and try again."
  }

  @steps [
    sign_in: "Sign in",
    wallet: "Link a wallet",
    note: "Write your first note",
    room: "Post in a room",
    chat: "Start a chat"
  ]
  @step_paths %{
    wallet: "/account/wallets",
    note: "/notes",
    room: "/rooms/#{hd(Room.all()).slug}",
    chat: "/chat"
  }
  @kinds %{"Pages" => :page, "Actions" => :action}

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      subscribe_to_own_topics(socket.assigns.access_context)
      Phoenix.PubSub.subscribe(AshTemplate.PubSub, JobsRunning.topic())
    end

    {:ok,
     socket
     |> assign(
       shell_instance: System.unique_integer([:positive, :monotonic]),
       room: nil,
       people: [],
       conversation: nil,
       chat_topics: MapSet.new(),
       verified_connections: %Read{},
       points: %Read{},
       verified_connections_notice: nil,
       connection_outcome: nil,
       notifications: %Read{},
       progress: progress(human_actor(socket)),
       jobs_running: JobsRunning.count(),
       healthy: AshTemplate.Health.database_ready?(),
       version: version(),
       search: unsearched(),
       assistant: nil
     )
     |> count_unread()
     |> read_credits()}
  end

  @impl true
  def handle_params(params, uri, socket) do
    action = socket.assigns.live_action
    room = room_in(action, params)
    conversation = conversation_in(action, params, human_actor(socket))
    route_spec = RouteCatalog.fetch!(action, params)

    {:noreply,
     socket
     |> assign(PublicDocuments.page(page_path(action, uri)))
     |> assign(:route_spec, route_spec)
     |> load_points(route_spec)
     |> load_verified_connections(route_spec)
     |> load_notifications(route_spec)
     |> assign(:search, unsearched())
     |> enter_room(room)
     |> open_conversation(conversation)}
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

  # The outcome is judged against the connections read after the provider came
  # back, so it waits for that read to land.
  def handle_event("refresh_verified_connections", params, socket) do
    {:noreply,
     socket
     |> assign(connection_outcome: params, verified_connections_notice: nil)
     |> read_verified_connections()}
  end

  def handle_event("mark_all_read", _params, socket) do
    with %Human{} = actor <- human_actor(socket) do
      Activity.mark_all_read(actor: actor)
    end

    {:noreply, socket}
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

  # The first question starts a conversation; the next ones continue it. The
  # reply arrives a piece at a time on the conversation's topic.
  def handle_event("assistant_ask", %{"text" => text}, socket) do
    with %Human{} = actor <- human_actor(socket),
         {:ok, message} <-
           Chat.create_message(%{text: text},
             actor: actor,
             private_arguments: assistant_conversation(socket.assigns.assistant)
           ) do
      {:noreply,
       socket
       |> assign(:assistant, %{
         conversation_id: message.conversation_id,
         question: text,
         reply: ""
       })
       |> sync_chat_topics()}
    else
      _refused -> {:noreply, socket}
    end
  end

  @impl true
  def handle_async({Read, _name, _generation} = name, result, socket) do
    {:noreply, socket |> Read.settle(name, result) |> report_connection_outcome()}
  end

  # Note changes are published on the writer's own topic; only the notes page
  # shows them, so on any other page they are dropped.
  @impl true
  def handle_info(%{topic: "notes:" <> _, event: event, payload: note}, socket) do
    if socket.assigns.route_spec.route_id == :notes,
      do: send_update(NotesLive, id: "notes", change: {event, note})

    {:noreply, if(event == "create", do: step_done(socket, :note), else: socket)}
  end

  # A notification arriving or being read anywhere recounts the bell, and
  # reads the Activity page again when it is open.
  def handle_info(%{topic: "notifications:" <> _}, socket) do
    {:noreply, socket |> count_unread() |> load_notifications(socket.assigns.route_spec)}
  end

  # A points award or correction landed for this account; the Points page follows.
  def handle_info(%{topic: "points:" <> _}, socket),
    do: {:noreply, load_points(socket, socket.assigns.route_spec)}

  # The balance changed on this or any Regent site: a purchase, a gift, a spend.
  # The header, the Buy Credits panel and the Account page follow.
  def handle_info(:credits_changed, socket), do: {:noreply, read_credits(socket)}

  # An agent paired, checked in or was unpaired, here or on another Regent site.
  def handle_info(:agents_changed, socket) do
    if socket.assigns.route_spec.route_id == :account,
      do: send_update(AshTemplateWeb.AgentsPanel, id: "account-agents", agents_changed: true)

    {:noreply, socket}
  end

  def handle_info({:jobs_running, count}, socket),
    do: {:noreply, assign(socket, :jobs_running, count)}

  # A room's posts, edits and deletes reach only the room on screen, so one
  # still in the mailbox from the room just left is dropped.
  def handle_info(%{topic: "rooms:" <> _, event: event, payload: %Message{} = message}, socket) do
    if on_room?(socket, message.room),
      do: send_update(RoomsLive, id: "rooms", change: {event, message})

    if event == "post" and own?(socket, message),
      do: {:noreply, step_done(socket, :room)},
      else: {:noreply, socket}
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

  # Each piece of the assistant's reply, and the person's own message, reach only
  # the conversation on screen.
  # The assistant box shows the reply to its own conversation as it is written.
  def handle_info(%{topic: "chat:messages:" <> id, payload: message}, socket) do
    if on_conversation?(socket, id),
      do: send_update(ChatLive, id: "chat", change: message)

    case socket.assigns.assistant do
      %{conversation_id: ^id} when message.source == :agent ->
        {:noreply, update(socket, :assistant, &%{&1 | reply: message.text})}

      _other ->
        {:noreply, socket}
    end
  end

  # A conversation started or named on any of the person's pages joins their
  # list, and renames the one on screen.
  def handle_info(%{topic: "chat:conversations:" <> _, payload: conversation}, socket) do
    if socket.assigns.route_spec.route_id == :chat,
      do: send_update(ChatLive, id: "chat", conversation_change: conversation)

    socket = step_done(socket, :chat)

    if on_conversation?(socket, conversation.id),
      do: {:noreply, assign(socket, :conversation, conversation)},
      else: {:noreply, socket}
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
      checklist={checklist(@progress)}
      unread={@unread}
      credits={@credits}
      jobs_running={@jobs_running}
      healthy={@healthy}
      version={@version}
      search={@search}
      assistant={@assistant}
    >
      <:credits_panel :if={@credits}>
        <.live_component
          module={AshTemplateWeb.CreditsPanel}
          id="credits-panel"
          lease={@session_lease}
          account={current_account(@access_context)}
          balance={@balance}
        />
      </:credits_panel>
      <:content>
        <OverviewLive.page
          :if={@route_spec.route_id == :app}
          account_control={@account_control}
          account={current_account(@access_context)}
        />

        <ActivityLive.page
          :if={@route_spec.route_id == :activity}
          account={current_account(@access_context)}
          notifications={@notifications}
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
        />

        <.live_component
          :if={@route_spec.route_id == :chat}
          module={ChatLive}
          id="chat"
          lease={@session_lease}
          account={current_account(@access_context)}
          conversation={@conversation}
        />

        <AccountLive.profile
          :if={@route_spec.route_id == :account}
          lease={@session_lease}
          account={current_account(@access_context)}
          account_control={@account_control}
          credits={@credits}
        />

        <AshTemplateWeb.PointsLive.page
          :if={@route_spec.route_id == :points}
          account={current_account(@access_context)}
          points={@points}
        />

        <AccountLive.wallets
          :if={@route_spec.route_id == :wallets}
          account={current_account(@access_context)}
        />

        <AccountLive.connections
          :if={@route_spec.route_id == :connections}
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
    Phoenix.PubSub.subscribe(AshTemplate.PubSub, RegentCredits.topic(account.privy_user_id))
    Phoenix.PubSub.subscribe(AshTemplate.PubSub, RegentAgents.topic(account.privy_user_id))
  end

  defp subscribe_to_own_topics(_access_context), do: :ok

  defp room_in(:room, %{"room" => slug}) do
    case Room.fetch(slug) do
      {:ok, room} -> room
      :error -> raise NotFoundError
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

  # Every conversation shares the chat page's title.
  defp page_path(:conversation, _uri), do: "/chat"
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

  defp open_conversation(socket, conversation),
    do: socket |> assign(:conversation, conversation) |> sync_chat_topics()

  # The page hears the conversation on screen and the assistant box's own, each
  # once even when they are the same conversation.
  defp sync_chat_topics(socket) do
    wanted =
      [socket.assigns.conversation, socket.assigns.assistant]
      |> Enum.flat_map(fn
        %{id: id} -> ["chat:messages:#{id}"]
        %{conversation_id: id} -> ["chat:messages:#{id}"]
        nil -> []
      end)
      |> MapSet.new()

    if connected?(socket) do
      held = socket.assigns.chat_topics

      for topic <- MapSet.difference(held, wanted),
          do: Phoenix.PubSub.unsubscribe(AshTemplate.PubSub, topic)

      for topic <- MapSet.difference(wanted, held),
          do: Phoenix.PubSub.subscribe(AshTemplate.PubSub, topic)

      assign(socket, :chat_topics, wanted)
    else
      socket
    end
  end

  defp on_room?(%{assigns: %{room: %{slug: slug}}}, room), do: to_string(slug) == to_string(room)
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
    Phoenix.PubSub.subscribe(AshTemplate.PubSub, Message.topic(room.slug))
    Phoenix.PubSub.subscribe(AshTemplate.PubSub, Presence.topic(room.slug))
    if human, do: Presence.join(room.slug, human)
  end

  defp leave_room(nil, _human), do: :ok

  defp leave_room(room, human) do
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

  defp own?(socket, message) do
    case human_actor(socket) do
      %Human{human_account_id: id} -> message.human_account_id == id
      nil -> false
    end
  end

  # What the Get started checklist shows as done, read from the person's own
  # records once, then kept current by the events the page already hears.
  defp progress(nil), do: %{}

  defp progress(%Human{} = actor) do
    %{
      sign_in: true,
      wallet: actor.wallet_addresses != [],
      note: Ash.exists?(Note, actor: actor),
      room:
        Message
        |> Ash.Query.filter(human_account_id == ^actor.human_account_id)
        |> Ash.exists?(actor: actor),
      chat: Ash.exists?(AshTemplate.Chat.Conversation, actor: actor)
    }
  end

  defp step_done(socket, step), do: update(socket, :progress, &Map.put(&1, step, true))

  defp checklist(progress) do
    for {id, label} <- @steps,
        do: %{id: id, label: label, path: @step_paths[id], done?: Map.get(progress, id, false)}
  end

  defp read_credits(socket) do
    case current_account(socket.assigns.access_context) do
      nil ->
        assign(socket, balance: nil, credits: nil)

      account ->
        balance = RegentCredits.balance(account.privy_user_id)
        assign(socket, balance: balance, credits: balance.available)
    end
  end

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
        Read.start(socket, :notifications, actor.human_account_id, fn ->
          Activity.list_my_notifications(actor: actor)
        end)

      nil ->
        Read.clear(socket, :notifications)
    end
  end

  defp load_notifications(socket, _route_spec), do: Read.clear(socket, :notifications)

  # Pages and actions match their names; the person's notes and the room
  # messages they can read match their text, from two characters on.
  defp search("", _actor), do: RouteCatalog.search_entries() |> Enum.map(&live_items/1)

  defp search(query, actor) do
    needle = String.downcase(query)

    named =
      for {group, entries} <- RouteCatalog.search_entries(),
          matches = Enum.filter(entries, &String.contains?(String.downcase(&1.label), needle)),
          matches != [],
          do: live_items({group, matches})

    named ++ found_notes(query, actor) ++ found_messages(query, actor)
  end

  defp live_items({group, entries}) do
    kind = Map.fetch!(@kinds, group)

    {group,
     Enum.map(entries, &Map.merge(&1, %{kind: kind, live?: RouteCatalog.live_path?(&1.path)}))}
  end

  defp found_notes(query, %Human{} = actor) when byte_size(query) >= 2 do
    case Notes.search_my_notes(query, actor: actor) do
      {:ok, [_ | _] = notes} ->
        [{"Notes", Enum.map(notes, &note_item(&1, query))}]

      _none ->
        []
    end
  end

  defp found_notes(_query, _actor), do: []

  defp found_messages(query, actor) when byte_size(query) >= 2 do
    case Rooms.search_messages(query, actor: actor) do
      {:ok, [_ | _] = messages} ->
        [{"Room messages", Enum.map(messages, &message_item(&1, query))}]

      _none ->
        []
    end
  end

  defp found_messages(_query, _actor), do: []

  defp note_item(note, query),
    do: %{
      kind: :note,
      label: note.title,
      detail: excerpt(note.body, query),
      path: "/notes",
      live?: true
    }

  defp message_item(message, query) do
    {:ok, room} = message.room |> Atom.to_string() |> Room.fetch()

    %{
      kind: :message,
      label: "#{message.author_name} in #{room.name}",
      detail: excerpt(message.body, query),
      path: "/rooms/#{room.slug}",
      live?: true
    }
  end

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

  defp assistant_conversation(%{conversation_id: id}), do: %{conversation_id: id}
  defp assistant_conversation(nil), do: %{}

  defp version do
    commit = Application.fetch_env!(:ash_template, :running_version)[:commit]
    "#{Application.spec(:ash_template, :vsn)} (#{commit})"
  end

  defp load_points(socket, %{route_id: :points}) do
    case human_actor(socket) do
      %Human{} = actor ->
        Read.start(socket, :points, actor.human_account_id, fn ->
          RegentPoints.summary(actor: actor)
        end)

      nil ->
        Read.clear(socket, :points)
    end
  end

  defp load_points(socket, _), do: Read.clear(socket, :points)

  defp load_verified_connections(socket, %{route_id: :connections}),
    do: read_verified_connections(socket)

  defp load_verified_connections(socket, _route_spec) do
    socket
    |> Read.clear(:verified_connections)
    |> assign(verified_connections_notice: nil, connection_outcome: nil)
  end

  # The account's own record is the only thing a connection is read from, so
  # nothing the browser reports can name a connection the record does not hold.
  defp read_verified_connections(socket) do
    case human_actor(socket) do
      %Human{} = actor ->
        Read.start(socket, :verified_connections, actor.human_account_id, fn ->
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

  defp report_connection_outcome(%{assigns: %{connection_outcome: nil}} = socket), do: socket

  defp report_connection_outcome(
         %{assigns: %{verified_connections: %{state: :loading}}} = socket
       ),
       do: socket

  defp report_connection_outcome(%{assigns: assigns} = socket) do
    notice = connection_outcome(assigns.connection_outcome, assigns.verified_connections)
    assign(socket, verified_connections_notice: notice, connection_outcome: nil)
  end

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
