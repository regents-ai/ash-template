defmodule AshTemplateWeb.PollsController do
  @moduledoc """
  The polls API (`AshTemplate.Polls`): anyone reads the newest polls and each
  one, as anyone reads /polls. An agent with per-request SIWA proof and an
  active pairing starts a poll for its person, votes for them, and ends a poll
  they started.

  A poll's counts are `null` while it is open, so nobody sees which way it
  leans; `votes_cast` says how many have voted. Nobody's vote is shown but
  their own.
  """

  use AshTemplateWeb, :controller

  alias AshTemplate.Polls
  alias AshTemplate.Polls.Poll
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
    "not_poll_starter" =>
      {403, "Only the person who started this poll ends it.",
       "End a poll your person started, or let it close by itself."},
    "poll_closed" =>
      {422, "This poll has closed.", "Read its counts with GET /api/v1/polls/:id."},
    "polls_unavailable" =>
      {503, "The polls could not be reached right now.", "Try again in a moment."}
  }
  @errors Map.merge(@errors, AgentWallet.not_person_refusals())

  defp paired_agent(%{assigns: %{actor: actor}} = conn, _opts)
       when AgentWallet.acts_for_account(actor),
       do: conn

  defp paired_agent(conn, _opts),
    do: conn |> refuse(AgentWallet.not_person_code(conn.assigns.actor)) |> halt()

  def index(conn, _params) do
    case Polls.list_polls() do
      {:ok, polls} -> json(conn, %{polls: Enum.map(polls, &present/1)})
      {:error, error} -> conn |> UnexpectedFailure.log(error) |> refuse("polls_unavailable")
    end
  end

  def show(conn, %{"poll" => id}) do
    with_poll(conn, id, nil, fn conn, poll -> json(conn, %{poll: present(poll)}) end)
  end

  # A retry with the operation_id of a poll this agent's person already started
  # answers that poll (200), and starts nothing.
  def create(conn, _params) do
    actor = conn.assigns.actor

    with {:ok, nil} <- earlier_start(conn.body_params["operation_id"], actor),
         {:ok, poll} <-
           Polls.start_poll(
             Map.take(conn.body_params, ["question", "choices", "minutes", "operation_id"]),
             actor: actor
           ) do
      conn |> put_status(:created) |> json(%{poll: present(poll)})
    else
      {:ok, %Poll{} = earlier} -> json(conn, %{poll: present(earlier)})
      {:error, %Ash.Error.Invalid{} = error} -> refuse(conn, "invalid_poll", error)
      {:error, error} -> conn |> UnexpectedFailure.log(error) |> refuse("polls_unavailable")
    end
  end

  # A missing or malformed operation_id finds no earlier poll; the start refuses it.
  defp earlier_start(operation_id, actor) do
    case Polls.get_started_poll(operation_id, actor: actor) do
      {:error, %Ash.Error.Invalid{}} -> {:ok, nil}
      result -> result
    end
  end

  # Sending the choice already made answers that vote again.
  def vote(conn, %{"poll" => id}) do
    actor = conn.assigns.actor

    with_poll(conn, id, actor, fn conn, poll ->
      case Polls.vote(poll.id, Map.take(conn.body_params, ["choice"]), actor: actor) do
        {:ok, vote} ->
          {:ok, poll} = Polls.get_poll(poll.id, actor: actor)
          json(conn, %{poll: present(poll), vote: %{choice: vote.choice}})

        {:error, %Ash.Error.Invalid{} = error} ->
          refuse(conn, "invalid_vote", error)

        {:error, error} ->
          conn |> UnexpectedFailure.log(error) |> refuse("polls_unavailable")
      end
    end)
  end

  def end_poll(conn, %{"poll" => id}) do
    actor = conn.assigns.actor

    with_poll(conn, id, actor, fn conn, poll ->
      case Polls.end_poll(poll, actor: actor) do
        {:ok, poll} -> json(conn, %{poll: present(poll)})
        {:error, %Ash.Error.Forbidden{}} -> refuse(conn, "not_poll_starter")
        {:error, %Ash.Error.Invalid{}} -> refuse(conn, "poll_closed")
        {:error, error} -> conn |> UnexpectedFailure.log(error) |> refuse("polls_unavailable")
      end
    end)
  end

  defp with_poll(conn, id, actor, respond) do
    case Polls.get_poll(id, actor: actor) do
      {:ok, %Poll{} = poll} -> respond.(conn, poll)
      {:ok, nil} -> refuse(conn, "poll_not_found")
      {:error, %Ash.Error.Invalid{}} -> refuse(conn, "poll_not_found")
      {:error, error} -> conn |> UnexpectedFailure.log(error) |> refuse("polls_unavailable")
    end
  end

  defp present(%Poll{} = poll) do
    %{
      id: poll.id,
      question: poll.question,
      choices: poll.choices,
      open: poll.open,
      closes_at: poll.closes_at,
      ended_at: poll.ended_at,
      votes_cast: poll.votes_cast,
      counts: poll.totals,
      started_by: %{name: poll.starter.name, picture: poll.starter.picture},
      via_agent_id: poll.via_agent_id,
      started_at: poll.inserted_at
    }
  end

  defp refuse(conn, code, error \\ nil) do
    {status, message, hint} = Map.fetch!(@errors, code)
    body = %{code: code, message: message, hint: hint}
    body = if error, do: Map.put(body, :details, FormErrors.details(error)), else: body
    conn |> put_status(status) |> json(%{error: body})
  end
end
