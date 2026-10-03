defmodule AshTemplateWeb.RoomsLive do
  @moduledoc """
  One chat room: its messages newest first, a post form bound to the message's
  own Ash actions, who is here now, and the people the reader has muted.

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
  alias Regent.{Discussion, Primitives}

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
      {:ok, %Message{} = message} -> {:noreply, edit_form(socket, message)}
      _gone -> {:noreply, assign(socket, :notice, @gone)}
    end
  end

  def handle_event("cancel", _params, socket), do: {:noreply, new_form(socket)}

  def handle_event("delete", %{"id" => id}, socket) do
    actor = socket.assigns.actor

    with {:ok, %Message{} = message} <- Rooms.get_message(id, actor: actor),
         :ok <- Rooms.delete_message(message, actor: actor) do
      {:noreply, assign(socket, :notice, nil)}
    else
      _gone -> {:noreply, assign(socket, :notice, @gone)}
    end
  end

  def handle_event("mute", %{"id" => id}, socket) do
    case Rooms.mute_author(id, actor: socket.assigns.actor) do
      {:ok, _mute} -> {:noreply, assign(socket, :notice, nil)}
      {:error, _refused} -> {:noreply, assign(socket, :notice, @gone)}
    end
  end

  def handle_event("unmute", %{"id" => id}, socket) do
    actor = socket.assigns.actor

    with {:ok, %Mute{} = mute} <- Rooms.get_my_mute(id, actor: actor),
         :ok <- Rooms.unmute(mute, actor: actor) do
      {:noreply, assign(socket, :notice, nil)}
    else
      _gone -> {:noreply, assign(socket, :notice, "That person is no longer muted.")}
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
        <section class="account-panel rooms-conversation" aria-labelledby="room-messages-title">
          <h2 id="room-messages-title">Messages</h2>

          <div :if={is_nil(@actor)} class="rooms-signed-out">
            <p>Anyone can read along. Sign in to post.</p>
            <Primitives.button type="button" data-account-target="sign-in">Sign in</Primitives.button>
          </div>

          <.form
            :if={@actor}
            for={@form}
            id="room-message-form"
            class="rooms-form"
            phx-change="validate"
            phx-submit="save"
            phx-target={@myself}
          >
            <Primitives.field
              :let={field}
              id="room-message-body"
              label={if @editing, do: "Edit your message", else: "Message"}
              errors={errors(@form[:body])}
            >
              <textarea
                id={field.id}
                name={@form[:body].name}
                rows="3"
                maxlength="2000"
                phx-debounce="300"
                aria-invalid={field.aria_invalid}
                aria-describedby={field.described_by}
              >{Phoenix.HTML.Form.normalize_value("textarea", @form[:body].value)}</textarea>
            </Primitives.field>
            <div class="rooms-form__actions">
              <Primitives.button type="submit" phx-disable-with="Posting…">
                {if @editing, do: "Save changes", else: "Post"}
              </Primitives.button>
              <Primitives.button
                :if={@editing}
                type="button"
                variant="secondary"
                phx-click="cancel"
                phx-target={@myself}
              >
                Cancel
              </Primitives.button>
            </div>
          </.form>

          <Primitives.notice :if={@notice} tone="warning">{@notice}</Primitives.notice>
          <Primitives.notice :if={@messages.state in [:error, :stale]} tone="error">
            This room couldn’t be loaded. Refresh the page to try again.
          </Primitives.notice>
          <p :if={@messages.state == :loading} class="rg-muted">Loading messages…</p>

          <ol
            id="room-messages"
            class="rg-sheet rg-discussion__replies rooms-messages"
            role="list"
            data-state={@messages.state}
            phx-update="stream"
          >
            <li id="room-messages-empty" class="rooms-empty rg-muted">
              No messages yet. Say hello.
            </li>
            <Discussion.post
              :for={{dom_id, message} <- @streams.messages}
              id={dom_id}
              author={message.author_name}
              at={message.inserted_at}
              ago={RegentFormat.relative_time(message.inserted_at, DateTime.utc_now())}
              href={"##{dom_id}"}
            >
              <:avatar>
                <span class="rooms-avatar" aria-hidden="true">
                  {initials(message.author_name)}
                </span>
              </:avatar>
              <:label :if={message.edited_at}>
                <Discussion.label>edited</Discussion.label>
              </:label>
              <p class="rooms-body">{message.body}</p>
              <:actions :if={@actor}>
                <.message_actions message={message} actor={@actor} myself={@myself} />
              </:actions>
            </Discussion.post>
          </ol>

          <Primitives.button
            :if={@page && @page.more?}
            type="button"
            variant="secondary"
            phx-click="older"
            phx-target={@myself}
            phx-disable-with="Loading…"
          >
            Show older messages
          </Primitives.button>
          <Primitives.notice :if={@older.state in [:error, :stale]} tone="error">
            Older messages couldn’t be loaded. Try again.
          </Primitives.notice>
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

  attr :message, Message, required: true
  attr :actor, Human, required: true
  attr :myself, :any, required: true

  defp message_actions(
         %{message: %{human_account_id: author}, actor: %{human_account_id: author}} = assigns
       ) do
    ~H"""
    <Primitives.button
      type="button"
      variant="quiet"
      phx-click="edit"
      phx-value-id={@message.id}
      phx-target={@myself}
    >
      Edit
    </Primitives.button>
    <Primitives.button
      type="button"
      variant="quiet"
      phx-click="delete"
      phx-value-id={@message.id}
      phx-target={@myself}
      data-confirm="Delete this message?"
    >
      Delete
    </Primitives.button>
    """
  end

  defp message_actions(assigns) do
    ~H"""
    <Primitives.button
      type="button"
      variant="quiet"
      phx-click="mute"
      phx-value-id={@message.id}
      phx-target={@myself}
      data-confirm={"Mute #{@message.author_name}? You won’t see their messages in any room until you unmute them."}
    >
      Mute
    </Primitives.button>
    """
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
    |> stream(:messages, value.page.results, reset: true)
  end

  defp show_messages(socket), do: socket

  defp show_older(%{assigns: %{older: %Read{state: :ready, value: page}}} = socket) do
    socket
    |> assign(:page, page)
    |> stream(:messages, page.results, at: -1)
  end

  defp show_older(socket), do: socket

  defp apply_change(socket, "destroy", message) do
    socket = stream_delete(socket, :messages, message)
    if socket.assigns.editing == message.id, do: new_form(socket), else: socket
  end

  defp apply_change(socket, event, message) do
    cond do
      MapSet.member?(socket.assigns.muted, message.human_account_id) -> socket
      event == "post" -> stream_insert(socket, :messages, message, at: 0)
      event == "edit" -> stream_insert(socket, :messages, message, update_only: true)
    end
  end

  # A short wallet address starts with "0x" for everyone, so its letters start after.
  defp initials(name), do: name |> String.replace_prefix("0x", "") |> RegentFormat.monogram("?")

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
