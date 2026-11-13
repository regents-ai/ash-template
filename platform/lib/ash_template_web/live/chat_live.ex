defmodule AshTemplateWeb.ChatLive do
  @moduledoc """
  Chat with the assistant (`AshTemplate.Chat`, from `mix ash_ai.gen.chat`) in
  the site's own look: the reader's conversations in the shell's sidebar, the
  one open, and a message box that starts a new conversation when none is open.

  Sending never touches the list directly. The person's message and the
  assistant's reply are published by the message's PubSub notifier: the reply
  when it starts, empty, and when it is whole. The shell holds the open
  conversation's subscription and hands each one on here as
  `send_update(ChatLive, id: "chat", change: message)`, each piece of a reply
  being written as `piece:`, and a conversation that is started or named as
  `conversation_change:`. A reply this page saw start shows its pieces as they
  come (the `.ChatReply` hook); one already under way when the page opened shows
  only that the assistant is writing, until the whole reply arrives.

  The page keeps what it shows of the latest page of chats and of messages, and
  the cursor for the older ones, never the records; the rest is in its streams.
  """

  use AshTemplateWeb, :live_component

  import AshTemplateWeb.Components.PageHead

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
     |> Session.check_component_lease(&take_account/2)
     |> assign(
       actor: nil,
       conversation: nil,
       conversations: %Read{},
       older_chats: %Read{},
       chats_cursor: nil,
       messages: %Read{},
       older_messages: %Read{},
       messages_cursor: nil,
       form: nil,
       writing?: false
     )
     |> stream(:conversations, [])
     |> stream_configure(:messages, dom_id: &message_id/1)
     |> stream(:messages, [])}
  end

  @impl true
  def update(%{change: message}, socket) do
    {:ok,
     socket
     |> stream_insert(:messages, message, at: -1)
     |> assign(:writing?, writing?(message))
     |> arrived(message)}
  end

  def update(%{piece: piece}, socket), do: {:ok, push_event(socket, "chat-piece", piece)}

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

  def handle_event("older_messages", _params, %{assigns: %{messages_cursor: cursor}} = socket)
      when is_binary(cursor) do
    %{actor: actor, conversation: conversation} = socket.assigns

    {:noreply,
     socket
     |> Read.now(:older_messages, conversation.id, fn ->
       Chat.message_history(conversation.id, actor: actor, page: [after: cursor])
       |> shown(&message/1)
     end)
     |> show_older_messages()}
  end

  def handle_event("older_chats", _params, %{assigns: %{chats_cursor: cursor}} = socket)
      when is_binary(cursor) do
    actor = socket.assigns.actor

    {:noreply,
     socket
     |> Read.now(:older_chats, actor.human_account_id, fn ->
       Chat.my_conversations(actor: actor, page: [after: cursor]) |> shown(&chat/1)
     end)
     |> show_older_chats()}
  end

  # The account as it reads now, before each event and each background result
  # (`Session.check_component_lease/2`).
  defp take_account(socket, account), do: assign(socket, :actor, Human.for_account(account))

  @impl true
  def render(assigns) do
    ~H"""
    <article id="chat-page" class="account-page">
      <script :type={Phoenix.LiveView.ColocatedHook} name=".ChatReply">
        // A reply being written: each piece the server sends for it is added as
        // plain text, until the whole reply replaces this element.
        export default {
          mounted() {
            this.handleEvent("chat-piece", ({id, text}) => {
              if (id === this.el.dataset.reply) this.el.append(text)
            })
          }
        }
      </script>
      <.portal id="chat-sidebar" target="#shell-sidebar-page">
        <div class="shell-sidebar__page">
          <.link :if={@actor} patch={~p"/chat"} class="shell-sidebar__new">New chat</.link>
          <Primitives.notice :if={@conversations.state in [:error, :stale]} tone="error">
            Your chats couldn’t be loaded. Refresh the page to try again.
          </Primitives.notice>
          <ul
            :if={@actor}
            id="chat-conversations"
            class="shell-sidebar__list"
            data-state={list_state(@conversations)}
            phx-update="stream"
          >
            <li id="chat-conversations-empty" class="shell-sidebar__empty">
              Nothing yet. Your first message starts a chat.
            </li>
            <li :for={{dom_id, conversation} <- @streams.conversations} id={dom_id}>
              <.link patch={~p"/chat/#{conversation.id}"}>{title(conversation)}</.link>
            </li>
          </ul>
          <Primitives.button
            :if={@actor && @chats_cursor}
            id="chat-older-chats"
            variant="quiet"
            class="chat-older"
            phx-click="older_chats"
            phx-target={@myself}
            phx-disable-with="Loading…"
          >
            Older chats
          </Primitives.button>
          <Primitives.notice :if={@older_chats.state in [:error, :stale]} tone="error">
            Older chats couldn’t be loaded. Try again.
          </Primitives.notice>
          <p :if={!@actor} class="shell-sidebar__empty">Sign in to see your chats here.</p>
        </div>
      </.portal>
      <.page_head title={title(@conversation)}>
        <:tip>
          This assistant is a free stand-in: it doesn’t read what you write, but its replies
          arrive a few words at a time, the way a real one’s do.
        </:tip>
      </.page_head>

      <.signed_out :if={is_nil(@actor)} id="chat-signed-out">
        Sign in to chat with the assistant.
      </.signed_out>

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
            <Primitives.button
              :if={@conversation && @messages_cursor}
              id="chat-older-messages"
              variant="secondary"
              class="chat-older"
              phx-click="older_messages"
              phx-target={@myself}
              phx-disable-with="Loading…"
            >
              Older messages
            </Primitives.button>
            <Primitives.notice :if={@older_messages.state in [:error, :stale]} tone="error">
              Older messages couldn’t be loaded. Try again.
            </Primitives.notice>
            <ol
              id="chat-messages"
              class="chat-messages"
              data-state={if @conversation, do: list_state(@messages), else: :empty}
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
                <div :if={message.complete} class="chat-message__body">
                  {markdown(message.text)}
                </div>
                <div
                  :if={!message.complete}
                  id={"#{dom_id}-writing"}
                  class="chat-message__body"
                  data-reply={message.id}
                  phx-hook=".ChatReply"
                  phx-update="ignore"
                  phx-no-format
                ></div>
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
            label="Message"
            errors={FormErrors.messages(@form[:text])}
          >
            <textarea
              id={field.id}
              name={@form[:text].name}
              rows="2"
              maxlength="4000"
              phx-debounce="blur"
              aria-invalid={field.aria_invalid}
              aria-describedby={"chat-message-hint #{field.described_by}"}
            >{Phoenix.HTML.Form.normalize_value("textarea", @form[:text].value)}</textarea>
          </Primitives.field>
          <AshTemplateWeb.LiveConnection.offline
            id="chat-message-offline"
            controls="#chat-message-actions"
          />
          <fieldset id="chat-message-actions" class="chat-composer__actions">
            <p id="chat-message-hint" class="visually-hidden">
              Enter sends. Shift+Enter starts a new line.
            </p>
            <Primitives.button type="submit" phx-disable-with="Sending…">Send</Primitives.button>
          </fieldset>
        </.form>
      </section>
    </article>
    """
  end

  defp load_conversations(%{assigns: %{actor: nil}} = socket) do
    socket
    |> Read.clear(:conversations)
    |> Read.clear(:older_chats)
    |> assign(:chats_cursor, nil)
    |> stream(:conversations, [], reset: true)
  end

  defp load_conversations(%{assigns: %{actor: actor}} = socket) do
    socket
    |> Read.clear(:older_chats)
    |> Read.now(:conversations, actor.human_account_id, fn ->
      Chat.my_conversations(actor: actor) |> shown(&chat/1)
    end)
    |> show_conversations()
  end

  defp load_messages(%{assigns: %{actor: actor, conversation: conversation}} = socket)
       when is_nil(actor) or is_nil(conversation) do
    socket
    |> Read.clear(:messages)
    |> Read.clear(:older_messages)
    |> assign(messages_cursor: nil, writing?: false)
    |> stream(:messages, [], reset: true)
    |> new_form()
  end

  defp load_messages(%{assigns: %{actor: actor, conversation: conversation}} = socket) do
    socket
    |> Read.clear(:older_messages)
    |> Read.now(:messages, conversation.id, fn ->
      Chat.message_history(conversation.id, actor: actor) |> shown(&message/1)
    end)
    |> show_messages()
    |> new_form()
  end

  # A page of chats or messages as the page keeps it: what each row shows, newest
  # first, and the cursor for the rows older than these, nil when there are none.
  defp shown({:ok, page}, row) do
    rows = page.results |> Enum.map(row) |> Enum.reject(&is_nil/1)
    older = if page.more?, do: List.last(page.results).__metadata__.keyset
    {:ok, %{rows: rows, older: older}}
  end

  defp shown(error, _row), do: error

  defp chat(conversation), do: %{id: conversation.id, title: conversation.title}

  # A reply still being written has no text saved yet, so it is left out: the
  # page shows that the assistant is writing until the whole reply arrives.
  defp message(%{source: :agent, complete: false}), do: nil

  defp message(message),
    do: %{id: message.id, source: message.source, text: message.text, complete: true}

  # A failed read keeps what is already on the page, so only a read that landed
  # replaces it.
  defp show_conversations(%{assigns: %{conversations: %Read{state: :ready} = read}} = socket) do
    socket
    |> assign(:chats_cursor, read.value.older)
    |> stream(:conversations, read.value.rows, reset: true)
  end

  defp show_conversations(socket), do: socket

  defp show_older_chats(%{assigns: %{older_chats: %Read{state: :ready} = read}} = socket) do
    socket
    |> assign(:chats_cursor, read.value.older)
    |> stream(:conversations, read.value.rows, at: -1)
  end

  defp show_older_chats(socket), do: socket

  # The history comes newest first; the newest message says whether a reply is
  # still being written.
  defp show_messages(%{assigns: %{messages: %Read{state: :ready} = read}} = socket) do
    socket
    |> assign(messages_cursor: read.value.older, writing?: writing?(List.first(read.value.rows)))
    |> stream(:messages, Enum.reverse(read.value.rows), reset: true)
  end

  defp show_messages(socket), do: socket

  # Older messages come newest first, so putting each one at the top in turn
  # leaves them in order above the ones already shown.
  defp show_older_messages(%{assigns: %{older_messages: %Read{state: :ready} = read}} = socket) do
    socket
    |> assign(:messages_cursor, read.value.older)
    |> stream(:messages, read.value.rows, at: 0)
  end

  defp show_older_messages(socket), do: socket

  # A page that landed with no rows is empty.
  defp list_state(%Read{state: :ready, value: %{rows: []}}), do: :empty
  defp list_state(%Read{state: state}), do: state

  # A person's message waits for its reply; a reply is written until it is complete.
  defp writing?(nil), do: false
  defp writing?(%{source: :user}), do: true
  defp writing?(%{complete: complete}), do: !complete

  defp message_id(%{id: id}), do: "messages-#{id}"

  # A reply rises into place as it starts; the person's own message, and the
  # reply made whole where it already stands, are simply there.
  defp arrived(socket, %{source: :agent, complete: false} = message),
    do: push_event(socket, "conversation:arrived", %{id: message_id(message)})

  defp arrived(socket, _message), do: socket

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
    |> AshTemplate.Markdown.to_html!(
      extension: [strikethrough: true, tagfilter: true, table: true, autolink: true],
      render: [unsafe: true],
      # A code block too wide for the panel scrolls sideways, so a keyboard can
      # focus it to scroll it.
      sanitize:
        Keyword.put(MDEx.Document.default_sanitize_options(), :set_tag_attribute_values, %{
          "pre" => %{"tabindex" => "0"}
        })
    )
    |> Phoenix.HTML.raw()
  end
end
