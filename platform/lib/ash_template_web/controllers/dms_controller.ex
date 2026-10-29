defmodule AshTemplateWeb.DmsController do
  @moduledoc """
  Direct messages for a paired agent, as its person has them on /dms: their
  conversations and their Blocked list, opening one from a room message the
  other person wrote, its messages newest first 50 at a time, sending, and
  blocking (`AshTemplate.Dms`).

  Every request needs per-request SIWA proof from an actively paired agent.
  Browser cookies grant no authority. A signed request takes no query string,
  so the history's cursor travels in its signed body.
  """

  use AshTemplateWeb, :controller

  alias AshTemplate.Actors.Agent
  alias AshTemplate.Dms
  alias AshTemplate.Dms.{Conversation, Message}
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
    "conversation_not_found" =>
      {404, "Your person has no conversation with that id.",
       "List your person's conversations with GET /api/v1/dms and use an id from there."},
    "invalid_open" =>
      {422, "That conversation could not be opened.",
       "details says why. Send message_id, the id of a room message the other person wrote, from rooms messages."},
    "invalid_cursor" =>
      {422, "That page could not be found.",
       "Send {\"after\": \"<next_cursor>\"} with the previous page's next_cursor, unchanged, or {} for the newest messages."},
    "invalid_message" =>
      {422, "The message could not be sent.",
       "details says why. Send {\"body\": \"…\", \"operation_id\": \"<uuid>\"}: a body of 1 to 2,000 characters and a UUID you keep when retrying. A person sends at most 300 messages an hour."},
    "unavailable" => {503, "That could not be reached right now.", "Try again in a moment."}
  }
  @errors Map.merge(@errors, AgentWallet.not_person_refusals())

  def index(conn, _params), do: conversations(conn, false)
  def blocked(conn, _params), do: conversations(conn, true)

  defp conversations(conn, blocked) do
    case Dms.list_conversations(blocked, actor: conn.assigns.actor) do
      {:ok, conversations} ->
        json(conn, %{conversations: Enum.map(conversations, &conversation/1)})

      {:error, %Ash.Error.Forbidden{}} ->
        refuse(conn, "agent_not_paired")

      {:error, error} ->
        conn |> UnexpectedFailure.log(error) |> refuse("unavailable")
    end
  end

  # Opening a conversation the two people already have answers it.
  def open(conn, _params) do
    case Dms.open_conversation(conn.body_params["message_id"], actor: conn.assigns.actor) do
      {:ok, conversation} -> json(conn, %{conversation: conversation(conversation)})
      {:error, %Ash.Error.Invalid{} = error} -> refuse(conn, "invalid_open", error)
      {:error, %Ash.Error.Forbidden{}} -> refuse(conn, "agent_not_paired")
      {:error, error} -> conn |> UnexpectedFailure.log(error) |> refuse("unavailable")
    end
  end

  def history(conn, %{"conversation" => id}) do
    with_conversation(conn, id, fn conn, conversation ->
      with {:ok, page} <- page(conn.body_params),
           {:ok, page} <- Dms.list_dms(conversation.id, actor: conn.assigns.actor, page: page) do
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
  def send_message(conn, %{"conversation" => id}) do
    actor = conn.assigns.actor

    with_conversation(conn, id, fn conn, conversation ->
      with {:ok, nil} <- earlier_send(conn.body_params["operation_id"], actor),
           {:ok, message} <-
             Dms.send_dm(conversation.id, Map.take(conn.body_params, ["body", "operation_id"]),
               actor: actor
             ) do
        conn |> put_status(:created) |> json(%{message: message(message)})
      else
        {:ok, %Message{} = earlier} -> json(conn, %{message: message(earlier)})
        {:error, %Ash.Error.Invalid{} = error} -> refuse(conn, "invalid_message", error)
        {:error, error} -> conn |> UnexpectedFailure.log(error) |> refuse("unavailable")
      end
    end)
  end

  # A missing or malformed operation_id finds no earlier message; the send refuses it.
  defp earlier_send(operation_id, actor) do
    case Dms.get_earlier_dm(operation_id, actor: actor) do
      {:error, %Ash.Error.Invalid{}} -> {:ok, nil}
      result -> result
    end
  end

  def block(conn, %{"conversation" => id}), do: change(conn, id, &Dms.block_conversation/2)
  def unblock(conn, %{"conversation" => id}), do: change(conn, id, &Dms.unblock_conversation/2)

  defp change(conn, id, change) do
    with_conversation(conn, id, fn conn, conversation ->
      case change.(conversation, actor: conn.assigns.actor) do
        {:ok, conversation} -> json(conn, %{conversation: conversation(conversation)})
        {:error, error} -> conn |> UnexpectedFailure.log(error) |> refuse("unavailable")
      end
    end)
  end

  # A conversation the person is not in reads as absent, exactly like an id
  # that names none.
  defp with_conversation(conn, id, respond) do
    case Dms.get_conversation(id, actor: conn.assigns.actor) do
      {:ok, %Conversation{} = conversation} -> respond.(conn, conversation)
      {:ok, nil} -> refuse(conn, "conversation_not_found")
      {:error, %Ash.Error.Invalid{}} -> refuse(conn, "conversation_not_found")
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
    %{
      id: conversation.id,
      with: %{
        name: conversation.other_person.name,
        picture: conversation.other_person.picture
      },
      blocked: conversation.blocked,
      last_message: conversation.last_body,
      last_message_at: conversation.last_message_at
    }
  end

  defp message(%Message{} = message) do
    %{
      id: message.id,
      conversation_id: message.conversation_id,
      body: message.body,
      mine: message.mine,
      via_agent_id: message.via_agent_id,
      inserted_at: message.inserted_at
    }
  end

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
