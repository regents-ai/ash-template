defmodule AshTemplateWeb.RoomsLive do
  @moduledoc """
  One chat room: its messages oldest at the top and newest at the bottom above
  the message box, a form bound to the message's own Ash actions, and below it,
  for someone signed in, who is here now, the people the reader has muted, a
  form to start a room and, in a room they started, one to change its topic.

  The shell's sidebar lists the rooms, the most recently active first. Its first
  page (`Rooms.list_rooms`, 50 rooms) is read once, when the page opens, and
  More reads the next by the last one's cursor. The rooms go into a stream, so
  the page keeps only where the next page starts and which room is on top. The
  open room is always in the list and marked: a room beyond the pages shown
  joins the end, and moves to its place if More reaches it.

  Posting never touches the list of messages directly. Every post, edit and
  delete reaches each open page of the room the same way: the message's PubSub
  notifier publishes it after the transaction commits, the shell holds the
  room's subscription and hands it on here as `send_update(RoomsLive, id:
  "rooms", change: {event, message})`.

  A room started, posted in or given a new topic anywhere arrives the same way,
  as `room_change: {event, Room.public(room)}`. A room started or posted in goes
  to the top of the list from what the notice carries, with nothing read; a new
  topic reaches the open room.

  A message on the page is `Message.public/1`, the same map the notifier
  publishes, so a message read and a message published are drawn alike. Which
  messages a reader sees is theirs alone (their mutes); what each one says is
  the same for everyone. The room's read hands the page only what it draws:
  those maps, the cursor of the oldest one and whether older ones are left
  (`more?`). The messages go into a stream, which the server does not keep, and
  older ones are read by that cursor, so the page holds no records and no more
  than the maps of the last page each read returned.

  A message someone likes shows a heart with its count (`RoomsLive.Heart`);
  anyone signed in likes a message from its menu or by pressing the heart, and
  presses it again to take the like back. A like anywhere arrives as
  `change: {"like", %{id, room, like_count, like_version}}`, and the heart takes
  that count; nobody reads the message again. Whether the reader likes it
  (`liked`) changes only from their own press.

  A signed-in reader sees who is here (`AshTemplateWeb.Presence`): listed by
  name when the room opens, then each arrival at the end and each departure
  taken out, as the shell hands them on (`here: {arrived, left}`).
  """

  use AshTemplateWeb, :live_component

  import AshTemplateWeb.Components.PageHead

  alias AshTemplate.Actors.Human
  alias AshTemplate.{Dms, Rooms}
  alias AshTemplate.PublicIdentity
  alias AshTemplate.Rooms.{Like, Message, Mute, Room}
  alias AshTemplateWeb.Components.Shell
  alias AshTemplateWeb.{FormErrors, Presence}
  alias AshTemplateWeb.Live.Session
  alias AshTemplateWeb.Read
  alias AshTemplateWeb.RoomsLive.Heart
  alias Regent.Primitives

  @preview_lines 6
  @preview_characters 280

  @gone "That message is no longer here."

  # Why someone may report a message (`AshTemplate.Rooms.Report`), in the menu's words.
  @report_reasons [
    spam: "Spam",
    abuse: "Abuse",
    steers_agents: "Tries to steer agents",
    other: "Something else"
  ]

  @impl true
  def mount(socket) do
    {:ok,
     socket
     |> Session.check_component_lease(&take_account/2)
     |> assign(
       actor: nil,
       room: nil,
       rooms: %Read{},
       more_rooms: %Read{},
       rooms_page: nil,
       top: nil,
       messages: %Read{},
       older: %Read{},
       cursor: nil,
       more?: false,
       mutes: [],
       muted: MapSet.new(),
       liked: MapSet.new(),
       shown: %{},
       latest: nil,
       form: nil,
       room_form: nil,
       topic_form: nil,
       editing: nil,
       notice: nil,
       reported?: false,
       author_key: :crypto.strong_rand_bytes(16)
     )
     |> stream(:messages, [])
     |> stream_configure(:rooms, dom_id: &"room-link-#{&1.slug}")
     |> stream(:rooms, [])
     |> stream_configure(:people, dom_id: &"room-person-#{&1.id}")
     |> stream(:people, [])}
  end

  @impl true
  def update(%{change: {event, message}}, socket), do: {:ok, apply_change(socket, event, message)}
  def update(%{mutes_changed: true}, socket), do: {:ok, load(socket)}

  # Who arrived and who left, worked out once on this machine
  # (`AshTemplateWeb.Presence`). A person already listed keeps their place. A
  # reader whose sign-in lapsed on this page no longer sees who is here.
  def update(%{here: _here}, %{assigns: %{actor: nil}} = socket), do: {:ok, socket}

  def update(%{here: {arrived, left}}, socket) do
    socket =
      arrived
      |> Enum.reject(&muted_person?(socket, &1))
      |> Enum.reduce(socket, &stream_insert(&2, :people, &1))

    {:ok, Enum.reduce(left, socket, &stream_delete(&2, :people, %{id: &1}))}
  end

  def update(%{room_change: {event, changed}}, socket) when event in ~w(create active),
    do: {:ok, to_top(socket, changed)}

  def update(%{room_change: {"set_topic", changed}}, %{assigns: %{room: room}} = socket) do
    if changed.slug == room.slug,
      do: {:ok, socket |> assign(:room, %{room | topic: changed.topic}) |> topic_form()},
      else: {:ok, socket}
  end

  # The shell renders this with every update of its own, so the room is read
  # again only when the room or the person reading it changes. The room's topic
  # here may be newer than the shell's, so only its slug is compared.
  def update(%{id: id, lease: lease, account: account, room: room, client_key: key}, socket) do
    actor = account && Human.for_account(account)
    socket = assign(socket, id: id, lease: lease, client_key: key)

    if {actor, room.slug} == {socket.assigns.actor, slug(socket.assigns.room)},
      do: {:ok, socket},
      else: {:ok, socket |> assign(actor: actor, room: room) |> load()}
  end

  @impl true
  def handle_event("validate", %{"message" => params}, socket),
    do: {:noreply, assign(socket, :form, AshPhoenix.Form.validate(socket.assigns.form, params))}

  def handle_event("save", %{"message" => params}, socket) do
    case AshPhoenix.Form.submit(socket.assigns.form, params: params) do
      {:ok, _message} -> {:noreply, new_form(socket)}
      {:error, form} -> {:noreply, assign(socket, :form, form)}
    end
  end

  def handle_event("edit", %{"id" => id}, socket) do
    case Rooms.get_message(id, actor: socket.assigns.actor) do
      {:ok, %Message{} = message} ->
        form = Rooms.form_to_edit_message(message, actor: socket.assigns.actor, as: "message")

        {:noreply,
         socket
         |> assign(form: to_form(form), editing: message.id, notice: nil, reported?: false)
         |> push_event("conversation:edit", %{})}

      failure ->
        {:noreply, notice(socket, failure, @gone, "That message couldn’t be loaded. Try again.")}
    end
  end

  def handle_event("cancel", _params, socket), do: {:noreply, new_form(socket)}

  def handle_event("validate_room", %{"room" => params}, socket),
    do:
      {:noreply,
       assign(socket, :room_form, AshPhoenix.Form.validate(socket.assigns.room_form, params))}

  def handle_event("create_room", %{"room" => params}, socket) do
    case AshPhoenix.Form.submit(socket.assigns.room_form, params: params) do
      {:ok, room} -> {:noreply, push_patch(socket, to: ~p"/rooms/#{room.slug}")}
      {:error, form} -> {:noreply, assign(socket, :room_form, form)}
    end
  end

  def handle_event("validate_topic", %{"topic" => params}, socket),
    do:
      {:noreply,
       assign(socket, :topic_form, AshPhoenix.Form.validate(socket.assigns.topic_form, params))}

  def handle_event("save_topic", %{"topic" => params}, socket) do
    case AshPhoenix.Form.submit(socket.assigns.topic_form, params: params) do
      {:ok, room} -> {:noreply, socket |> assign(:room, room) |> topic_form()}
      {:error, form} -> {:noreply, assign(socket, :topic_form, form)}
    end
  end

  def handle_event("delete", %{"id" => id}, socket) do
    actor = socket.assigns.actor

    with {:ok, %Message{} = message} <- Rooms.get_message(id, actor: actor),
         :ok <- Rooms.delete_message(message, actor: actor) do
      {:noreply, assign(socket, :notice, nil)}
    else
      failure ->
        {:noreply, notice(socket, failure, @gone, "That message couldn’t be deleted. Try again.")}
    end
  end

  def handle_event("mute", %{"id" => id}, socket) do
    case Rooms.mute_author(id, actor: socket.assigns.actor) do
      {:ok, _mute} ->
        {:noreply, assign(socket, :notice, nil)}

      failure ->
        {:noreply, notice(socket, failure, @gone, "That person couldn’t be muted. Try again.")}
    end
  end

  # Opens the reader's direct messages with the message's author.
  def handle_event("message_author", %{"id" => id}, socket) do
    case Dms.open_conversation(id, actor: socket.assigns.actor) do
      {:ok, conversation} ->
        {:noreply, push_patch(socket, to: ~p"/dms/#{conversation.id}")}

      # Why it could not open, in the words the conversation gives.
      {:error, %Ash.Error.Invalid{} = error} ->
        [%{message: why} | _] = FormErrors.details(error)
        {:noreply, assign(socket, :notice, why)}

      {:error, _failure} ->
        {:noreply, assign(socket, :notice, "That conversation couldn’t be opened. Try again.")}
    end
  end

  # Likes the message, or takes back the reader's like when they already like it.
  # Only this reader's page changes whether it shows the message liked; the
  # count arrives with the like's notice, as on every page of the room.
  def handle_event("like", %{"id" => id}, socket) do
    %{actor: actor, client_key: key, liked: liked} = socket.assigns
    likes? = not MapSet.member?(liked, id)

    case press_like(id, likes?, actor, key) do
      :ok ->
        send_update(Heart, id: heart_id(id), liked: likes?)
        liked = if likes?, do: MapSet.put(liked, id), else: MapSet.delete(liked, id)
        {:noreply, assign(socket, liked: liked, notice: nil)}

      # Why it could not be saved, in the like's own words: the message is gone,
      # or the reader is going too quickly.
      {:error, %Ash.Error.Invalid{} = error} ->
        [%{message: why} | _] = FormErrors.details(error)
        {:noreply, assign(socket, :notice, why)}

      {:error, _failure} ->
        {:noreply, assign(socket, :notice, "That like couldn’t be saved. Try again.")}
    end
  end

  # Reports someone else's message to the site's team, saying why. The thanks
  # stays until the reader next posts or edits.
  def handle_event("report", %{"id" => id, "reason" => reason}, socket) do
    case Rooms.report_message(id, reason, actor: socket.assigns.actor) do
      {:ok, _report} ->
        {:noreply, assign(socket, notice: nil, reported?: true)}

      # Why it could not be reported, in the words the report gives.
      {:error, %Ash.Error.Invalid{} = error} ->
        [%{message: why} | _] = FormErrors.details(error)
        {:noreply, assign(socket, notice: why, reported?: false)}

      {:error, _failure} ->
        {:noreply,
         assign(socket, notice: "That report couldn’t be sent. Try again.", reported?: false)}
    end
  end

  def handle_event("unmute", %{"id" => id}, socket) do
    actor = socket.assigns.actor

    with {:ok, %Mute{} = mute} <- Rooms.get_my_mute(id, actor: actor),
         :ok <- Rooms.unmute(mute, actor: actor) do
      {:noreply, assign(socket, :notice, nil)}
    else
      failure ->
        {:noreply,
         notice(
           socket,
           failure,
           "That person is no longer muted.",
           "That person couldn’t be unmuted. Try again."
         )}
    end
  end

  def handle_event("older", _params, %{assigns: %{more?: true} = assigns} = socket) do
    %{room: room, actor: actor, cursor: cursor} = assigns

    {:noreply,
     socket
     |> Read.now(:older, owner(socket), fn -> read_older(room, actor, cursor) end)
     |> show_older()}
  end

  def handle_event(
        "more_rooms",
        _params,
        %{assigns: %{rooms_page: %{more?: true} = page}} = socket
      ) do
    {:noreply,
     socket
     |> Read.now(:more_rooms, :rooms, fn -> read_rooms(after: page.cursor) end)
     |> show_more_rooms()}
  end

  # A second press that arrives after the last page landed has nothing to read.
  def handle_event("more_rooms", _params, socket), do: {:noreply, socket}

  # The account as it reads now, before each event and each background result
  # (`Session.check_component_lease/2`).
  defp take_account(socket, account), do: assign(socket, :actor, Human.for_account(account))

  @impl true
  def render(assigns) do
    ~H"""
    <article id="rooms-page" class="account-page">
      <.portal id="rooms-sidebar" target="#shell-sidebar-page">
        <div class="shell-sidebar__page">
          <ul
            id="rooms-list"
            class="shell-sidebar__list"
            data-state={@rooms.state}
            phx-update="stream"
          >
            <li :for={{dom_id, room} <- @streams.rooms} id={dom_id}>
              <.link patch={~p"/rooms/#{room.slug}"} aria-current={room.slug == @room.slug && "page"}>
                {room.name}
              </.link>
            </li>
          </ul>
          <button
            :if={@rooms_page && @rooms_page.more?}
            type="button"
            class="shell-sidebar__more"
            phx-click="more_rooms"
            phx-target={@myself}
          >
            More
          </button>
          <Primitives.notice
            :if={@rooms.state == :error or @more_rooms.state in [:error, :stale]}
            tone="error"
          >
            The rooms couldn’t be loaded. Refresh the page to try again.
          </Primitives.notice>
        </div>
      </.portal>
      <.page_head title={@room.name}>
        <:tip>{@room.topic}</:tip>
      </.page_head>

      <section
        id="room-conversation"
        class="account-panel rooms-conversation"
        aria-labelledby="room-messages-title"
        phx-hook="Conversation"
      >
        <h2 id="room-messages-title" class="visually-hidden">Messages in {@room.name}</h2>

        <div
          class="rooms-scroller"
          role="log"
          aria-labelledby="room-messages-title"
          tabindex="0"
          data-conversation-scroller
        >
          <div class="rooms-scroller__inner">
            <Primitives.button
              :if={@more?}
              type="button"
              variant="secondary"
              class="rooms-older"
              phx-click="older"
              phx-target={@myself}
              phx-disable-with="Loading…"
            >
              Show older messages
            </Primitives.button>
            <Primitives.notice :if={@older.state in [:error, :stale]} tone="error">
              Older messages couldn’t be loaded. Try again.
            </Primitives.notice>

            <ol
              id="room-messages"
              class="rooms-messages"
              data-state={@messages.state}
              data-conversation-messages
              phx-update="stream"
            >
              <li id="room-messages-empty" class="rooms-empty rg-muted">
                No messages yet. Say hello.
              </li>
              <li
                :for={{dom_id, message} <- @streams.messages}
                id={dom_id}
                class="rooms-message"
                data-author={author_tag(message, @author_key)}
                data-at={DateTime.to_unix(message.inserted_at)}
                phx-mounted={JS.ignore_attributes(["data-continued"])}
              >
                <Shell.account_picture
                  :if={message.author_squares}
                  id={"#{dom_id}-picture"}
                  class="rooms-avatar"
                  squares={message.author_squares}
                  picture={message.author_picture}
                  size={36}
                />
                <span :if={!message.author_squares} class="rooms-avatar" aria-hidden="true">
                  {initials(words(message))}
                </span>
                <div class="rooms-message__main">
                  <p class="rooms-message__meta">
                    <Shell.person_name
                      id={"#{dom_id}-author"}
                      class="rooms-message__author"
                      person={Message.author(message)}
                    />
                    <span :if={message.agent_id} class="rooms-message__agent">Agent</span>
                    <span :if={message.backed_agents} class="rooms-message__human">
                      <span class="rooms-message__agent">Human-backed</span>
                      <Primitives.tip id={"#{dom_id}-human"} label="About human-backed agents">
                        {backing(message.backed_agents)}
                      </Primitives.tip>
                    </span>
                    <span :if={message.via_agent_id} class="rooms-message__human">
                      <span class="rooms-message__agent">Via agent</span>
                      <Primitives.tip id={"#{dom_id}-via"} label="About this agent">
                        {via_agent(message)}
                      </Primitives.tip>
                    </span>
                    <time datetime={DateTime.to_iso8601(message.inserted_at)}>
                      {RegentFormat.relative_time(message.inserted_at, DateTime.utc_now())}
                    </time>
                  </p>
                  <.message_body id={dom_id} body={message.body} />
                  <p :if={message.edited_at} class="rooms-message__edited">Edited</p>
                  <.live_component
                    module={Heart}
                    id={heart_id(message.id)}
                    message_id={message.id}
                    like_count={message.like_count}
                    like_version={message.like_version}
                    liked={MapSet.member?(@liked, message.id)}
                    signed_in?={@actor != nil}
                    target={@myself}
                  />
                </div>
                <.message_menu
                  :if={@actor}
                  id={dom_id}
                  message={message}
                  actor={@actor}
                  myself={@myself}
                />
              </li>
            </ol>
          </div>
        </div>

        <Primitives.notice :if={@notice} tone="warning">{@notice}</Primitives.notice>
        <Primitives.notice :if={@reported?} tone="success">
          Thanks. The site’s team will read your report.
        </Primitives.notice>
        <Primitives.notice :if={@messages.state in [:error, :stale]} tone="error">
          This room couldn’t be loaded. Refresh the page to try again.
        </Primitives.notice>

        <div :if={is_nil(@actor)} class="rooms-signed-out">
          <p>Anyone can read along. Sign in to post.</p>
          <Primitives.button type="button" data-account-target="sign-in">Sign in</Primitives.button>
        </div>

        <.form
          :if={@actor}
          for={@form}
          id="room-message-form"
          class="rooms-composer"
          phx-change="validate"
          phx-submit="save"
          phx-target={@myself}
        >
          <Primitives.field
            :let={field}
            id="room-message-body"
            label={if @editing, do: "Edit your message", else: "Message #{@room.name}"}
            errors={FormErrors.messages(@form[:body])}
          >
            <textarea
              id={field.id}
              name={@form[:body].name}
              rows="2"
              maxlength="2000"
              phx-debounce="blur"
              aria-invalid={field.aria_invalid}
              aria-describedby={"room-message-hint #{field.described_by}"}
            >{Phoenix.HTML.Form.normalize_value("textarea", @form[:body].value)}</textarea>
          </Primitives.field>
          <AshTemplateWeb.LiveConnection.offline
            id="room-message-offline"
            controls="#room-message-actions"
          />
          <fieldset id="room-message-actions" class="rooms-composer__actions">
            <p id="room-message-hint" class="visually-hidden">
              Enter sends. Shift+Enter starts a new line.
            </p>
            <Primitives.button
              :if={@editing}
              type="button"
              variant="secondary"
              phx-click="cancel"
              phx-target={@myself}
            >
              Cancel
            </Primitives.button>
            <Primitives.button type="submit" phx-disable-with="Sending…">
              {if @editing, do: "Save", else: "Send"}
            </Primitives.button>
          </fieldset>
        </.form>
      </section>

      <div :if={@actor} class="rooms-side">
        <section class="account-panel" aria-labelledby="room-people-title">
          <h2 id="room-people-title">Here now</h2>
          <ul id="room-people" class="rooms-people" phx-update="stream">
            <li id="room-people-empty" class="rooms-people__empty rg-muted">
              Nobody signed in has this room open.
            </li>
            <li :for={{dom_id, person} <- @streams.people} id={dom_id}>
              <Shell.person_name id={"#{dom_id}-name"} person={person} />
            </li>
          </ul>
        </section>

        <section :if={@mutes != []} class="account-panel" aria-labelledby="room-mutes-title">
          <h2 id="room-mutes-title">Muted</h2>
          <p class="rg-muted">
            You don’t see their messages in any room. They aren’t told.
          </p>
          <ul class="rooms-mutes">
            <li :for={mute <- @mutes}>
              <Shell.person_name id={"room-muted-#{mute.id}"} person={mute.person} />
              <Primitives.button
                type="button"
                variant="quiet"
                phx-click="unmute"
                phx-value-id={mute.id}
                phx-target={@myself}
              >
                Unmute
              </Primitives.button>
            </li>
          </ul>
        </section>

        <section
          :if={@topic_form}
          class="account-panel"
          aria-labelledby="room-topic-title"
        >
          <h2 id="room-topic-title">Topic</h2>
          <.form
            for={@topic_form}
            id="room-topic-form"
            class="rooms-start"
            phx-change="validate_topic"
            phx-submit="save_topic"
            phx-target={@myself}
          >
            <.topic_field form={@topic_form} id="room-topic" />
            <AshTemplateWeb.LiveConnection.offline
              id="room-topic-offline"
              controls="#room-topic-actions"
            />
            <fieldset id="room-topic-actions" class="rooms-start__actions">
              <Primitives.button type="submit" variant="secondary" phx-disable-with="Saving…">
                Save topic
              </Primitives.button>
            </fieldset>
          </.form>
        </section>

        <section class="account-panel" aria-labelledby="room-start-title">
          <h2 id="room-start-title">New room</h2>
          <.form
            for={@room_form}
            id="room-start-form"
            class="rooms-start"
            phx-change="validate_room"
            phx-submit="create_room"
            phx-target={@myself}
          >
            <Primitives.field
              :let={field}
              id="room-start-name"
              label="Name"
              errors={FormErrors.messages(@room_form[:name])}
            >
              <input
                id={field.id}
                name={@room_form[:name].name}
                value={@room_form[:name].value}
                maxlength="40"
                autocomplete="off"
                phx-debounce="blur"
                aria-invalid={field.aria_invalid}
                aria-describedby={field.described_by}
              />
            </Primitives.field>
            <.topic_field form={@room_form} id="room-start-topic" />
            <AshTemplateWeb.LiveConnection.offline
              id="room-start-offline"
              controls="#room-start-actions"
            />
            <fieldset id="room-start-actions" class="rooms-start__actions">
              <Primitives.button type="submit" phx-disable-with="Starting…">
                Start room
              </Primitives.button>
            </fieldset>
          </.form>
        </section>
      </div>
    </article>
    """
  end

  attr :form, Phoenix.HTML.Form, required: true
  attr :id, :string, required: true

  defp topic_field(assigns) do
    ~H"""
    <Primitives.field :let={field} id={@id} label="Topic" errors={FormErrors.messages(@form[:topic])}>
      <textarea
        id={field.id}
        name={@form[:topic].name}
        rows="2"
        maxlength="200"
        phx-debounce="blur"
        aria-invalid={field.aria_invalid}
        aria-describedby={field.described_by}
      >{Phoenix.HTML.Form.normalize_value("textarea", @form[:topic].value)}</textarea>
    </Primitives.field>
    """
  end

  attr :id, :string, required: true
  attr :body, :string, required: true

  # A long message shows its opening lines and a "Show more" that opens the
  # rest in place, in the browser alone.
  defp message_body(assigns) do
    assigns = assign(assigns, :preview, preview(assigns.body))

    ~H"""
    <p :if={is_nil(@preview)} class="rooms-body">{@body}</p>
    <div :if={@preview} class="rooms-long">
      <p id={"#{@id}-preview"} class="rooms-body">{@preview}</p>
      <p id={"#{@id}-full"} class="rooms-body" tabindex="-1" hidden>{@body}</p>
      <button
        type="button"
        class="rooms-more"
        phx-click={
          JS.set_attribute({"hidden", ""}, to: "##{@id}-preview")
          |> JS.remove_attribute("hidden", to: "##{@id}-full")
          |> JS.focus(to: "##{@id}-full")
          |> JS.set_attribute({"hidden", ""})
        }
      >
        Show more
      </button>
    </div>
    """
  end

  attr :id, :string, required: true
  attr :message, :map, required: true
  attr :actor, Human, required: true
  attr :myself, :any, required: true

  # Every message offers Like, or Remove like once the reader likes it (the
  # message's heart holds which, `RoomsLive.Heart`). The
  # author's own message offers Edit and Delete; anyone else's, Mute, Report,
  # and Message when a person stands behind it. The
  # browser opens the choices above everything else (`popover`), hanging from
  # the button, so the conversation's scrolling edge never cuts them off; they
  # open upward when there is no room below. Each choice closes them. Report
  # opens the reasons in their place, and each reason closes both.
  defp message_menu(assigns) do
    assigns =
      assign(assigns,
        report_reasons: @report_reasons,
        own?: assigns.message.human_account_id == assigns.actor.human_account_id,
        menu: "#{assigns.id}-menu",
        reasons: "#{assigns.id}-reasons",
        anchor: "--#{assigns.id}-menu"
      )

    ~H"""
    <div class="rooms-menu">
      <button
        type="button"
        class="rooms-menu__button"
        popovertarget={@menu}
        style={"anchor-name: #{@anchor}"}
      >
        <span aria-hidden="true">…</span>
        <span class="visually-hidden">Options for this message</span>
      </button>
      <div
        id={@menu}
        class="rooms-menu__items"
        popover
        role="group"
        aria-label="Message options"
        style={"position-anchor: #{@anchor}"}
      >
        <button
          type="button"
          class="rooms-menu__item"
          popovertarget={@menu}
          popovertargetaction="hide"
          phx-click={JS.push("like", value: %{id: @message.id}, target: @myself)}
        >
          <span class="rooms-menu__like">Like</span>
          <span class="rooms-menu__unlike">Remove like</span>
        </button>
        <button
          :if={@own?}
          type="button"
          class="rooms-menu__item"
          popovertarget={@menu}
          popovertargetaction="hide"
          phx-click={JS.push("edit", value: %{id: @message.id}, target: @myself)}
        >
          Edit
        </button>
        <button
          :if={@own?}
          type="button"
          class="rooms-menu__item"
          popovertarget={@menu}
          popovertargetaction="hide"
          phx-click={JS.push("delete", value: %{id: @message.id}, target: @myself)}
          data-confirm="Delete this message?"
          data-confirm-action="Delete"
        >
          Delete
        </button>
        <button
          :if={!@own? and @message.human_account_id}
          type="button"
          class="rooms-menu__item"
          popovertarget={@menu}
          popovertargetaction="hide"
          phx-click={JS.push("message_author", value: %{id: @message.id}, target: @myself)}
        >
          Message <bdi>{words(@message)}</bdi>
        </button>
        <button
          :if={!@own?}
          type="button"
          class="rooms-menu__item"
          popovertarget={@menu}
          popovertargetaction="hide"
          phx-click={JS.push("mute", value: %{id: @message.id}, target: @myself)}
          data-confirm={"Mute #{words(@message)}? You won’t see their messages in any room until you unmute them."}
          data-confirm-action="Mute"
        >
          Mute <bdi>{words(@message)}</bdi>
        </button>
        <button :if={!@own?} type="button" class="rooms-menu__item" popovertarget={@reasons}>
          Report
        </button>
      </div>
      <div
        :if={!@own?}
        id={@reasons}
        class="rooms-menu__items rooms-menu__reasons"
        popover
        role="group"
        aria-label="Report reason"
        style={"position-anchor: #{@anchor}"}
      >
        <p class="rooms-menu__label">Report as</p>
        <button
          :for={{reason, label} <- @report_reasons}
          type="button"
          class="rooms-menu__item"
          popovertarget={@menu}
          popovertargetaction="hide"
          phx-click={JS.push("report", value: %{id: @message.id, reason: reason}, target: @myself)}
        >
          {label}
        </button>
      </div>
    </div>
    """
  end

  defp owner(%{assigns: %{room: room, actor: actor}}),
    do: {room.slug, actor && actor.human_account_id}

  defp load(%{assigns: %{room: room, actor: actor}} = socket) do
    socket
    |> Read.clear(:older)
    |> Read.now(:messages, owner(socket), fn -> read_room(room, actor) end)
    |> show_messages()
    |> list_rooms()
    |> show_people()
    |> new_form()
    |> room_form()
    |> topic_form()
  end

  # A visitor has muted nobody. A signed-in reader's mutes are read with the
  # messages, so the two always agree.
  defp read_room(room, nil) do
    with {:ok, page} <- Rooms.list_room_messages(room.slug),
         do: {:ok, Map.put(drawn(page), :mutes, [])}
  end

  defp read_room(room, actor) do
    with {:ok, mutes} <- Rooms.list_my_mutes(actor: actor),
         {:ok, page} <- Rooms.list_room_messages(room.slug, actor: actor),
         do: {:ok, Map.put(drawn(page), :mutes, Enum.map(mutes, &drawn_mute/1))}
  end

  # The list's first page is read once, when the page opens. A room opened after
  # that is put in the list: updated where it stands, or at the end when it is
  # beyond the pages shown.
  defp list_rooms(%{assigns: %{rooms_page: nil}} = socket) do
    socket
    |> Read.now(:rooms, :rooms, fn -> read_rooms([]) end)
    |> show_rooms()
  end

  defp list_rooms(%{assigns: %{room: room}} = socket),
    do: stream_insert(socket, :rooms, Room.public(room))

  # A page of rooms as the list draws them, and where the next page starts.
  defp read_rooms(page) do
    with {:ok, page} <- Rooms.list_rooms(page: page) do
      {:ok,
       %{
         rooms: Enum.map(page.results, &Room.public/1),
         page: %{more?: page.more?, cursor: cursor(page.results)}
       }}
    end
  end

  # The open room joins the end of the first page when it is not on it.
  defp show_rooms(%{assigns: %{rooms: %Read{state: :ready, value: value} = read}} = socket) do
    open = Room.public(socket.assigns.room)

    rooms =
      if Enum.any?(value.rooms, &(&1.slug == open.slug)),
        do: value.rooms,
        else: value.rooms ++ [open]

    socket
    |> assign(rooms: %{read | value: nil}, rooms_page: value.page, top: hd(rooms).slug)
    |> stream(:rooms, rooms, reset: true)
  end

  defp show_rooms(socket), do: socket

  # Each room is taken out first, so one already in the list beyond the pages
  # shown (an open room put at the end) moves to its place.
  defp show_more_rooms(
         %{assigns: %{more_rooms: %Read{state: :ready, value: value} = read}} = socket
       ) do
    value.rooms
    |> Enum.reduce(socket, &stream_delete(&2, :rooms, &1))
    |> assign(more_rooms: %{read | value: nil}, rooms_page: value.page)
    |> stream(:rooms, value.rooms)
  end

  defp show_more_rooms(socket), do: socket

  # A room started or posted in goes to the top, from wherever it is in the list
  # or from beyond the pages shown. The room already on top stays as it is.
  defp to_top(%{assigns: %{top: slug}} = socket, %{slug: slug}), do: socket

  defp to_top(socket, room) do
    socket
    |> stream_delete(:rooms, room)
    |> stream_insert(:rooms, room, at: 0)
    |> assign(:top, room.slug)
  end

  # The page of messages before the oldest one shown.
  defp read_older(room, actor, cursor) do
    with {:ok, page} <- Rooms.list_room_messages(room.slug, actor: actor, page: [after: cursor]),
         do: {:ok, drawn(page)}
  end

  # What the page draws of a page of messages, newest first: the messages as
  # every page draws them, which of them the reader likes, the cursor of the
  # oldest and whether older ones are left.
  defp drawn(%Ash.Page.Keyset{results: messages, more?: more?}) do
    %{
      messages: Enum.map(messages, &Message.public/1),
      liked: for(%Message{liked_by_me: true, id: id} <- messages, into: MapSet.new(), do: id),
      cursor: cursor(messages),
      more?: more?
    }
  end

  # Where the page after this one starts: the oldest message, or the room least
  # recently active.
  defp cursor([]), do: nil
  defp cursor(results), do: List.last(results).__metadata__.keyset

  defp drawn_mute(mute), do: %{id: mute.id, person: Mute.muted(mute), author: muted_author(mute)}

  defp slug(nil), do: nil
  defp slug(room), do: room.slug

  # A failed read keeps the messages already on the page, so only a read that
  # landed replaces them.
  defp show_messages(%{assigns: %{messages: %Read{state: :ready, value: value}}} = socket) do
    socket
    |> assign(
      mutes: value.mutes,
      muted: MapSet.new(value.mutes, & &1.author),
      liked: value.liked,
      cursor: value.cursor,
      more?: value.more?,
      shown: edits(value.messages),
      latest: newest_at(value.messages)
    )
    |> stream(:messages, Enum.reverse(value.messages), reset: true)
  end

  defp show_messages(socket), do: socket

  defp newest_at([]), do: nil
  defp newest_at([newest | _older]), do: newest.inserted_at

  # A page of older messages comes newest first, so putting each one at the top
  # in turn leaves them in order above the ones already shown.
  defp show_older(%{assigns: %{older: %Read{state: :ready, value: value}}} = socket) do
    socket
    |> assign(
      cursor: value.cursor,
      more?: value.more?,
      liked: MapSet.union(socket.assigns.liked, value.liked),
      shown: Map.merge(socket.assigns.shown, edits(value.messages))
    )
    |> stream(:messages, value.messages, at: 0)
  end

  defp show_older(socket), do: socket

  # A signed-in reader sees who has the room open, by name, less anyone they
  # muted; the shell then hands on each arrival and departure.
  defp show_people(%{assigns: %{actor: nil}} = socket),
    do: stream(socket, :people, [], reset: true)

  defp show_people(%{assigns: %{room: room}} = socket) do
    people = Enum.reject(Presence.people(room.slug), &muted_person?(socket, &1))
    stream(socket, :people, people, reset: true)
  end

  defp muted_person?(%{assigns: %{muted: muted}}, person),
    do: MapSet.member?(muted, "person-#{person.id}")

  defp heart_id(message_id), do: "room-heart-#{message_id}"

  # Two notices about one message can arrive in either order, so the page keeps
  # the newer. `shown` holds, for each message the page has shown edited, the
  # time the database gave that edit, or `:deleted`; a notice that is not newer
  # changes nothing. `latest` is when the newest message shown was posted: an
  # edit of a message posted after it has overtaken its own post, and goes at
  # the bottom as the post would have.
  defp apply_change(socket, "destroy", %{id: id}) do
    socket = socket |> stream_delete(:messages, %{id: id}) |> shown(id, :deleted)
    if socket.assigns.editing == id, do: new_form(socket), else: socket
  end

  # A like or a like taken back anywhere: the message's heart takes the count it
  # carries. A message the page does not show (deleted, muted, older than the
  # page reaches) has no heart, and the notice changes nothing.
  defp apply_change(socket, "like", %{id: id, like_count: count, like_version: version}) do
    send_update(Heart, id: heart_id(id), like_count: count, like_version: version)
    socket
  end

  defp apply_change(socket, event, message) do
    cond do
      muted?(socket, message) ->
        socket

      stale?(socket, message) ->
        socket

      event == "post" or after_latest?(socket, message) ->
        latest =
          if after_latest?(socket, message),
            do: message.inserted_at,
            else: socket.assigns.latest

        socket
        |> stream_insert(:messages, message, at: -1)
        |> assign(:latest, latest)
        |> shown(message)

      event == "edit" ->
        socket |> stream_insert(:messages, message, update_only: true) |> shown(message)
    end
  end

  defp stale?(%{assigns: %{shown: shown}}, %{id: id, edited_at: edited_at}) do
    case shown do
      %{^id => :deleted} -> true
      %{^id => at} -> is_nil(edited_at) or DateTime.compare(edited_at, at) != :gt
      _never_shown_edited -> false
    end
  end

  defp after_latest?(%{assigns: %{latest: nil}}, _message), do: true

  defp after_latest?(%{assigns: %{latest: latest}}, message),
    do: DateTime.compare(message.inserted_at, latest) == :gt

  defp shown(socket, %{edited_at: nil}), do: socket
  defp shown(socket, %{id: id, edited_at: at}), do: shown(socket, id, at)

  defp shown(socket, id, mark),
    do: assign(socket, :shown, Map.put(socket.assigns.shown, id, mark))

  defp edits(messages),
    do: for(%{id: id, edited_at: %DateTime{} = at} <- messages, into: %{}, do: {id, at})

  # The read leaves out a muted author's messages and those a muted agent wrote
  # for its person (`LeaveOutMuted`); a notice is left out the same way.
  defp muted?(%{assigns: %{muted: muted}}, message) do
    MapSet.member?(muted, author(message)) or
      MapSet.member?(muted, "agent-#{message.via_agent_id}")
  end

  # A message or mute that is gone (deleted elsewhere, or never this person's)
  # says so; a database that could not answer says to try again.
  defp notice(socket, {:ok, nil}, gone, _retry), do: assign(socket, :notice, gone)

  defp notice(socket, {:error, %Ash.Error.Invalid{}}, gone, _retry),
    do: assign(socket, :notice, gone)

  defp notice(socket, {:error, _failure}, _gone, retry), do: assign(socket, :notice, retry)

  # A short wallet address starts with "0x" for everyone, so its picture shows
  # the two characters after it.
  defp initials("0x" <> rest), do: rest |> String.slice(0, 2) |> String.upcase()
  defp initials(name), do: RegentFormat.monogram(name, "?")

  # The opening lines of a long message, cut at a word and ending in "…"; nil
  # when the whole message is short enough to show.
  defp preview(body) do
    opening = body |> String.split("\n") |> Enum.take(@preview_lines) |> Enum.join("\n")

    opening =
      if String.length(opening) > @preview_characters,
        do: opening |> String.slice(0, @preview_characters) |> String.replace(~r/\s+\S*\z/u, ""),
        else: opening

    if opening == body, do: nil, else: String.trim_trailing(opening) <> "…"
  end

  defp backing(1),
    do:
      "A person verified with World ID stands behind this agent. It is the only agent they back."

  defp backing(count),
    do: "A person verified with World ID stands behind this agent. They back #{count} agents."

  # Who wrote a message, the same for every message by that person or agent.
  defp author(%{agent_id: nil, human_account_id: id}), do: "person-#{id}"
  defp author(%{agent_id: id}), do: "agent-#{id}"

  # What the page groups a person's messages by: the same for each of their
  # messages on this page, and unrelated to their account or agent number or
  # to their tag on any other page.
  defp author_tag(message, key) do
    :hmac
    |> :crypto.mac(:sha256, key, author(message))
    |> binary_part(0, 9)
    |> Base.url_encode64()
  end

  defp press_like(message_id, true, actor, key) do
    with {:ok, _like} <-
           Rooms.like_message(message_id, actor: actor, context: %{client_key: key}),
         do: :ok
  end

  defp press_like(message_id, false, actor, key) do
    case Rooms.get_my_like(message_id, actor: actor) do
      {:ok, %Like{} = like} -> Rooms.unlike(like, actor: actor, context: %{client_key: key})
      {:ok, nil} -> :ok
      failure -> failure
    end
  end

  defp via_agent(%{via_agent_name: nil} = message),
    do: "Written by an agent #{words(message)} paired with their account."

  defp via_agent(%{via_agent_name: agent} = message),
    do: "Written by #{agent}, an agent #{words(message)} paired with their account."

  # The author in plain words, where a button, a dialog or a tip cannot hold an
  # address.
  defp words(message), do: message |> Message.author() |> PublicIdentity.words()

  defp muted_author(%Mute{muted_agent_id: nil, muted_account_id: id}), do: "person-#{id}"
  defp muted_author(%Mute{muted_agent_id: id}), do: "agent-#{id}"

  defp new_form(%{assigns: %{actor: nil}} = socket), do: assign(socket, form: nil, editing: nil)

  defp new_form(%{assigns: %{actor: actor, room: room}} = socket) do
    form =
      Rooms.form_to_post_message(
        actor: actor,
        as: "message",
        context: %{client_key: socket.assigns.client_key},
        prepare_params: fn params, _phase -> Map.put(params, "room", room.slug) end
      )

    assign(socket, form: to_form(form), editing: nil, notice: nil, reported?: false)
  end

  defp room_form(%{assigns: %{actor: nil}} = socket), do: assign(socket, :room_form, nil)

  defp room_form(%{assigns: %{actor: actor}} = socket),
    do: assign(socket, :room_form, to_form(Rooms.form_to_create_room(actor: actor, as: "room")))

  # Only the person who started the room sees the form to change its topic.
  defp topic_form(%{assigns: %{actor: %Human{human_account_id: id}, room: room}} = socket)
       when room.created_by_id == id do
    form = Rooms.form_to_set_room_topic(room, actor: socket.assigns.actor, as: "topic")
    assign(socket, :topic_form, to_form(form))
  end

  defp topic_form(socket), do: assign(socket, :topic_form, nil)
end
