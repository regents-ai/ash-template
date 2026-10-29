defmodule AshTemplateWeb.DmsController do
  @moduledoc """
  Direct messages for a paired agent, as its person has them on /dms: their
  conversations and their Blocked list, opening one from a room message the
  other person wrote, its messages newest first 50 at a time, sending, and
  blocking (`AshTemplate.Dms`).

  Every request needs per-request SIWA proof from an actively paired agent.
  Browser cookies grant no authority. A signed request takes no query string,
  so the history's cursor travels in its signed body.

  Each route runs the direct-messages action its browser tool and hosted MCP
  tool run, and this table holds the words of every direct-messages refusal, on
  each surface.
  """

  use AshTemplateWeb, :controller

  alias AshTemplate.Actors.Agent
  alias AshTemplate.Agents.NotPaired
  alias AshTemplate.Dms
  alias AshTemplate.Dms.Refused
  alias AshTemplateWeb.{FormErrors, UnexpectedFailure}
  alias AshTemplateWeb.Plugs.AgentWallet

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
    "idempotency_conflict" =>
      {409, "This operation_id was already used for another message.",
       "Send a new UUID as operation_id for a new message. Keep an operation_id only to retry the same message in the same conversation."},
    "unavailable" => {503, "That could not be reached right now.", "Try again in a moment."}
  }
  @errors Map.merge(@errors, AgentWallet.not_person_refusals())

  @doc """
  The `{status, message, hint}` of the direct-messages refusal `code`, for every
  surface that answers it.
  """
  def refusal(code), do: Map.fetch!(@errors, code)

  # Each action that takes input, and the refusal input it cannot take gets
  # besides the conversation's: the save's own, or the read's.
  @input %{
    dms_open: "invalid_open",
    dms_read: "invalid_cursor",
    dms_send: "invalid_message",
    dms_block: "conversation_not_found",
    dms_unblock: "conversation_not_found"
  }

  # The refusals of a save, which say why in `details`.
  @saves ~w(invalid_open invalid_message)

  @doc """
  The refusal `{code, extra}` a direct-messages `action` answers for `error`: the
  action's own refusal, or the input it could not take. A conversation it cannot
  take reads as one that names none; other input is the action's own refusal,
  with `details` for a save. The paired agent routes and the hosted MCP server
  answer the same.
  """
  @spec input_refusal(atom(), Ash.Error.Invalid.t()) :: {String.t(), map()}
  def input_refusal(action, %Ash.Error.Invalid{errors: errors} = error) do
    other = Map.fetch!(@input, action)

    cond do
      refused = Enum.find(errors, &match?(%Refused{}, &1)) -> answer(refused)
      Enum.any?(errors, &match?(%{field: :conversation}, &1)) -> {"conversation_not_found", %{}}
      other in @saves -> {other, details(error)}
      true -> {other, %{}}
    end
  end

  @doc "A direct-messages action's own refusal as `{code, extra}`: what the code alone leaves out."
  @spec answer(Refused.t()) :: {String.t(), map()}
  def answer(%Refused{code: code, error: %Ash.Error.Invalid{} = error}),
    do: {code, details(error)}

  def answer(%Refused{code: code}), do: {code, %{}}

  defp details(error), do: %{details: FormErrors.details(error)}

  def index(conn, _params),
    do: respond(conn, :dms_list, Dms.dms_list(actor: conn.assigns.actor))

  def blocked(conn, _params),
    do: respond(conn, :dms_blocked, Dms.dms_blocked(actor: conn.assigns.actor))

  # Opening a conversation the two people already have answers it.
  def open(conn, _params),
    do: respond(conn, :dms_open, Dms.dms_open(conn.body_params, actor: conn.assigns.actor))

  def history(conn, %{"conversation" => id}),
    do: respond(conn, :dms_read, Dms.dms_read(id, addressed(conn), actor: conn.assigns.actor))

  # A retry with the operation_id of a message this agent already sent answers
  # that message (200), and sends nothing (`AshTemplate.Dms.Message.AgentSend`).
  def send_message(conn, %{"conversation" => id}) do
    case Dms.dms_send(id, addressed(conn), actor: conn.assigns.actor) do
      {:ok, %{message: message, replayed: false}} ->
        conn |> put_status(:created) |> json(%{message: message})

      {:ok, %{message: message, replayed: true}} ->
        json(conn, %{message: message})

      {:error, error} ->
        refuse_error(conn, :dms_send, error)
    end
  end

  def block(conn, %{"conversation" => id}),
    do: respond(conn, :dms_block, Dms.dms_block(id, actor: conn.assigns.actor))

  def unblock(conn, %{"conversation" => id}),
    do: respond(conn, :dms_unblock, Dms.dms_unblock(id, actor: conn.assigns.actor))

  # The address names the conversation: one in the body never chooses another.
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

      %{assigns: %{actor: %Agent{pairing: :active}}} = conn ->
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
