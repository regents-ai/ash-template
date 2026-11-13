defmodule AshTemplateWeb.DmsLive do
  @moduledoc """
  Direct messages (`AshTemplate.Dms`): the reader's conversations in the shell's
  sidebar, newest message first, with the ones they blocked folded under
  "Blocked", and the one open, a page of messages at a time, with its message
  box and its Block button. A conversation starts from Message on a room
  message someone wrote.

  Sending never touches the list directly. Each message and each block is
  published on both people's topic (`AshTemplate.Dms.topic/1`); the shell hands
  each on here as `send_update(DmsLive, id: "dms", change: {event, payload})`.
  A message moves only its own conversation to the top of its list, read as
  the reader; a block reads both lists again. The shell holds the open
  conversation and reads it again after a block.

  The conversations and messages live in streams; the page keeps only what it
  renders of each and, for the open conversation, the cursor of its oldest
  message shown and whether older ones are left.
  """

  use AshTemplateWeb, :live_component

  import AshTemplateWeb.Components.PageHead

  alias AshTemplate.Actors.Human
  alias AshTemplate.Dms
  alias AshTemplate.Dms.Message
  alias AshTemplate.PublicIdentity
  alias AshTemplateWeb.Components.Shell
  alias AshTemplateWeb.FormErrors
  alias AshTemplateWeb.Live.Session
  alias AshTemplateWeb.Read
  alias Regent.Primitives

  @impl true
  def mount(socket) do
    {:ok,
     socket
     |> Session.check_component_lease(&take_account/2)
     |> assign(
       actor: nil,
       me: nil,
       conversation: nil,
       conversations: %Read{},
       blocked: %Read{},
       messages: %Read{},
       older: %Read{},
       paging: nil,
       form: nil,
       notice: nil
     )
     |> stream(:conversations, [])
     |> stream_configure(:messages, dom_id: &message_id/1)
     |> stream(:messages, [])}
  end

  # A new message moves its conversation to the top of the reader's list, and
  # reaches the open conversation at its end; one the other person sent rises
  # into place there (`Conversation`).
  @impl true
  def update(%{change: {"send", %{conversation_id: id, message_id: message_id}}}, socket) do
    socket = relist(socket, id)

    # Read as the reader, so a message they may not read never shows.
    with %{id: ^id} <- socket.assigns.conversation,
         {:ok, %Message{} = message} <-
           Dms.get_dm(message_id, actor: socket.assigns.actor, load: [:mine]) do
      {:ok,
       socket
       |> stream_insert(:messages, shown_message(message), at: -1)
       |> arrived(message)}
    else
      _closed_or_gone -> {:ok, socket}
    end
  end

  def update(%{change: {_block, _payload}}, socket), do: {:ok, load_conversations(socket)}

  # The shell renders this with every update of its own, so the lists are read
  # again only for a different person, and the messages only for a different
  # conversation.
  def update(%{id: id, lease: lease, account: account, conversation: conversation}, socket) do
    actor = account && Human.for_account(account)
    previous = {socket.assigns.actor, conversation_id(socket.assigns.conversation)}
    socket = assign(socket, id: id, lease: lease, conversation: conversation, me: account)

    socket =
      if actor == socket.assigns.actor,
        do: socket,
        else: socket |> assign(:actor, actor) |> load_conversations()

    if {actor, conversation_id(conversation)} == previous,
      do: {:ok, socket},
      else: {:ok, load_messages(socket)}
  end

  @impl true
  def handle_event("validate", %{"message" => params}, socket),
    do: {:noreply, assign(socket, :form, AshPhoenix.Form.validate(socket.assigns.form, params))}

  def handle_event("send", %{"message" => params}, socket) do
    case AshPhoenix.Form.submit(socket.assigns.form, params: params) do
      {:ok, _message} ->
        {:noreply, socket |> assign(:notice, nil) |> new_form()}

      # A conversation that is gone has no field to show it under.
      {:error, form} ->
        notice = Keyword.get(AshPhoenix.Form.errors(form), :conversation_id)
        {:noreply, assign(socket, form: form, notice: notice)}
    end
  end

  def handle_event("block", _params, socket),
    do: change(socket, &Dms.block_conversation/2, "They couldn’t be blocked. Try again.")

  def handle_event("unblock", _params, socket),
    do: change(socket, &Dms.unblock_conversation/2, "They couldn’t be unblocked. Try again.")

  def handle_event(
        "older",
        _params,
        %{assigns: %{paging: %{more?: true, cursor: cursor}}} = socket
      ) do
    %{conversation: conversation, actor: actor} = socket.assigns

    {:noreply,
     socket
     |> Read.now(:older, owner(socket), fn -> messages(conversation.id, actor, after: cursor) end)
     |> show_older()}
  end

  # The shell reads the conversation again when the block is published.
  defp change(socket, change, retry) do
    case change.(socket.assigns.conversation, actor: socket.assigns.actor) do
      {:ok, _conversation} -> {:noreply, assign(socket, :notice, nil)}
      {:error, _failure} -> {:noreply, assign(socket, :notice, retry)}
    end
  end

  # The account as it reads now, before each event and each background result
  # (`Session.check_component_lease/2`).
  defp take_account(socket, account),
    do: assign(socket, actor: Human.for_account(account), me: account)

  @impl true
  def render(assigns) do
    ~H"""
    <article id="dms-page" class="account-page">
      <.portal id="dms-sidebar" target="#shell-sidebar-page">
        <div class="shell-sidebar__page">
          <Primitives.notice :if={@conversations.state in [:error, :stale]} tone="error">
            Your messages couldn’t be loaded. Refresh the page to try again.
          </Primitives.notice>
          <ul
            :if={@actor}
            id="dms-conversations"
            class="shell-sidebar__list dms-list"
            data-state={@conversations.state}
            phx-update="stream"
          >
            <li id="dms-conversations-empty" class="shell-sidebar__empty">
              Nothing yet. Choose Message on something someone wrote in a room.
            </li>
            <li :for={{dom_id, conversation} <- @streams.conversations} id={dom_id}>
              <.conversation_link conversation={conversation} open={@conversation} />
            </li>
          </ul>
          <details :if={@actor && @blocked.value not in [nil, []]} class="dms-blocked">
            <summary>Blocked ({length(@blocked.value)})</summary>
            <ul class="shell-sidebar__list dms-list">
              <li :for={conversation <- @blocked.value}>
                <.conversation_link conversation={conversation} open={@conversation} />
              </li>
            </ul>
          </details>
          <p :if={!@actor} class="shell-sidebar__empty">Sign in to see your messages here.</p>
        </div>
      </.portal>
      <.page_head title={title(@conversation)}>
        <:heading :if={@conversation}>
          <Shell.person_name id="dms-title-person" person={@conversation.other_person} />
        </:heading>
        <:tip>
          Only the two of you can read these, and agents you each paired. Block someone to move
          them out of your messages.
        </:tip>
      </.page_head>

      <.signed_out :if={is_nil(@actor)} id="dms-signed-out">
        Sign in to see your messages.
      </.signed_out>

      <section :if={@actor && is_nil(@conversation)} id="dms-start" class="account-panel">
        <p>
          To message someone, open a room and choose Message on something they wrote.
        </p>
        <.link navigate={~p"/rooms/general"} class="dms-start__link">Open the General room</.link>
      </section>

      <section
        :if={@actor && @conversation}
        id="dms-conversation"
        class="account-panel rooms-conversation"
        aria-labelledby="dms-messages-title"
        phx-hook="Conversation"
      >
        <div class="dms-head">
          <h2 id="dms-messages-title" class="visually-hidden">
            Messages with {PublicIdentity.words(@conversation.other_person)}
          </h2>
          <Primitives.button
            :if={!@conversation.blocked}
            id="dms-block"
            type="button"
            variant="secondary"
            phx-click="block"
            phx-target={@myself}
            data-confirm={"Block #{PublicIdentity.words(@conversation.other_person)}? Their messages still arrive, under Blocked, and they aren’t told."}
            data-confirm-action="Block"
          >
            Block
          </Primitives.button>
        </div>

        <Primitives.notice :if={@conversation.blocked} tone="warning">
          You blocked
          <Shell.person_name id="dms-blocked-person" person={@conversation.other_person} />.
          Their messages still arrive here.
          <button
            id="dms-unblock"
            type="button"
            class="dms-unblock"
            phx-click="unblock"
            phx-target={@myself}
          >
            Unblock
          </button>
        </Primitives.notice>

        <div
          class="rooms-scroller"
          role="log"
          aria-labelledby="dms-messages-title"
          tabindex="0"
          data-conversation-scroller
        >
          <div class="rooms-scroller__inner">
            <Primitives.button
              :if={@paging && @paging.more?}
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
              id="dms-messages"
              class="rooms-messages"
              data-state={@messages.state}
              data-conversation-messages
              phx-update="stream"
            >
              <li id="dms-messages-empty" class="rooms-empty rg-muted">
                No messages yet. Say hello.
              </li>
              <li
                :for={{dom_id, message} <- @streams.messages}
                id={dom_id}
                class="rooms-message"
                data-mine={message.mine}
              >
                <Shell.account_picture
                  id={"#{dom_id}-picture"}
                  class="rooms-avatar"
                  squares={picture_of(message, @me, @conversation).squares}
                  picture={picture_of(message, @me, @conversation).picture}
                  size={36}
                />
                <div class="rooms-message__main">
                  <p class="rooms-message__meta">
                    <bdi :if={message.mine} class="rooms-message__author">You</bdi>
                    <Shell.person_name
                      :if={!message.mine}
                      id={"#{dom_id}-author"}
                      class="rooms-message__author"
                      person={@conversation.other_person}
                    />
                    <span :if={message.via_agent_id} class="rooms-message__agent">Via agent</span>
                    <time datetime={DateTime.to_iso8601(message.inserted_at)}>
                      {RegentFormat.relative_time(message.inserted_at, DateTime.utc_now())}
                    </time>
                  </p>
                  <p class="rooms-body">{message.body}</p>
                </div>
              </li>
            </ol>
          </div>
        </div>

        <Primitives.notice :if={@notice} tone="warning">{@notice}</Primitives.notice>
        <Primitives.notice :if={@messages.state in [:error, :stale]} tone="error">
          This conversation couldn’t be loaded. Refresh the page to try again.
        </Primitives.notice>

        <.form
          for={@form}
          id="dms-message-form"
          class="rooms-composer"
          phx-change="validate"
          phx-submit="send"
          phx-target={@myself}
        >
          <Primitives.field
            :let={field}
            id="dms-message-body"
            label={"Message #{PublicIdentity.words(@conversation.other_person)}"}
            errors={FormErrors.messages(@form[:body])}
          >
            <textarea
              id={field.id}
              name={@form[:body].name}
              rows="2"
              maxlength="2000"
              phx-debounce="blur"
              aria-invalid={field.aria_invalid}
              aria-describedby={"dms-message-hint #{field.described_by}"}
            >{Phoenix.HTML.Form.normalize_value("textarea", @form[:body].value)}</textarea>
          </Primitives.field>
          <AshTemplateWeb.LiveConnection.offline
            id="dms-message-offline"
            controls="#dms-message-actions"
          />
          <fieldset id="dms-message-actions" class="rooms-composer__actions">
            <p id="dms-message-hint" class="visually-hidden">
              Enter sends. Shift+Enter starts a new line.
            </p>
            <Primitives.button type="submit" phx-disable-with="Sending…">Send</Primitives.button>
          </fieldset>
        </.form>
      </section>
    </article>
    """
  end

  attr :conversation, :map, required: true
  attr :open, :map, required: true

  # A person shown by their wallet keeps its copy icon, which a link cannot
  # hold: the address lies over the link's first line, where the link keeps the
  # same words for a screen reader.
  defp conversation_link(assigns) do
    ~H"""
    <.link
      patch={~p"/dms/#{@conversation.id}"}
      class="dms-list__item"
      aria-current={if conversation_id(@open) == @conversation.id, do: "page"}
    >
      <bdi :if={@conversation.other_person.name} class="dms-list__name">
        {@conversation.other_person.name}
      </bdi>
      <span :if={!@conversation.other_person.name} class="dms-list__name">
        <span class="visually-hidden">{PublicIdentity.words(@conversation.other_person)}</span>
      </span>
      <span :if={@conversation.last_body} class="dms-list__last rg-muted">
        {@conversation.last_body}
      </span>
    </.link>
    <Regent.Primitives.address
      :if={!@conversation.other_person.name}
      id={"dms-list-person-#{@conversation.id}"}
      class="dms-list__address"
      address={@conversation.other_person.wallet}
      label={@conversation.other_person.ens_name}
      variant="compact"
    />
    """
  end

  defp owner(%{assigns: %{conversation: conversation, actor: actor}}),
    do: {conversation_id(conversation), actor && actor.human_account_id}

  defp load_conversations(%{assigns: %{actor: nil}} = socket) do
    socket
    |> Read.clear(:conversations)
    |> Read.clear(:blocked)
    |> stream(:conversations, [], reset: true)
  end

  defp load_conversations(%{assigns: %{actor: actor}} = socket) do
    socket
    |> Read.now(:conversations, actor.human_account_id, fn ->
      conversations(false, actor)
    end)
    |> Read.now(:blocked, actor.human_account_id, fn -> conversations(true, actor) end)
    |> show_conversations()
  end

  # The reader's conversations as the list shows them, or the one `id` names.
  defp conversations(blocked?, actor, query \\ []) do
    with {:ok, conversations} <- Dms.list_conversations(blocked?, actor: actor, query: query),
         do: {:ok, Enum.map(conversations, &shown_conversation/1)}
  end

  defp shown_conversation(conversation),
    do: Map.take(conversation, [:id, :other_person, :last_body])

  # The stream keeps the list; the page keeps only whether it was read.
  defp show_conversations(%{assigns: %{conversations: %Read{state: state} = read}} = socket)
       when state in [:ready, :empty] do
    socket
    |> stream(:conversations, read.value, reset: true)
    |> assign(:conversations, %{read | value: nil})
  end

  defp show_conversations(socket), do: socket

  # The one conversation a message names, read as the reader through the list
  # it is in, moves to the top of that list. Nothing else is read.
  defp relist(%{assigns: %{actor: nil}} = socket, _id), do: socket

  defp relist(%{assigns: %{actor: actor, blocked: blocked}} = socket, id) do
    blocked? = Enum.any?(List.wrap(blocked.value), &(&1.id == id))

    case conversations(blocked?, actor, filter: [id: id]) do
      {:ok, [conversation]} when blocked? ->
        others = Enum.reject(blocked.value, &(&1.id == id))
        assign(socket, :blocked, %{blocked | value: [conversation | others]})

      {:ok, [conversation]} ->
        socket
        |> stream_delete(:conversations, conversation)
        |> stream_insert(:conversations, conversation, at: 0)

      _gone ->
        socket
    end
  end

  defp load_messages(%{assigns: %{actor: actor, conversation: conversation}} = socket)
       when is_nil(actor) or is_nil(conversation) do
    socket
    |> Read.clear(:messages)
    |> Read.clear(:older)
    |> assign(paging: nil, form: nil, notice: nil)
    |> stream(:messages, [], reset: true)
  end

  defp load_messages(%{assigns: %{actor: actor, conversation: conversation}} = socket) do
    socket
    |> Read.clear(:older)
    |> assign(:notice, nil)
    |> Read.now(:messages, owner(socket), fn -> messages(conversation.id, actor, []) end)
    |> show_messages()
    |> new_form()
  end

  # A page of the conversation, newest first: what the log shows of each
  # message, the oldest one's cursor and whether older ones are left.
  defp messages(conversation_id, actor, page) do
    with {:ok, page} <- Dms.list_dms(conversation_id, actor: actor, page: page) do
      {:ok,
       %{
         shown: Enum.map(page.results, &shown_message/1),
         paging: %{more?: page.more?, cursor: cursor(page.results)}
       }}
    end
  end

  defp cursor([]), do: nil
  defp cursor(results), do: List.last(results).__metadata__.keyset

  defp shown_message(message),
    do: Map.take(message, [:id, :mine, :via_agent_id, :inserted_at, :body])

  defp message_id(%{id: id}), do: "messages-#{id}"

  # The reader's own message is simply there; the other person's rises into place.
  defp arrived(socket, %{mine: true}), do: socket

  defp arrived(socket, message),
    do: push_event(socket, "conversation:arrived", %{id: message_id(message)})

  # The log reads oldest first. The stream keeps the messages; the page keeps
  # only where the next older page starts.
  defp show_messages(%{assigns: %{messages: %Read{state: :ready, value: value} = read}} = socket) do
    socket
    |> assign(messages: %{read | value: nil}, paging: value.paging)
    |> stream(:messages, Enum.reverse(value.shown), reset: true)
  end

  defp show_messages(socket), do: assign(socket, :paging, nil)

  defp show_older(%{assigns: %{older: %Read{state: :ready, value: value} = read}} = socket) do
    socket
    |> assign(older: %{read | value: nil}, paging: value.paging)
    |> stream(:messages, value.shown, at: 0)
  end

  defp show_older(socket), do: socket

  defp new_form(%{assigns: %{actor: actor, conversation: conversation}} = socket) do
    form =
      Message
      |> AshPhoenix.Form.for_create(:send,
        actor: actor,
        as: "message",
        prepare_params: fn params, _phase ->
          Map.put(params, "conversation_id", conversation.id)
        end
      )
      |> to_form()

    assign(socket, :form, form)
  end

  defp picture_of(%{mine: true}, me, _conversation),
    do: %{
      squares: PublicIdentity.squares(me),
      picture: PublicIdentity.picture(me)
    }

  defp picture_of(_message, _me, conversation), do: conversation.other_person

  defp conversation_id(nil), do: nil
  defp conversation_id(conversation), do: conversation.id

  defp title(nil), do: "Messages"
  defp title(conversation), do: PublicIdentity.words(conversation.other_person)
end
