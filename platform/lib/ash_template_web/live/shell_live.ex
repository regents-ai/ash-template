defmodule AshTemplateWeb.ShellLive do
  @moduledoc """
  One LiveView holds the header, sidebar and account control across every in-app
  route and patches between them, so the frame never remounts on navigation.
  """

  use AshTemplateWeb, :live_view

  import AshTemplateWeb.Components.Shell

  alias AshTemplate.Accounts
  alias AshTemplate.Accounts.LinkedIdentity.Providers
  alias AshTemplate.Actors.Human
  alias AshTemplate.Notes.Note
  alias AshTemplate.Rooms.{Message, Mute, Room}

  alias AshTemplateWeb.{
    AccountLive,
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

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: subscribe_to_own_topics(socket.assigns.access_context)

    {:ok,
     assign(socket,
       shell_instance: System.unique_integer([:positive, :monotonic]),
       room: nil,
       people: [],
       verified_connections: %Read{},
       verified_connections_notice: nil,
       connection_outcome: nil
     )}
  end

  @impl true
  def handle_params(params, uri, socket) do
    action = socket.assigns.live_action
    room = room_in(action, params)
    route_spec = RouteCatalog.fetch!(action, params)

    {:noreply,
     socket
     |> assign(PublicDocuments.page(URI.parse(uri).path))
     |> assign(:route_spec, route_spec)
     |> load_verified_connections(route_spec)
     |> enter_room(room)}
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

    {:noreply, socket}
  end

  # A room's posts, edits and deletes reach only the room on screen, so one
  # still in the mailbox from the room just left is dropped.
  def handle_info(%{topic: "rooms:" <> _, event: event, payload: %Message{} = message}, socket) do
    if on_room?(socket, message.room),
      do: send_update(RoomsLive, id: "rooms", change: {event, message})

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

  @impl true
  def render(assigns) do
    ~H"""
    <.shell
      route_spec={@route_spec}
      account_control={@account_control}
      shell_instance={@shell_instance}
    >
      <:content>
        <OverviewLive.page
          :if={@route_spec.route_id == :app}
          account_control={@account_control}
          account={current_account(@access_context)}
        />

        <.live_component
          :if={@route_spec.route_id == :notes}
          module={NotesLive}
          id="notes"
          account={current_account(@access_context)}
        />

        <.live_component
          :if={@route_spec.route_id == :room}
          module={RoomsLive}
          id="rooms"
          account={current_account(@access_context)}
          room={@room}
          people={@people}
        />

        <AccountLive.page
          :if={@route_spec.route_id == :account}
          account={current_account(@access_context)}
          account_control={@account_control}
          verified_connections={@verified_connections}
          verified_connections_notice={@verified_connections_notice}
        />
      </:content>
    </.shell>
    """
  end

  defp subscribe_to_own_topics(%{principal: {:human, account}}) do
    Phoenix.PubSub.subscribe(AshTemplate.PubSub, Note.topic(account.id))
    Phoenix.PubSub.subscribe(AshTemplate.PubSub, Mute.topic(account.id))
  end

  defp subscribe_to_own_topics(_access_context), do: :ok

  defp room_in(:room, %{"room" => slug}) do
    case Room.fetch(slug) do
      {:ok, room} -> room
      :error -> raise NotFoundError
    end
  end

  defp room_in(_action, _params), do: nil

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

  defp load_verified_connections(socket, %{route_id: :account}),
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
