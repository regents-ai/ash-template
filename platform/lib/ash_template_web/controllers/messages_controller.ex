defmodule AshTemplateWeb.MessagesController do
  @moduledoc """
  An agent leaving a private message for the site's team, under a topic the site
  names, with per-request SIWA proof. Paired or not, it may leave a few an hour,
  and past that is told how many seconds to wait; only the team reads them, at
  /admin/messages.
  """

  use AshTemplateWeb, :controller

  alias AshTemplate.Messages
  alias AshTemplate.Messages.Refused
  alias AshTemplateWeb.{ClientAddress, FormErrors}
  alias RegentHttp.UnexpectedFailure

  # Every refusal answers {"error": {"code", "message", "hint"}}, the shape of the
  # site's other JSON errors.
  @errors %{
    "invalid_message" =>
      {422, "The message could not be left.",
       "details says why. Send {\"body\": \"…\", \"reply_to\": \"…\", \"operation_id\": \"<uuid>\"}: a body of 1 to 2,000 characters, an optional reply_to of up to 200, and a UUID you keep when retrying, to a topic of lowercase letters, numbers and hyphens."},
    "idempotency_conflict" =>
      {409, "This operation_id was already used for another message.",
       "Send a new UUID as operation_id for a new message. Keep an operation_id only to retry the same message."},
    "too_many_requests" =>
      {429, "Too Many Requests",
       "Wait the number of seconds in Retry-After, then send the request again."},
    "messages_unavailable" =>
      {503, "The message could not be left right now.", "Try again in a moment."}
  }

  @doc """
  The `{status, message, hint}` of the refusal `code`, for the hosted MCP
  server's tool errors (`AshTemplateWeb.ToolErrors`).
  """
  def refusal(code), do: Map.fetch!(@errors, code)

  # A retry with the operation_id of a message this agent already left answers
  # its receipt (200), and leaves nothing (`AshTemplate.Messages.Message.AgentLeave`).
  def leave(conn, %{"topic" => topic}) do
    case Messages.agent_leave_message(
           topic,
           Map.take(conn.body_params, ["body", "reply_to", "operation_id"]),
           actor: conn.assigns.actor,
           context: %{client_key: ClientAddress.client_key(conn)}
         ) do
      {:ok, %{receipt: receipt, replayed: false}} ->
        conn |> put_status(:created) |> json(%{receipt: receipt})

      {:ok, %{receipt: receipt, replayed: true}} ->
        json(conn, %{receipt: receipt})

      {:error, %Ash.Error.Invalid{errors: errors} = error} ->
        case Enum.find(errors, &is_struct(&1, Refused)) do
          %Refused{code: "too_many_requests", retry_after: seconds} ->
            conn
            |> put_resp_header("retry-after", Integer.to_string(seconds))
            |> refuse("too_many_requests")

          %Refused{code: code} ->
            refuse(conn, code)

          nil ->
            refuse(conn, "invalid_message", error)
        end

      {:error, error} ->
        conn |> UnexpectedFailure.log(error) |> refuse("messages_unavailable")
    end
  end

  # `details` says why invalid input was refused.
  defp refuse(conn, code, error \\ nil) do
    {status, message, hint} = refusal(code)

    body =
      case error do
        nil -> %{code: code, message: message, hint: hint}
        error -> %{code: code, message: message, hint: hint, details: FormErrors.details(error)}
      end

    conn |> put_status(status) |> json(%{error: body})
  end
end
