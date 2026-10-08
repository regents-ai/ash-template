defmodule AshTemplateWeb.ChatLive do
  @moduledoc """
  Chat with the assistant (`AshTemplate.Chat`, from `mix ash_ai.gen.chat`) in
  the site's own look: the reader's conversations in the shell's sidebar, the
  one open, and a message box that starts a new conversation when none is open.

  Sending never touches the list directly. The person's message and each piece
  of the assistant's reply are published by the message's PubSub notifier; the
  shell holds the open conversation's subscription and hands each one on here
  as `send_update(ChatLive, id: "chat", change: message)`, and a conversation
  that is started or named arrives as `conversation_change:`. The same page in
  the generator's own look is `AshTemplateWeb.ChatOriginalLive`.
  """

  use AshTemplateWeb, :live_component

  alias AshTemplate.Actors.Human
  alias AshTemplate.Chat
  alias AshTemplateWeb.FormErrors
  alias AshTemplateWeb.Live.Session
  alias AshTemplateWeb.Read
  alias Regent.Primitives

  @impl true
  def mount(socket) do
    {:ok,
     socket
     |> Session.check_component_events(&take_account/2)
     |> assign(
       actor: nil,
       conversation: nil,
       conversations: %Read{},
       messages: %Read{},
       form: nil,
       writing?: false
     )
     |> stream(:conversations, [])
     |> stream(:messages, [])}
  end

  @impl true
  def update(%{change: message}, socket) do
    {:ok,
     socket
     |> stream_insert(:messages, message, at: -1)
     |> assign(:writing?, writing?(message))}
  end

  def update(%{conversation_change: conversation}, socket),
    do: {:ok, stream_insert(socket, :conversations, conversation, at: 0)}

  # The shell renders this with every update of its own, so the list is read
  # again only for a different person, and the messages only for a different
  # conversation.
  def update(%{id: id, lease: lease, account: account, conversation: conversation}, socket) do
    actor = account && Human.for_account(account)
    previous = {socket.assigns.actor, conversation_id(socket.assigns.conversation)}
    socket = assign(socket, id: id, lease: lease, conversation: conversation)

    socket =
      if actor == socket.assigns.actor,
        do: socket,
        else: socket |> assign(:actor, actor) |> load_conversations()

    if {actor, conversation_id(conversation)} == previous,
      do: {:ok, socket},
      else: {:ok, load_messages(socket)}
  end

  @impl true
  def handle_async(
        {Read, :conversations, generation} = name,
        result,
        %{assigns: %{conversations: %Read{generation: generation}}} = socket
      ) do
    {:noreply, socket |> Read.settle(name, result) |> show_conversations()}
  end

  def handle_async(
        {Read, :messages, generation} = name,
        result,
        %{assigns: %{messages: %Read{generation: generation}}} = socket
      ) do
    {:noreply, socket |> Read.settle(name, result) |> show_messages()}
  end

  def handle_async({Read, _name, _superseded}, _result, socket), do: {:noreply, socket}

  @impl true
  def handle_event("validate", %{"message" => params}, socket),
    do: {:noreply, assign(socket, :form, AshPhoenix.Form.validate(socket.assigns.form, params))}

  # The first message of a new chat starts its conversation, which then opens.
  def handle_event("send", %{"message" => params}, socket) do
    case AshPhoenix.Form.submit(socket.assigns.form, params: params) do
      {:ok, message} when is_nil(socket.assigns.conversation) ->
        {:noreply, push_patch(socket, to: ~p"/chat/#{message.conversation_id}")}

      {:ok, _message} ->
        {:noreply, new_form(socket)}

      {:error, form} ->
        {:noreply, assign(socket, :form, form)}
    end
  end

  # The account as it reads now, before each event
  # (`Session.check_component_events/2`).
  defp take_account(socket, account), do: assign(socket, :actor, Human.for_account(account))

  @impl true
  def render(assigns) do
    ~H"""
    <article id="chat-page" class="account-page">
      <.portal id="chat-sidebar" target="#shell-sidebar-page">
        <div class="shell-sidebar__page">
          <.link :if={@actor} patch={~p"/chat"} class="shell-sidebar__new">New chat</.link>
          <p :if={@conversations.state == :loading} class="shell-sidebar__empty">
            Loading your chats…
          </p>
          <Primitives.notice :if={@conversations.state in [:error, :stale]} tone="error">
            Your chats couldn’t be loaded. Refresh the page to try again.
          </Primitives.notice>
          <ul
            :if={@actor}
            id="chat-conversations"
            class="shell-sidebar__list"
            data-state={@conversations.state}
            phx-update="stream"
          >
            <li id="chat-conversations-empty" class="shell-sidebar__empty">
              Nothing yet. Your first message starts a chat.
            </li>
            <li :for={{dom_id, conversation} <- @streams.conversations} id={dom_id}>
              <.link patch={~p"/chat/#{conversation.id}"}>{title(conversation)}</.link>
            </li>
          </ul>
          <p :if={!@actor} class="shell-sidebar__empty">Sign in to see your chats here.</p>
        </div>
      </.portal>
      <header class="account-heading">
        <p class="account-kicker">Chat</p>
        <h1 tabindex="-1">{title(@conversation)}</h1>
        <p class="account-lede">
          Talk with the assistant. This one is a free stand-in: it doesn’t read what you
          write, but its replies arrive a few words at a time, the way a real one’s do.
        </p>
        <p class="chat-original">
          <.link navigate={~p"/chat/original"}>See this chat in Ash AI’s own look</.link>
        </p>
      </header>

      <div :if={is_nil(@actor)} class="account-panel chat-signed-out">
        <p>Sign in to chat with the assistant. Your conversations are yours alone.</p>
        <Primitives.button type="button" data-account-target="sign-in">Sign in</Primitives.button>
      </div>

      <section
        :if={@actor}
        id="chat-conversation"
        class="account-panel chat-conversation"
        aria-labelledby="chat-messages-title"
        phx-hook="Conversation"
      >
        <h2 id="chat-messages-title" class="visually-hidden">Messages</h2>

        <div
          class="chat-scroller"
          role="log"
          aria-labelledby="chat-messages-title"
          tabindex="0"
          data-conversation-scroller
        >
          <div class="chat-scroller__inner">
            <p :if={@messages.state == :loading} class="rg-muted chat-loading">
              Loading messages…
            </p>
            <ol
              id="chat-messages"
              class="chat-messages"
              data-state={if @conversation, do: @messages.state, else: :empty}
              data-conversation-messages
              phx-update="stream"
            >
              <li id="chat-messages-empty" class="chat-empty rg-muted">
                Ask anything to start.
              </li>
              <li
                :for={{dom_id, message} <- @streams.messages}
                id={dom_id}
                class="chat-message"
                data-source={message.source}
              >
                <p class="chat-message__author">{author(message.source)}</p>
                <div class="chat-message__body">{markdown(message.text)}</div>
              </li>
            </ol>
            <p :if={@writing?} class="chat-writing rg-muted" role="status">
              The assistant is writing…
            </p>
          </div>
        </div>

        <Primitives.notice :if={@messages.state in [:error, :stale]} tone="error">
          This chat couldn’t be loaded. Refresh the page to try again.
        </Primitives.notice>

        <.form
          for={@form}
          id="chat-message-form"
          class="chat-composer"
          phx-change="validate"
          phx-submit="send"
          phx-target={@myself}
        >
          <Primitives.field
            :let={field}
            id="chat-message-text"
            label="Message the assistant"
            errors={FormErrors.messages(@form[:text])}
          >
            <textarea
              id={field.id}
              name={@form[:text].name}
              rows="2"
              maxlength="4000"
              aria-invalid={field.aria_invalid}
              aria-describedby={"chat-message-hint #{field.described_by}"}
            >{Phoenix.HTML.Form.normalize_value("textarea", @form[:text].value)}</textarea>
          </Primitives.field>
          <div class="chat-composer__actions">
            <p id="chat-message-hint" class="chat-composer__hint rg-muted">
              Enter sends. Shift+Enter starts a new line.
            </p>
            <Primitives.button type="submit" phx-disable-with="Sending…">Send</Primitives.button>
          </div>
        </.form>
      </section>
    </article>
    """
  end

  defp load_conversations(%{assigns: %{actor: nil}} = socket),
    do: socket |> Read.clear(:conversations) |> stream(:conversations, [], reset: true)

  defp load_conversations(%{assigns: %{actor: actor}} = socket) do
    Read.start(socket, :conversations, actor.human_account_id, fn ->
      Chat.my_conversations(actor: actor)
    end)
  end

  defp load_messages(%{assigns: %{actor: actor, conversation: conversation}} = socket)
       when is_nil(actor) or is_nil(conversation) do
    socket
    |> Read.clear(:messages)
    |> stream(:messages, [], reset: true)
    |> assign(:writing?, false)
    |> new_form()
  end

  defp load_messages(%{assigns: %{actor: actor, conversation: conversation}} = socket) do
    socket
    |> Read.start(:messages, conversation.id, fn ->
      Chat.message_history(conversation.id, actor: actor)
    end)
    |> new_form()
  end

  defp show_conversations(%{assigns: %{conversations: %Read{state: state} = read}} = socket)
       when state in [:ready, :empty],
       do: stream(socket, :conversations, read.value, reset: true)

  defp show_conversations(socket), do: socket

  # The history comes newest first; the newest message says whether a reply is
  # still being written.
  defp show_messages(%{assigns: %{messages: %Read{state: state} = read}} = socket)
       when state in [:ready, :empty] do
    socket
    |> stream(:messages, Enum.reverse(read.value), reset: true)
    |> assign(:writing?, read.value |> List.first() |> writing?())
  end

  defp show_messages(socket), do: socket

  # A person's message waits for its reply; a reply is written until it is complete.
  defp writing?(nil), do: false
  defp writing?(%{source: :user}), do: true
  defp writing?(%{complete: complete}), do: !complete

  defp new_form(%{assigns: %{actor: nil}} = socket), do: assign(socket, :form, nil)

  defp new_form(%{assigns: %{actor: actor, conversation: conversation}} = socket) do
    arguments = if conversation, do: %{conversation_id: conversation.id}, else: %{}

    form =
      Chat.form_to_create_message(actor: actor, as: "message", private_arguments: arguments)

    assign(socket, :form, to_form(form))
  end

  defp conversation_id(nil), do: nil
  defp conversation_id(conversation), do: conversation.id

  defp title(nil), do: "New chat"
  defp title(%{title: nil}), do: "Untitled chat"
  defp title(%{title: title}), do: title

  defp author(:user), do: "You"
  defp author(:agent), do: "Assistant"

  # The assistant may answer in Markdown. The HTML is sanitized by MDEx, which
  # needs the raw HTML rendered first to sanitize it.
  # sobelow_skip ["XSS.Raw"]
  defp markdown(text) do
    text
    |> MDEx.to_html!(
      extension: [strikethrough: true, tagfilter: true, table: true, autolink: true],
      render: [unsafe: true],
      sanitize: MDEx.Document.default_sanitize_options()
    )
    |> Phoenix.HTML.raw()
  end
end
