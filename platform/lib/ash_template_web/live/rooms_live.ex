defmodule AshTemplateWeb.RoomsLive do
  @moduledoc """
  One chat room: its messages oldest at the top and newest at the bottom above
  the message box, a form bound to the message's own Ash actions, and below it,
  for someone signed in, who is here now, the people the reader has muted, a
  form to start a room and, in a room they started, one to change its topic.
  Every room is listed in the shell's sidebar.

  Posting never touches the list directly. Every post, edit and delete reaches
  each open page of the room the same way: the message's PubSub notifier
  publishes it after the transaction commits, the shell holds the room's
  subscription and hands it on here as `send_update(RoomsLive, id: "rooms",
  change: {event, message})`. The shell also tracks who is here
  (`AshTemplateWeb.Presence`) and passes the list in as `people`.

  A room started or a topic changed anywhere arrives the same way, as
  `room_change: {event, Room.public(room)}`, and the list and the topic follow.

  A message on the page is `Message.public/1`, the same map the notifier
  publishes, so a message read and a message published are drawn alike. Which
  messages a reader sees is theirs alone (their mutes); what each one says is
  the same for everyone.

  A message someone likes shows a heart with its count; anyone signed in likes
  a message from its menu or by pressing the heart, and presses it again to
  take the like back. A like anywhere arrives as `change: {"like", %{id, room}}`,
  and the page reads that message again, so its count is as it stands and its
  heart shows whether this reader likes it (`liked`).
  """

  use AshTemplateWeb, :live_component

  import AshTemplateWeb.Components.PageHead

  alias AshTemplate.Actors.Human
  alias AshTemplate.{Dms, Rooms}
  alias AshTemplate.Rooms.{Like, Message, Mute, Room}
  alias AshTemplateWeb.Components.Shell
  alias AshTemplateWeb.FormErrors
  alias AshTemplateWeb.Live.Session
  alias AshTemplateWeb.Read
  alias Regent.{Discussion, Primitives}

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
       rooms: [],
       people: [],
       messages: %Read{},
       older: %Read{},
       page: nil,
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
     |> stream(:messages, [])}
  end

  @impl true
  def update(%{change: {event, message}}, socket), do: {:ok, apply_change(socket, event, message)}
  def update(%{mutes_changed: true}, socket), do: {:ok, load(socket)}

  def update(%{room_change: {_event, changed}}, socket) do
    room = socket.assigns.room

    socket =
      if changed.slug == room.slug,
        do: socket |> assign(:room, %{room | topic: changed.topic}) |> topic_form(),
        else: socket

    {:ok, assign(socket, :rooms, listed(socket.assigns.rooms, changed))}
  end

  # The shell renders this with every update of its own, so the room is read
  # again only when the room or the person reading it changes. The room's topic
  # here may be newer than the shell's, so only its slug is compared.
  def update(
        %{id: id, lease: lease, account: account, room: room, people: people, client_key: key},
        socket
      ) do
    actor = account && Human.for_account(account)
    socket = assign(socket, id: id, lease: lease, people: people, client_key: key)

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
        {:noreply, socket |> edit_form(message) |> push_event("conversation:edit", %{})}

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
  def handle_event("like", %{"id" => id}, socket) do
    actor = socket.assigns.actor

    result =
      if MapSet.member?(socket.assigns.liked, id),
        do: unlike(id, actor),
        else: Rooms.like_message(id, actor: actor)

    case result do
      {:ok, _like} ->
        {:noreply, assign(socket, :notice, nil)}

      failure ->
        {:noreply, notice(socket, failure, @gone, "That like couldn’t be saved. Try again.")}
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

  def handle_event("older", _params, %{assigns: %{page: %{more?: true} = page}} = socket) do
    {:noreply,
     socket |> Read.now(:older, owner(socket), fn -> Ash.page(page, :next) end) |> show_older()}
  end

  # The account as it reads now, before each event and each background result
  # (`Session.check_component_lease/2`).
  defp take_account(socket, account), do: assign(socket, :actor, Human.for_account(account))

  @impl true
  def render(assigns) do
    ~H"""
    <article id="rooms-page" class="account-page">
      <.portal id="rooms-sidebar" target="#shell-sidebar-page">
        <ul id="rooms-list" class="shell-sidebar__list" data-state={@messages.state}>
          <li :for={room <- @rooms}>
            <.link
              patch={~p"/rooms/#{room.slug}"}
              aria-current={if room.slug == @room.slug, do: "page"}
            >
              {room.name}
            </.link>
          </li>
        </ul>
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
              :if={@page && @page.more?}
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
                <span
                  :if={!message.author_squares}
                  class="rooms-avatar"
                  data-tone={:erlang.phash2(author(message), 3)}
                  aria-hidden="true"
                >
                  {initials(message.author_name)}
                </span>
                <div class="rooms-message__main">
                  <p class="rooms-message__meta">
                    <bdi class="rooms-message__author">{message.author_name}</bdi>
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
                  <.likes
                    :if={message.like_count > 0}
                    message={message}
                    liked={MapSet.member?(@liked, message.id)}
                    actor={@actor}
                    myself={@myself}
                  />
                </div>
                <.message_menu
                  :if={@actor}
                  id={dom_id}
                  message={message}
                  liked={MapSet.member?(@liked, message.id)}
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
              aria-invalid={field.aria_invalid}
              aria-describedby={"room-message-hint #{field.described_by}"}
            >{Phoenix.HTML.Form.normalize_value("textarea", @form[:body].value)}</textarea>
          </Primitives.field>
          <AshTemplateWeb.LiveConnection.offline
            id="room-message-offline"
            controls="#room-message-actions"
          />
          <fieldset id="room-message-actions" class="rooms-composer__actions">
            <p id="room-message-hint" class="rooms-composer__hint rg-muted">
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
          <ul :if={here(@people, @muted) != []} class="rooms-people">
            <li :for={person <- here(@people, @muted)}><bdi>{person.name}</bdi></li>
          </ul>
          <p :if={here(@people, @muted) == []} class="rg-muted">
            Nobody signed in has this room open.
          </p>
        </section>

        <section class="account-panel" aria-labelledby="room-mutes-title">
          <h2 id="room-mutes-title">Muted</h2>
          <p class="rg-muted">
            You don’t see their messages in any room. They aren’t told.
          </p>
          <ul :if={@mutes != []} class="rooms-mutes">
            <li :for={mute <- @mutes}>
              <bdi>{mute.muted_name}</bdi>
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
          <h2 id="room-topic-title">Room topic</h2>
          <p class="rg-muted">You started this room, so you choose what it’s about.</p>
          <.form
            for={@topic_form}
            id="room-topic-form"
            class="rooms-start"
            phx-change="validate_topic"
            phx-submit="save_topic"
            phx-target={@myself}
          >
            <.topic_field form={@topic_form} id="room-topic" />
            <Primitives.button type="submit" variant="secondary" phx-disable-with="Saving…">
              Save topic
            </Primitives.button>
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
                phx-debounce="300"
                aria-invalid={field.aria_invalid}
                aria-describedby={field.described_by}
              />
            </Primitives.field>
            <.topic_field form={@room_form} id="room-start-topic" />
            <Primitives.button type="submit" phx-disable-with="Starting…">
              Start room
            </Primitives.button>
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
        phx-debounce="300"
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

  attr :message, :map, required: true
  attr :liked, :boolean, required: true
  attr :actor, Human, default: nil
  attr :myself, :any, required: true

  # The heart and its count. A visitor's press opens sign-in.
  defp likes(%{actor: nil} = assigns) do
    ~H"""
    <Discussion.like count={@message.like_count} liked={false} data-account-target="sign-in" />
    """
  end

  defp likes(assigns) do
    ~H"""
    <Discussion.like
      count={@message.like_count}
      liked={@liked}
      phx-click={JS.push("like", value: %{id: @message.id}, target: @myself)}
    />
    """
  end

  attr :id, :string, required: true
  attr :message, :map, required: true
  attr :liked, :boolean, required: true
  attr :actor, Human, required: true
  attr :myself, :any, required: true

  # Every message offers Like, or Remove like once the reader likes it. The
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
          {if @liked, do: "Remove like", else: "Like"}
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
          Message <bdi>{@message.author_name}</bdi>
        </button>
        <button
          :if={!@own?}
          type="button"
          class="rooms-menu__item"
          popovertarget={@menu}
          popovertargetaction="hide"
          phx-click={JS.push("mute", value: %{id: @message.id}, target: @myself)}
          data-confirm={"Mute #{@message.author_name}? You won’t see their messages in any room until you unmute them."}
        >
          Mute <bdi>{@message.author_name}</bdi>
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
    |> new_form()
    |> room_form()
    |> topic_form()
  end

  # A visitor has muted nobody. A signed-in reader's mutes are read with the
  # messages, so the two always agree. The list of rooms is read alongside.
  defp read_room(room, nil) do
    with {:ok, rooms} <- Rooms.list_rooms(),
         {:ok, page} <- Rooms.list_room_messages(room.slug),
         do: {:ok, %{rooms: rooms, mutes: [], page: page}}
  end

  defp read_room(room, actor) do
    with {:ok, rooms} <- Rooms.list_rooms(),
         {:ok, mutes} <- Rooms.list_my_mutes(actor: actor),
         {:ok, page} <- Rooms.list_room_messages(room.slug, actor: actor),
         do: {:ok, %{rooms: rooms, mutes: mutes, page: page}}
  end

  defp slug(nil), do: nil
  defp slug(room), do: room.slug

  # A room started elsewhere joins the end of the list; a changed topic keeps
  # its place.
  defp listed(rooms, changed) do
    if Enum.any?(rooms, &(&1.slug == changed.slug)),
      do: Enum.map(rooms, &if(&1.slug == changed.slug, do: changed, else: &1)),
      else: rooms ++ [changed]
  end

  # A failed read keeps the messages already on the page, so only a read that
  # landed replaces them.
  defp show_messages(%{assigns: %{messages: %Read{state: :ready, value: value}}} = socket) do
    messages = Enum.map(value.page.results, &Message.public/1)

    socket
    |> assign(
      rooms: Enum.map(value.rooms, &Room.public/1),
      page: value.page,
      mutes: value.mutes,
      muted: MapSet.new(value.mutes, &muted_author/1),
      liked: liked(value.page.results),
      shown: edits(messages),
      latest: with([newest | _] <- messages, do: newest.inserted_at)
    )
    |> stream(:messages, Enum.reverse(messages), reset: true)
  end

  defp show_messages(socket), do: socket

  # A page of older messages comes newest first, so putting each one at the top
  # in turn leaves them in order above the ones already shown.
  defp show_older(%{assigns: %{older: %Read{state: :ready, value: page}}} = socket) do
    messages = Enum.map(page.results, &Message.public/1)

    socket
    |> assign(
      page: page,
      liked: MapSet.union(socket.assigns.liked, liked(page.results)),
      shown: Map.merge(socket.assigns.shown, edits(messages))
    )
    |> stream(:messages, messages, at: 0)
  end

  defp show_older(socket), do: socket

  defp liked(messages),
    do: for(%Message{liked_by_me: true, id: id} <- messages, into: MapSet.new(), do: id)

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

  # A like or a like taken back: the message is read again, as this reader sees
  # it. One deleted, muted or no longer here changes nothing.
  defp apply_change(socket, "like", %{id: id, room: room}) do
    with false <- match?(%{^id => :deleted}, socket.assigns.shown),
         {:ok, %Message{} = read} <- Rooms.get_room_message(room, id, actor: socket.assigns.actor),
         message = Message.public(read),
         false <- muted?(socket, message) do
      socket
      |> update(
        :liked,
        &if(read.liked_by_me, do: MapSet.put(&1, id), else: MapSet.delete(&1, id))
      )
      |> stream_insert(:messages, message, update_only: true)
      |> shown(message)
    else
      _unchanged -> socket
    end
  end

  defp apply_change(socket, event, message) do
    cond do
      muted?(socket, message) ->
        socket

      stale?(socket, message) ->
        socket

      event == "post" or after_latest?(socket, message) ->
        append(socket, message)

      event == "edit" ->
        socket |> stream_insert(:messages, message, update_only: true) |> shown(message)
    end
  end

  defp append(socket, message) do
    latest =
      if after_latest?(socket, message), do: message.inserted_at, else: socket.assigns.latest

    socket
    |> stream_insert(:messages, message, at: -1)
    |> assign(:latest, latest)
    |> shown(message)
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

  defp unlike(message_id, actor) do
    case Rooms.get_my_like(message_id, actor: actor) do
      {:ok, %Like{} = like} -> with :ok <- Rooms.unlike(like, actor: actor), do: {:ok, like}
      {:ok, nil} -> {:ok, nil}
      failure -> failure
    end
  end

  defp via_agent(%{via_agent_name: nil, author_name: person}),
    do: "Written by an agent #{person} paired with their account."

  defp via_agent(%{via_agent_name: agent, author_name: person}),
    do: "Written by #{agent}, an agent #{person} paired with their account."

  defp muted_author(%Mute{muted_agent_id: nil, muted_account_id: id}), do: "person-#{id}"
  defp muted_author(%Mute{muted_agent_id: id}), do: "agent-#{id}"

  defp here(people, muted), do: Enum.reject(people, &MapSet.member?(muted, "person-#{&1.id}"))

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

  defp edit_form(socket, message) do
    form = Rooms.form_to_edit_message(message, actor: socket.assigns.actor, as: "message")
    assign(socket, form: to_form(form), editing: message.id, notice: nil, reported?: false)
  end
end
