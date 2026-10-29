defmodule AshTemplateWeb.ChatController do
  @moduledoc """
  Chat with the assistant for a paired agent, as its person has it on /chat:
  their chats, a chat's messages newest first 50 at a time, and sending a
  message, which starts a chat when it names none (`AshTemplate.Chat`). The
  assistant's reply is written a few words at a time after the send answers;
  reading the chat again shows it, `complete` once it is finished.

  Every request needs per-request SIWA proof from an actively paired agent.
  Browser cookies grant no authority. A signed request takes no query string,
  so the history's cursor travels in its signed body.
  """

  use AshTemplateWeb, :controller

  alias AshTemplate.Actors.Agent
  alias AshTemplate.Chat
  alias AshTemplate.Chat.{Conversation, Message}
  alias AshTemplateWeb.{FormErrors, UnexpectedFailure}
  alias AshTemplateWeb.Plugs.AgentWallet

  require AgentWallet

  plug :paired_agent

  # Every refusal answers {"error": {"code", "message", "hint"}}, the shape of the
  # site's other JSON errors.
  @errors %{
    "authentication_required" =>
      {401, "A signed request from a paired agent is required.",
       "Prepare the request, sign its exact bytes with your SIWA signer, then send the request and proof."},
    "chat_not_found" =>
      {404, "Your person has no chat with that id.",
       "List your person's chats with GET /api/v1/chat and use an id from there."},
    "invalid_cursor" =>
      {422, "That page could not be found.",
       "Send {\"after\": \"<next_cursor>\"} with the previous page's next_cursor, unchanged, or {} for the newest messages."},
    "invalid_message" =>
      {422, "The message could not be sent.",
       "details says why. Send {\"text\": \"…\", \"operation_id\": \"<uuid>\"}: text of 1 to 4,000 characters and a UUID you keep when retrying, with conversation_id from chat list to continue a chat. A person sends at most 10 messages a minute."},
    "unavailable" => {503, "That could not be reached right now.", "Try again in a moment."}
  }
  @errors Map.merge(@errors, AgentWallet.not_person_refusals())

  # Newest first, the latest 100.
  def index(conn, _params) do
    case Chat.my_conversations(actor: conn.assigns.actor, query: [limit: 100]) do
      {:ok, conversations} ->
        json(conn, %{conversations: Enum.map(conversations, &conversation/1)})

      {:error, %Ash.Error.Forbidden{}} ->
        refuse(conn, "agent_not_paired")

      {:error, error} ->
        conn |> UnexpectedFailure.log(error) |> refuse("unavailable")
    end
  end

  def history(conn, %{"conversation" => id}) do
    with_conversation(conn, id, fn conn, conversation ->
      with {:ok, page} <- page(conn.body_params),
           {:ok, page} <-
             Chat.message_history(conversation.id, actor: conn.assigns.actor, page: page) do
        json(conn, %{
          messages: Enum.map(page.results, &message/1),
          pagination: %{has_more: page.more?, next_cursor: next_cursor(page)}
        })
      else
        {:error, :invalid_cursor} -> refuse(conn, "invalid_cursor")
        {:error, %Ash.Error.Invalid{}} -> refuse(conn, "invalid_cursor")
        {:error, error} -> conn |> UnexpectedFailure.log(error) |> refuse("unavailable")
      end
    end)
  end

  # A retry with the operation_id of a message this agent's person already sent
  # answers that message (200), and sends nothing.
  def send_message(conn, _params) do
    case conn.body_params do
      %{"conversation_id" => id} -> with_conversation(conn, id, &send_in/2)
      _new_chat -> send_in(conn, nil)
    end
  end

  defp send_in(conn, conversation) do
    actor = conn.assigns.actor
    operation_id = conn.body_params["operation_id"]
    arguments = %{operation_id: operation_id, conversation_id: conversation && conversation.id}

    with {:ok, nil} <- earlier_send(operation_id, actor),
         {:ok, message} <-
           Chat.create_message(Map.take(conn.body_params, ["text"]),
             actor: actor,
             private_arguments: arguments
           ) do
      conn |> put_status(:created) |> json(%{message: message(message)})
    else
      {:ok, %Message{} = earlier} -> json(conn, %{message: message(earlier)})
      {:error, %Ash.Error.Invalid{} = error} -> refuse(conn, "invalid_message", error)
      {:error, %Ash.Error.Forbidden{}} -> refuse(conn, "agent_not_paired")
      {:error, error} -> conn |> UnexpectedFailure.log(error) |> refuse("unavailable")
    end
  end

  # A missing or malformed operation_id finds no earlier message; the send refuses it.
  defp earlier_send(operation_id, actor) do
    case Chat.get_earlier_message(operation_id, actor: actor) do
      {:error, %Ash.Error.Invalid{}} -> {:ok, nil}
      result -> result
    end
  end

  # A chat that is not the person's reads as absent, exactly like an id that
  # names none.
  defp with_conversation(conn, id, respond) do
    case Chat.get_conversation(id, actor: conn.assigns.actor) do
      {:ok, %Conversation{} = conversation} -> respond.(conn, conversation)
      {:error, %Ash.Error.Invalid{}} -> refuse(conn, "chat_not_found")
      {:error, %Ash.Error.Forbidden{}} -> refuse(conn, "agent_not_paired")
      {:error, error} -> conn |> UnexpectedFailure.log(error) |> refuse("unavailable")
    end
  end

  defp page(body) when body == %{}, do: {:ok, limit: 50}
  defp page(%{"after" => cursor}) when is_binary(cursor), do: {:ok, after: cursor, limit: 50}
  defp page(_body), do: {:error, :invalid_cursor}

  defp next_cursor(%{more?: true, results: results}),
    do: List.last(results).__metadata__.keyset

  defp next_cursor(_page), do: nil

  defp conversation(%Conversation{} = conversation) do
    %{id: conversation.id, title: conversation.title, inserted_at: conversation.inserted_at}
  end

  defp message(%Message{} = message) do
    %{
      id: message.id,
      conversation_id: message.conversation_id,
      from: from(message.source),
      text: message.text,
      complete: message.complete,
      response_to_id: message.response_to_id,
      inserted_at: message.inserted_at
    }
  end

  defp from(:user), do: "person"
  defp from(:agent), do: "assistant"

  defp paired_agent(conn, _opts) do
    conn = put_resp_header(conn, "cache-control", "no-store")

    case AgentWallet.call(conn, []) do
      %{halted: true} = conn ->
        conn

      %{assigns: %{actor: actor}} = conn when AgentWallet.acts_for_account(actor) ->
        conn

      %{assigns: %{actor: %Agent{} = actor}} = conn ->
        conn |> refuse(AgentWallet.not_person_code(actor)) |> halt()

      conn ->
        conn |> refuse("authentication_required") |> halt()
    end
  end

  defp refuse(conn, code, error \\ nil) do
    {status, message, hint} = Map.fetch!(@errors, code)
    body = %{code: code, message: message, hint: hint}
    body = if error, do: Map.put(body, :details, FormErrors.details(error)), else: body
    conn |> put_status(status) |> json(%{error: body})
  end
end
