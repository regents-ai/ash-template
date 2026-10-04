defmodule AshTemplateWeb.RoomsLive do
  @moduledoc """
  One chat room: its messages oldest at the top and newest at the bottom above
  the message box, a form bound to the message's own Ash actions, who is here
  now, and the people the reader has muted.

  Posting never touches the list directly. Every post, edit and delete reaches
  each open page of the room the same way: the message's PubSub notifier
  publishes it after the transaction commits, the shell holds the room's
  subscription and hands it on here as `send_update(RoomsLive, id: "rooms",
  change: {event, message})`. The shell also tracks who is here
  (`AshTemplateWeb.Presence`) and passes the list in as `people`.
  """

  use AshTemplateWeb, :live_component

  alias AshTemplate.Actors.Human
  alias AshTemplate.Rooms
  alias AshTemplate.Rooms.{Message, Mute, Room}
  alias AshTemplateWeb.Read
  alias Regent.Primitives

  @preview_lines 6
  @preview_characters 280

  @gone "That message is no longer here."

  @impl true
  def mount(socket) do
    {:ok,
     socket
     |> assign(
       actor: nil,
       room: nil,
       people: [],
       messages: %Read{},
       older: %Read{},
       page: nil,
       mutes: [],
       muted: MapSet.new(),
       form: nil,
       editing: nil,
       notice: nil
     )
     |> stream(:messages, [])}
  end

  @impl true
  def update(%{change: {event, message}}, socket), do: {:ok, apply_change(socket, event, message)}
  def update(%{mutes_changed: true}, socket), do: {:ok, load(socket)}

  # The shell renders this with every update of its own, so the room is read
  # again only when the room or the person reading it changes.
  def update(%{id: id, account: account, room: room, people: people}, socket) do
    actor = account && Human.for_account(account)
    socket = assign(socket, id: id, people: people)

    if {actor, room} == {socket.assigns.actor, socket.assigns.room},
      do: {:ok, socket},
      else: {:ok, socket |> assign(actor: actor, room: room) |> load()}
  end

  @impl true
  def handle_async(
        {Read, :messages, generation} = name,
        result,
        %{assigns: %{messages: %Read{generation: generation}}} = socket
      ) do
    {:noreply, socket |> Read.settle(name, result) |> show_messages()}
  end

  def handle_async(
        {Read, :older, generation} = name,
        result,
        %{assigns: %{older: %Read{generation: generation}}} = socket
      ) do
    {:noreply, socket |> Read.settle(name, result) |> show_older()}
  end

  def handle_async({Read, _name, _superseded}, _result, socket), do: {:noreply, socket}

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
    {:noreply, Read.start(socket, :older, owner(socket), fn -> Ash.page(page, :next) end)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <article id="rooms-page" class="account-page">
      <header class="account-heading">
        <p class="account-kicker">Rooms</p>
        <h1 tabindex="-1">{@room.name}</h1>
        <p class="account-lede">{@room.about}</p>
        <nav class="rooms-tabs" aria-label="Rooms">
          <.link
            :for={room <- Room.all()}
            patch={~p"/rooms/#{room.slug}"}
            aria-current={room.slug == @room.slug && "page"}
          >
            {room.name}
          </.link>
        </nav>
      </header>

      <div class="rooms-layout">
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
              <p :if={@messages.state == :loading} class="rg-muted rooms-loading">
                Loading messages…
              </p>

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
                  data-author={message.human_account_id}
                  data-at={DateTime.to_unix(message.inserted_at)}
                  phx-mounted={JS.ignore_attributes(["data-continued"])}
                >
                  <span
                    class="rooms-avatar"
                    data-tone={rem(message.human_account_id, 3)}
                    aria-hidden="true"
                  >
                    {initials(message.author_name)}
                  </span>
                  <div class="rooms-message__main">
                    <p class="rooms-message__meta">
                      <bdi class="rooms-message__author">{message.author_name}</bdi>
                      <time datetime={DateTime.to_iso8601(message.inserted_at)}>
                        {RegentFormat.relative_time(message.inserted_at, DateTime.utc_now())}
                      </time>
                    </p>
                    <.message_body id={dom_id} body={message.body} />
                    <p :if={message.edited_at} class="rooms-message__edited">Edited</p>
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
              errors={errors(@form[:body])}
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
            <div class="rooms-composer__actions">
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
            </div>
          </.form>
        </section>

        <aside class="rooms-side">
          <section class="account-panel" aria-labelledby="room-people-title">
            <h2 id="room-people-title">Here now</h2>
            <ul :if={here(@people, @muted) != []} class="rooms-people">
              <li :for={person <- here(@people, @muted)}><bdi>{person.name}</bdi></li>
            </ul>
            <p :if={here(@people, @muted) == []} class="rg-muted">
              Nobody signed in has this room open.
            </p>
          </section>

          <section :if={@actor} class="account-panel" aria-labelledby="room-mutes-title">
            <h2 id="room-mutes-title">People you’ve muted</h2>
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
        </aside>
      </div>
    </article>
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
  attr :message, Message, required: true
  attr :actor, Human, required: true
  attr :myself, :any, required: true

  # The author's own message offers Edit and Delete; anyone else's, Mute.
  defp message_menu(assigns) do
    assigns =
      assign(assigns, :own?, assigns.message.human_account_id == assigns.actor.human_account_id)

    ~H"""
    <details class="rooms-menu">
      <summary>
        <span aria-hidden="true">…</span>
        <span class="visually-hidden">Options for this message</span>
      </summary>
      <div class="rooms-menu__items" role="group" aria-label="Message options">
        <button
          :if={@own?}
          type="button"
          class="rooms-menu__item"
          phx-click={choose("edit", @message.id, @myself)}
        >
          Edit
        </button>
        <button
          :if={@own?}
          type="button"
          class="rooms-menu__item"
          phx-click={choose("delete", @message.id, @myself)}
          data-confirm="Delete this message?"
        >
          Delete
        </button>
        <button
          :if={!@own?}
          type="button"
          class="rooms-menu__item"
          phx-click={choose("mute", @message.id, @myself)}
          data-confirm={"Mute #{@message.author_name}? You won’t see their messages in any room until you unmute them."}
        >
          Mute <bdi>{@message.author_name}</bdi>
        </button>
      </div>
    </details>
    """
  end

  # Runs the choice and closes the menu it was chosen from.
  defp choose(event, id, target) do
    event
    |> JS.push(value: %{id: id}, target: target)
    |> JS.remove_attribute("open", to: {:closest, "details"})
  end

  defp owner(%{assigns: %{room: room, actor: actor}}),
    do: {room.slug, actor && actor.human_account_id}

  defp load(%{assigns: %{room: room, actor: actor}} = socket) do
    socket
    |> Read.clear(:older)
    |> Read.start(:messages, owner(socket), fn -> read_room(room, actor) end)
    |> new_form()
  end

  # A visitor has muted nobody. A signed-in reader's mutes are read with the
  # messages, so the two always agree.
  defp read_room(room, nil) do
    with {:ok, page} <- Rooms.list_room_messages(room.slug),
         do: {:ok, %{mutes: [], page: page}}
  end

  defp read_room(room, actor) do
    with {:ok, mutes} <- Rooms.list_my_mutes(actor: actor),
         {:ok, page} <- Rooms.list_room_messages(room.slug, actor: actor),
         do: {:ok, %{mutes: mutes, page: page}}
  end

  # A failed read keeps the messages already on the page, so only a read that
  # landed replaces them.
  defp show_messages(%{assigns: %{messages: %Read{state: :ready, value: value}}} = socket) do
    socket
    |> assign(
      page: value.page,
      mutes: value.mutes,
      muted: MapSet.new(value.mutes, & &1.muted_account_id)
    )
    |> stream(:messages, Enum.reverse(value.page.results), reset: true)
  end

  defp show_messages(socket), do: socket

  # A page of older messages comes newest first, so putting each one at the top
  # in turn leaves them in order above the ones already shown.
  defp show_older(%{assigns: %{older: %Read{state: :ready, value: page}}} = socket) do
    socket
    |> assign(:page, page)
    |> stream(:messages, page.results, at: 0)
  end

  defp show_older(socket), do: socket

  defp apply_change(socket, "destroy", message) do
    socket = stream_delete(socket, :messages, message)
    if socket.assigns.editing == message.id, do: new_form(socket), else: socket
  end

  defp apply_change(socket, event, message) do
    cond do
      MapSet.member?(socket.assigns.muted, message.human_account_id) -> socket
      event == "post" -> stream_insert(socket, :messages, message, at: -1)
      event == "edit" -> stream_insert(socket, :messages, message, update_only: true)
    end
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

  defp here(people, muted), do: Enum.reject(people, &MapSet.member?(muted, &1.id))

  defp new_form(%{assigns: %{actor: nil}} = socket), do: assign(socket, form: nil, editing: nil)

  defp new_form(%{assigns: %{actor: actor, room: room}} = socket) do
    form =
      AshPhoenix.Form.for_create(Message, :post,
        actor: actor,
        as: "message",
        prepare_params: fn params, _phase -> Map.put(params, "room", room.slug) end
      )

    assign(socket, form: to_form(form), editing: nil, notice: nil)
  end

  defp edit_form(socket, message) do
    form = AshPhoenix.Form.for_update(message, :edit, actor: socket.assigns.actor, as: "message")
    assign(socket, form: to_form(form), editing: message.id, notice: nil)
  end

  defp errors(field) do
    if used_input?(field), do: Enum.map(field.errors, &message/1), else: []
  end

  defp message({message, values}) do
    Enum.reduce(values, message, fn {key, value}, message ->
      String.replace(message, "%{#{key}}", to_string(value))
    end)
  end
end
