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

  Each route runs the chat action its browser tool and hosted MCP tool run, and
  this table holds the words of every chat refusal, on each surface.
  """

  use AshTemplateWeb, :controller

  alias AshTemplate.Actors.Agent
  alias AshTemplate.Agents.NotPaired
  alias AshTemplate.Chat
  alias AshTemplate.Chat.Refused
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
    "idempotency_conflict" =>
      {409, "This operation_id was already used for another message.",
       "Send a new UUID as operation_id for a new message. Keep an operation_id only to retry the same message in the same chat."},
    "unavailable" => {503, "That could not be reached right now.", "Try again in a moment."}
  }
  @errors Map.merge(@errors, AgentWallet.not_person_refusals())

  @doc """
  The `{status, message, hint}` of the chat refusal `code`, for every surface
  that answers it.
  """
  def refusal(code), do: Map.fetch!(@errors, code)

  # Each action that takes input, and the refusal input it cannot take gets
  # besides the chat's.
  @input %{chat_read: "invalid_cursor", chat_send: "invalid_message"}

  @doc """
  The refusal `{code, extra}` a chat `action` answers for `error`: the action's
  own refusal, or the input it could not take. A chat id it cannot take reads as
  one that names none; other input is the action's own refusal, with `details`
  for a send. The paired agent routes and the hosted MCP server answer the same.
  """
  @spec input_refusal(atom(), Ash.Error.Invalid.t()) :: {String.t(), map()}
  def input_refusal(action, %Ash.Error.Invalid{errors: errors} = error) do
    cond do
      refused = Enum.find(errors, &match?(%Refused{}, &1)) ->
        answer(refused)

      Enum.any?(
        errors,
        &match?(%{field: field} when field in [:conversation, :conversation_id], &1)
      ) ->
        {"chat_not_found", %{}}

      action == :chat_send ->
        {"invalid_message", details(error)}

      true ->
        {Map.fetch!(@input, action), %{}}
    end
  end

  @doc "A chat action's own refusal as `{code, extra}`: what the code alone leaves out."
  @spec answer(Refused.t()) :: {String.t(), map()}
  def answer(%Refused{code: code, error: %Ash.Error.Invalid{} = error}),
    do: {code, details(error)}

  def answer(%Refused{code: code}), do: {code, %{}}

  defp details(error), do: %{details: FormErrors.details(error)}

  def index(conn, _params),
    do: respond(conn, :chat_list, Chat.chat_list(actor: conn.assigns.actor))

  def history(conn, %{"conversation" => id}),
    do: respond(conn, :chat_read, Chat.chat_read(id, addressed(conn), actor: conn.assigns.actor))

  # A retry with the operation_id and words of a message this agent already sent
  # answers that message (200), and sends nothing
  # (`AshTemplate.Chat.Message.AgentSend`).
  def send_message(conn, _params) do
    case Chat.chat_send(conn.body_params, actor: conn.assigns.actor) do
      {:ok, %{message: message, replayed: false}} ->
        conn |> put_status(:created) |> json(%{message: message})

      {:ok, %{message: message, replayed: true}} ->
        json(conn, %{message: message})

      {:error, error} ->
        refuse_error(conn, :chat_send, error)
    end
  end

  # The address names the chat: one in the body never chooses another.
  defp addressed(conn), do: Map.delete(conn.body_params, "conversation")

  defp respond(conn, _action, {:ok, answer}), do: json(conn, answer)
  defp respond(conn, action, {:error, error}), do: refuse_error(conn, action, error)

  defp refuse_error(conn, action, %Ash.Error.Invalid{} = error),
    do: refuse_with(conn, input_refusal(action, error))

  # The pairing was revoked after this request was let in.
  defp refuse_error(conn, _action, %Ash.Error.Forbidden{errors: [%NotPaired{code: code}]}),
    do: refuse(conn, code)

  defp refuse_error(conn, _action, error),
    do: conn |> UnexpectedFailure.log(error) |> refuse("unavailable")

  defp refuse_with(conn, {code, extra}), do: refuse(conn, code, extra)

  defp paired_agent(conn, _opts) do
    conn = put_resp_header(conn, "cache-control", "no-store")

    case AgentWallet.call(conn, []) do
      %{halted: true} = conn ->
        conn

      %{assigns: %{actor: actor}} = conn when AgentWallet.acts_for_account(actor) ->
        conn

      %{assigns: %{actor: %Agent{} = actor}} = conn ->
        conn |> refuse(NotPaired.code(actor)) |> halt()

      conn ->
        conn |> refuse("authentication_required") |> halt()
    end
  end

  defp refuse(conn, code, extra \\ %{}) do
    {status, message, hint} = refusal(code)

    conn
    |> put_status(status)
    |> json(%{error: Map.merge(%{code: code, message: message, hint: hint}, extra)})
  end
end
