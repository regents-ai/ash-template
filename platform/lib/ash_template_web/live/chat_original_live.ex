defmodule AshTemplateWeb.ChatOriginalLive do
  @moduledoc """
  The chat page `mix ash_ai.gen.chat` generates, kept in its own Tailwind and
  DaisyUI look (`assets/ash_ai_chat/`, loaded by this page alone) beside the
  site's own `AshTemplateWeb.ChatLive`. Both read and write the same
  conversations.

  Changed from the generated page: it lives at `/chat/original`, its actor is
  the signed-in `AshTemplate.Actors.Human`, it brings the `icon` and `flash`
  components a new Phoenix app would have, a visitor is sent to sign in, the
  Ash AI logo is an icon (the page loads no outside images), the message
  history is read as the signed-in person, the message box clears after each
  send, and the newest conversation is listed first (the list is reversed on
  screen, and `my_conversations` reads newest first).
  """

  use AshTemplateWeb, :live_view

  alias AshTemplate.Actors.Human
  alias AshTemplateWeb.PublicDocuments

  @chat_ui_tools AshAi.ChatUI.Tools
  def render(assigns) do
    ~H"""
    <div class="drawer md:drawer-open bg-base-200 min-h-dvh max-h-dvh">
      <input id="ash-ai-drawer" type="checkbox" class="drawer-toggle" />
      <div class="drawer-content flex flex-col">
        <.flash kind={:info} flash={@flash} />
        <.flash kind={:error} flash={@flash} />
        <div
          :if={Phoenix.Flash.get(@flash, :warning)}
          class="alert alert-warning m-4 mb-0 text-sm"
        >
          {Phoenix.Flash.get(@flash, :warning)}
        </div>
        <div class="navbar bg-base-300 w-full">
          <div class="flex-none md:hidden">
            <label for="ash-ai-drawer" aria-label="open sidebar" class="btn btn-square btn-ghost">
              <svg
                xmlns="http://www.w3.org/2000/svg"
                fill="none"
                viewBox="0 0 24 24"
                class="inline-block h-6 w-6 stroke-current"
              >
                <path
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  stroke-width="2"
                  d="M4 6h16M4 12h16M4 18h16"
                >
                </path>
              </svg>
            </label>
          </div>
          <span class="rounded-full bg-primary text-primary-content p-2" aria-hidden="true">
            <.icon name="hero-sparkles-solid" class="block" />
          </span>
          <div class="mx-2 flex-1 px-2">
            <p :if={@conversation}>{build_conversation_title_string(@conversation.title)}</p>
            <p class="text-xs">AshAi</p>
          </div>
          <.link navigate={~p"/chat"} class="btn btn-ghost btn-sm">Back to the template</.link>
        </div>
        <div :if={is_nil(@actor)} class="alert m-4">
          <.icon name="hero-user-circle" />
          <span>Sign in to chat with the assistant.</span>
          <.link navigate={~p"/chat"} class="btn btn-primary btn-sm">Sign in</.link>
        </div>
        <div class="flex-1 flex flex-col overflow-y-scroll bg-base-200 max-h-[calc(100dvh-8rem)]">
          <div
            id="message-container"
            phx-update="stream"
            class="flex-1 overflow-y-auto overflow-x-hidden px-4 py-2 flex flex-col-reverse"
          >
            <%= for {id, message} <- @streams.messages do %>
              <div
                id={id}
                class={[
                  "chat",
                  message.source == :user && "chat-end",
                  message.source == :agent && "chat-start"
                ]}
              >
                <div :if={message.source == :agent} class="chat-image avatar">
                  <div class="w-10 rounded-full bg-primary text-primary-content p-2">
                    <.icon name="hero-sparkles-solid" class="block" />
                  </div>
                </div>
                <div :if={message.source == :user} class="chat-image avatar avatar-placeholder">
                  <div class="w-10 rounded-full bg-base-300">
                    <.icon name="hero-user-solid" class="block" />
                  </div>
                </div>
                <div
                  :if={message.source == :agent && tool_calls(message) != []}
                  class="mt-2 flex w-full max-w-[36rem] min-w-0 flex-wrap gap-1 text-[11px] opacity-80"
                >
                  <%= for tool_call <- tool_calls(message) do %>
                    <span class="badge badge-outline badge-info max-w-full min-w-0 justify-start overflow-hidden text-ellipsis whitespace-nowrap">
                      tool: {tool_call.name}
                      <span :if={tool_call.arguments != %{}}>
                        ({tool_call.arguments_preview})
                      </span>
                    </span>
                  <% end %>
                </div>
                <div
                  :if={message.source == :agent && tool_results(message) != []}
                  class="chat-footer mt-1 flex w-full max-w-[36rem] min-w-0 flex-col gap-1"
                >
                  <%= for tool_result <- tool_results(message) do %>
                    <div class={[
                      "rounded max-w-full overflow-hidden px-2 py-1 text-xs leading-relaxed break-words",
                      tool_result.is_error && "bg-error/20",
                      !tool_result.is_error && "bg-base-300"
                    ]}>
                      <span class="font-semibold">
                        {if tool_result.is_error, do: "tool_error", else: "tool_result"}
                      </span>
                      <span :if={tool_result.name}> ({tool_result.name})</span>
                      <span class="break-all">
                        : {tool_result.content_preview}
                      </span>
                    </div>
                  <% end %>
                </div>
                <div :if={String.trim(message.text || "") != ""} class="chat-bubble">
                  {to_markdown(message.text || "")}
                </div>
              </div>
            <% end %>
          </div>
        </div>
        <div :if={@agent_responding} class="px-4 py-2 text-xs opacity-80 flex items-center gap-2">
          <span class="loading loading-dots loading-sm" />
          <span>AshAi is responding...</span>
        </div>
        <div class="p-4 border-t">
          <.form
            :let={form}
            for={@message_form}
            phx-change="validate_message"
            phx-submit="send_message"
            class="flex items-center gap-4"
          >
            <div class="flex-1">
              <input
                name={form[:text].name}
                value={form[:text].value}
                type="text"
                phx-mounted={JS.focus()}
                placeholder="Type your message..."
                class="input input-primary w-full mb-0"
                autocomplete="off"
              />
            </div>
            <button type="submit" class="btn btn-primary rounded-full">
              <.icon name="hero-paper-airplane" /> Send
            </button>
          </.form>
        </div>
      </div>

      <div class="drawer-side border-r bg-base-300 min-w-72">
        <div class="py-4 px-6">
          <div class="text-lg mb-4">
            Conversations
          </div>
          <div class="mb-4">
            <.link navigate={~p"/chat/original"} class="btn btn-primary btn-lg mb-2">
              <div class="rounded-full bg-primary-content text-primary w-6 h-6 flex items-center justify-center">
                <.icon name="hero-plus" />
              </div>
              <span>New Chat</span>
            </.link>
          </div>
          <ul class="flex flex-col-reverse" phx-update="stream" id="conversations-list">
            <%= for {id, conversation} <- @streams.conversations do %>
              <li id={id}>
                <.link
                  navigate={~p"/chat/original/#{conversation.id}"}
                  phx-click="select_conversation"
                  phx-value-id={conversation.id}
                  class={"block py-2 px-3 transition border-l-4 pl-2 mb-2 #{if @conversation && @conversation.id == conversation.id, do: "border-primary font-medium", else: "border-transparent"}"}
                >
                  {build_conversation_title_string(conversation.title)}
                </.link>
              </li>
            <% end %>
          </ul>
        </div>
      </div>
    </div>
    """
  end

  attr :name, :string, required: true
  attr :class, :any, default: nil

  # A Heroicon drawn by the Tailwind plugin in `assets/ash_ai_chat/heroicons.js`.
  defp icon(%{name: "hero-" <> _} = assigns) do
    ~H"""
    <span class={[@name, @class]} />
    """
  end

  attr :flash, :map, required: true
  attr :kind, :atom, values: [:info, :error]

  defp flash(assigns) do
    ~H"""
    <div
      :if={msg = Phoenix.Flash.get(@flash, @kind)}
      id={"flash-#{@kind}"}
      role="alert"
      class="toast toast-top toast-end z-50"
      phx-click={JS.push("lv:clear-flash", value: %{key: @kind}) |> JS.hide(to: "#flash-#{@kind}")}
    >
      <div class={[
        "alert w-80 sm:w-96 max-w-80 sm:max-w-96 text-wrap",
        @kind == :info && "alert-info",
        @kind == :error && "alert-error"
      ]}>
        <.icon :if={@kind == :info} name="hero-information-circle" class="size-5 shrink-0" />
        <.icon :if={@kind == :error} name="hero-exclamation-circle" class="size-5 shrink-0" />
        <p>{msg}</p>
        <div class="flex-1" />
        <button type="button" class="group self-start cursor-pointer" aria-label="close">
          <.icon name="hero-x-mark" class="size-5 opacity-40 group-hover:opacity-70" />
        </button>
      </div>
    </div>
    """
  end

  defp actor(%{principal: {:human, account}}), do: Human.for_account(account)
  defp actor(_access_context), do: nil

  def build_conversation_title_string(title) do
    cond do
      title == nil -> "Untitled conversation"
      is_binary(title) && String.length(title) > 25 -> String.slice(title, 0, 25) <> "..."
      is_binary(title) && String.length(title) <= 25 -> title
    end
  end

  def mount(_params, _session, socket) do
    socket = assign(socket, :actor, actor(socket.assigns.access_context))

    if connected?(socket) && socket.assigns.actor do
      AshTemplateWeb.Endpoint.subscribe(
        "chat:conversations:#{socket.assigns.actor.human_account_id}"
      )
    end

    conversations =
      if is_nil(socket.assigns.actor) do
        []
      else
        AshTemplate.Chat.my_conversations!(actor: socket.assigns.actor)
      end

    socket =
      socket
      |> assign(PublicDocuments.page("/chat/original"))
      |> stream(:conversations, Enum.reverse(conversations))
      |> assign(:agent_responding, false)
      |> assign(:tool_data_warning_shown?, false)
      |> assign(:messages, [])

    {:ok, socket, layout: false}
  end

  def handle_params(%{"conversation_id" => conversation_id}, _, socket) do
    if is_nil(socket.assigns.actor) do
      {:noreply,
       socket
       |> put_flash(:error, "You must sign in to access conversations")
       |> push_navigate(to: ~p"/chat/original")}
    else
      conversation =
        AshTemplate.Chat.get_conversation!(conversation_id, actor: socket.assigns.actor)

      messages =
        AshTemplate.Chat.message_history!(conversation.id,
          actor: socket.assigns.actor,
          stream?: true
        )

      cond do
        socket.assigns[:conversation] && socket.assigns[:conversation].id == conversation.id ->
          :ok

        socket.assigns[:conversation] ->
          AshTemplateWeb.Endpoint.unsubscribe("chat:messages:#{socket.assigns.conversation.id}")
          AshTemplateWeb.Endpoint.subscribe("chat:messages:#{conversation.id}")

        true ->
          AshTemplateWeb.Endpoint.subscribe("chat:messages:#{conversation.id}")
      end

      socket
      |> maybe_warn_tool_data(messages)
      |> assign(:conversation, conversation)
      |> assign(:agent_responding, agent_response_pending?(messages))
      |> stream(:messages, messages)
      |> assign_message_form()
      |> then(&{:noreply, &1})
    end
  end

  def handle_params(_, _, socket) do
    if socket.assigns[:conversation] do
      AshTemplateWeb.Endpoint.unsubscribe("chat:messages:#{socket.assigns.conversation.id}")
    end

    socket
    |> assign(:conversation, nil)
    |> assign(:agent_responding, false)
    |> stream(:messages, [])
    |> assign_message_form()
    |> then(&{:noreply, &1})
  end

  def handle_event("validate_message", %{"form" => params}, socket) do
    {:noreply,
     assign(socket, :message_form, AshPhoenix.Form.validate(socket.assigns.message_form, params))}
  end

  def handle_event("send_message", _params, %{assigns: %{actor: nil}} = socket),
    do: {:noreply, put_flash(socket, :error, "You must sign in to send messages")}

  def handle_event("send_message", %{"form" => params}, socket) do
    case AshPhoenix.Form.submit(socket.assigns.message_form, params: params) do
      {:ok, message} -> {:noreply, message_sent(socket, message)}
      {:error, form} -> {:noreply, assign(socket, :message_form, form)}
    end
  end

  def handle_info(
        %Phoenix.Socket.Broadcast{
          topic: "chat:messages:" <> conversation_id,
          payload: message
        },
        socket
      ) do
    if socket.assigns.conversation && socket.assigns.conversation.id == conversation_id do
      socket =
        socket
        |> maybe_warn_tool_data(message)
        |> stream_insert(:messages, message, at: 0)
        |> update_agent_responding(message)

      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  def handle_info(
        %Phoenix.Socket.Broadcast{
          topic: "chat:conversations:" <> _,
          payload: conversation
        },
        socket
      ) do
    socket =
      if socket.assigns.conversation && socket.assigns.conversation.id == conversation.id do
        assign(socket, :conversation, conversation)
      else
        socket
      end

    {:noreply, stream_insert(socket, :conversations, conversation)}
  end

  defp message_sent(%{assigns: %{conversation: nil}} = socket, message),
    do: push_navigate(socket, to: ~p"/chat/original/#{message.conversation_id}")

  defp message_sent(socket, message) do
    socket
    |> assign(:agent_responding, true)
    |> assign_message_form()
    |> stream_insert(:messages, message, at: 0)
  end

  defp assign_message_form(socket) do
    form =
      if socket.assigns.conversation do
        AshTemplate.Chat.form_to_create_message(
          actor: socket.assigns.actor,
          private_arguments: %{conversation_id: socket.assigns.conversation.id}
        )
        |> to_form()
      else
        AshTemplate.Chat.form_to_create_message(actor: socket.assigns.actor)
        |> to_form()
      end

    assign(
      socket,
      :message_form,
      form
    )
  end

  defp tool_calls(message), do: safe_extract(message).tool_calls

  defp tool_results(message), do: safe_extract(message).tool_results

  defp safe_extract(message) do
    case @chat_ui_tools.extract(message) do
      {:ok, extracted} ->
        extracted

      {:error, _} ->
        %{tool_calls: [], tool_results: []}
    end
  end

  defp maybe_warn_tool_data(socket, messages) when is_list(messages) do
    Enum.reduce(messages, socket, fn message, acc ->
      maybe_warn_tool_data(acc, message)
    end)
  end

  defp maybe_warn_tool_data(socket, message) do
    if agent_message?(message) do
      case @chat_ui_tools.extract(message) do
        {:ok, _} ->
          socket

        {:error, _} ->
          maybe_put_tool_data_warning(socket)
      end
    else
      socket
    end
  end

  defp maybe_put_tool_data_warning(socket) do
    if socket.assigns[:tool_data_warning_shown?] do
      socket
    else
      socket
      |> put_flash(:warning, "Some tool call data could not be displayed.")
      |> assign(:tool_data_warning_shown?, true)
    end
  end

  defp message_source(%{source: source}), do: source
  defp message_source(%{"source" => source}), do: source
  defp message_source(_), do: nil

  defp message_complete?(%{complete: complete}), do: complete in [true, "true"]
  defp message_complete?(%{"complete" => complete}), do: complete in [true, "true"]
  defp message_complete?(_), do: false

  defp user_message?(message), do: message_source(message) in [:user, "user"]
  defp agent_message?(message), do: message_source(message) in [:agent, "agent"]

  defp update_agent_responding(socket, message) do
    cond do
      user_message?(message) ->
        assign(socket, :agent_responding, true)

      agent_message?(message) ->
        assign(socket, :agent_responding, !message_complete?(message))

      true ->
        socket
    end
  end

  defp agent_response_pending?(messages) do
    case Enum.find(messages, fn message -> user_message?(message) or agent_message?(message) end) do
      nil -> false
      message -> user_message?(message) || !message_complete?(message)
    end
  end

  # sobelow_skip ["XSS.Raw"]
  defp to_markdown(text) do
    # Note that you must pass the "unsafe: true" option to first generate the raw HTML
    # in order to sanitize it. https://hexdocs.pm/mdex/MDEx.html#module-sanitize
    MDEx.to_html(text,
      extension: [
        strikethrough: true,
        tagfilter: true,
        table: true,
        autolink: true,
        tasklist: true,
        footnotes: true,
        shortcodes: true
      ],
      parse: [
        smart: true,
        relaxed_tasklist_matching: true,
        relaxed_autolinks: true
      ],
      render: [
        github_pre_lang: true,
        unsafe: true
      ],
      sanitize: MDEx.Document.default_sanitize_options()
    )
    |> case do
      {:ok, html} ->
        html
        |> Phoenix.HTML.raw()

      {:error, _} ->
        text
    end
  end
end
