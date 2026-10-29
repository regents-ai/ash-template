defmodule AshTemplateWeb.PollsController do
  @moduledoc """
  The polls API (`AshTemplate.Polls`): anyone reads the newest polls and each
  one, as anyone reads /polls. An agent with per-request SIWA proof and an
  active pairing starts a poll for its person, votes for them, and ends a poll
  they started.

  A poll's counts are `null` while it is open, so nobody sees which way it
  leans; `votes_cast` says how many have voted. Nobody's vote is shown but
  their own.

  Each route runs the polls action its browser tool and hosted MCP tool run,
  and this table holds the words of every polls refusal, on each surface.
  """

  use AshTemplateWeb, :controller

  alias AshTemplate.Agents.NotPaired
  alias AshTemplate.Polls
  alias AshTemplate.Polls.Refused
  alias AshTemplateWeb.{FormErrors, UnexpectedFailure}
  alias AshTemplateWeb.Plugs.AgentWallet

  require AgentWallet

  plug :paired_agent when action in [:create, :vote, :end_poll]

  # Every refusal answers {"error": {"code", "message", "hint"}}, the shape of the
  # site's other JSON errors.
  @errors %{
    "poll_not_found" =>
      {404, "There is no poll with that id.", "List the polls with GET /api/v1/polls."},
    "invalid_poll" =>
      {422, "The poll could not be started.",
       "details says why. Send {\"question\": \"…\", \"choices\": [\"…\", \"…\"], \"minutes\": 15, \"operation_id\": \"<uuid>\"}: a question of 1 to 200 characters, 2 to 10 different choices of 1 to 100 characters, 1 to 60 minutes, and a UUID you keep when retrying. A person starts 3 polls a day."},
    "invalid_vote" =>
      {422, "The vote could not be counted.",
       "details says why. Send {\"choice\": \"…\"} with one of the poll's choices, exactly as listed, while it is open. A person votes once in each poll, and a vote can't be changed."},
    "idempotency_conflict" =>
      {409, "This operation_id was already used for another poll.",
       "Send a new UUID as operation_id for a new poll. Keep an operation_id only to retry the same question, choices and minutes."},
    "not_poll_starter" =>
      {403, "Only the person who started this poll ends it.",
       "End a poll your person started, or let it close by itself."},
    "poll_closed" =>
      {422, "This poll has closed.", "Read its counts with GET /api/v1/polls/:id."},
    "polls_unavailable" =>
      {503, "The polls could not be reached right now.", "Try again in a moment."}
  }
  @errors Map.merge(@errors, AgentWallet.not_person_refusals())

  @doc "The `{status, message, hint}` of the polls refusal `code`, for every surface that answers it."
  def refusal(code), do: Map.fetch!(@errors, code)

  # Each action that takes input, and the refusal input it cannot take gets
  # besides the poll's: the save's own.
  @input %{
    polls_show: "poll_not_found",
    polls_start: "invalid_poll",
    polls_vote: "invalid_vote",
    polls_end: "poll_not_found"
  }

  # The refusals of a save, which say why in `details`.
  @saves ~w(invalid_poll invalid_vote)

  @doc """
  The refusal `{code, extra}` a polls `action` answers for `error`: the action's
  own refusal, or the input it could not take. A poll it cannot take reads as
  one that names none; other input is the action's own refusal, with `details`
  for a save. The agent routes and the hosted MCP server answer the same.
  """
  @spec input_refusal(atom(), Ash.Error.Invalid.t()) :: {String.t(), map()}
  def input_refusal(action, %Ash.Error.Invalid{errors: errors} = error) do
    other = Map.fetch!(@input, action)

    cond do
      refused = Enum.find(errors, &match?(%Refused{}, &1)) -> answer(refused)
      Enum.any?(errors, &match?(%{field: :poll}, &1)) -> {"poll_not_found", %{}}
      other in @saves -> {other, details(error)}
      true -> {other, %{}}
    end
  end

  @doc "A polls action's own refusal as `{code, extra}`: what the code alone leaves out."
  @spec answer(Refused.t()) :: {String.t(), map()}
  def answer(%Refused{code: code, error: %Ash.Error.Invalid{} = error}),
    do: {code, details(error)}

  def answer(%Refused{code: code}), do: {code, %{}}

  defp details(error), do: %{details: FormErrors.details(error)}

  defp paired_agent(%{assigns: %{actor: actor}} = conn, _opts)
       when AgentWallet.acts_for_account(actor),
       do: conn

  defp paired_agent(conn, _opts),
    do: conn |> refuse(NotPaired.code(conn.assigns.actor)) |> halt()

  def index(conn, _params), do: respond(conn, :polls_list, Polls.polls_list())

  def show(conn, %{"poll" => id}), do: respond(conn, :polls_show, Polls.polls_show(id))

  # A retry with the operation_id, question, choices and minutes of a poll this
  # agent already started answers that poll (200), and starts nothing
  # (`AshTemplate.Polls.Poll.AgentStart`).
  def create(conn, _params) do
    case Polls.polls_start(conn.body_params, actor: conn.assigns.actor) do
      {:ok, %{poll: poll, replayed: false}} -> conn |> put_status(:created) |> json(%{poll: poll})
      {:ok, %{poll: poll, replayed: true}} -> json(conn, %{poll: poll})
      {:error, error} -> refuse_error(conn, :polls_start, error)
    end
  end

  # Sending the choice already made answers that vote again.
  def vote(conn, %{"poll" => id}),
    do:
      respond(conn, :polls_vote, Polls.polls_vote(id, addressed(conn), actor: conn.assigns.actor))

  def end_poll(conn, %{"poll" => id}),
    do: respond(conn, :polls_end, Polls.polls_end(id, actor: conn.assigns.actor))

  # The address names the poll: one in the body never chooses another.
  defp addressed(conn), do: Map.delete(conn.body_params, "poll")

  defp respond(conn, _action, {:ok, answer}), do: json(conn, answer)
  defp respond(conn, action, {:error, error}), do: refuse_error(conn, action, error)

  defp refuse_error(conn, action, %Ash.Error.Invalid{} = error),
    do: refuse_with(conn, input_refusal(action, error))

  # The pairing was revoked after this request was let in.
  defp refuse_error(conn, _action, %Ash.Error.Forbidden{errors: [%NotPaired{code: code}]}),
    do: refuse(conn, code)

  defp refuse_error(conn, _action, error),
    do: conn |> UnexpectedFailure.log(error) |> refuse("polls_unavailable")

  defp refuse_with(conn, {code, extra}), do: refuse(conn, code, extra)

  defp refuse(conn, code, extra \\ %{}) do
    {status, message, hint} = refusal(code)

    conn
    |> put_status(status)
    |> json(%{error: Map.merge(%{code: code, message: message, hint: hint}, extra)})
  end
end
