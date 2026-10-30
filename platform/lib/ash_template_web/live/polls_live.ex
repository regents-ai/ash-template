defmodule AshTemplateWeb.PollsLive do
  @moduledoc """
  Polls (`AshTemplate.Polls`): the newest polls in the shell's sidebar, open
  ones first, and the one open on the page with its choices, or, on /polls, the
  form to start one. Anyone reads them; a signed-in person votes once in each
  and ends the polls they started.

  Voting and starting never touch the page directly. Each start, vote and end
  is published on `AshTemplate.Polls.topic/0`; the shell hands each on here as
  `send_update(PollsLive, id: "polls", change: poll_id)`. While a poll on the
  page is open, the page reads it again each minute and at its close, so its
  time left and its counts follow the clock.
  """

  use AshTemplateWeb, :live_component

  import AshTemplateWeb.Components.PageHead

  alias AshTemplate.Actors.Human
  alias AshTemplate.Polls
  alias AshTemplate.Polls.Poll
  alias AshTemplateWeb.FormErrors
  alias AshTemplateWeb.Live.Session
  alias AshTemplateWeb.Read
  alias Regent.Primitives

  @minutes [1, 5, 15, 30, 60]
  @minute 60_000

  @impl true
  def mount(socket) do
    {:ok,
     socket
     |> Session.check_component_lease(&take_account/2)
     |> assign(
       actor: nil,
       poll_id: nil,
       # The person and poll the page was last read for; nobody yet.
       shown: {:nobody, nil},
       polls: %Read{},
       poll: %Read{},
       form: nil,
       notice: nil,
       clock: nil
     )}
  end

  # A start, vote or end anywhere moves the list, and the poll on the page when
  # it is the one that changed.
  @impl true
  def update(%{change: poll_id}, socket) do
    socket = load_polls(socket)

    if poll_id == socket.assigns.poll_id,
      do: {:ok, load_poll(socket)},
      else: {:ok, socket}
  end

  def update(%{tick: true}, socket), do: {:ok, socket |> assign(:clock, nil) |> load_poll()}

  # The shell renders this with every update of its own, so the list and the
  # form are made again only for a different person, and the poll read again
  # only for a different poll.
  def update(%{id: id, lease: lease, account: account, poll_id: poll_id}, socket) do
    actor = account && Human.for_account(account)
    {shown_actor, _shown_poll} = shown = socket.assigns.shown
    socket = assign(socket, id: id, lease: lease, actor: actor, poll_id: poll_id)

    cond do
      shown == {actor, poll_id} ->
        {:ok, socket}

      shown_actor == actor ->
        {:ok, socket |> assign(shown: {actor, poll_id}, notice: nil) |> load_poll()}

      true ->
        {:ok,
         socket
         |> assign(shown: {actor, poll_id}, notice: nil)
         |> load_polls()
         |> new_form()
         |> load_poll()}
    end
  end

  @impl true
  def handle_event("validate", %{"poll" => params}, socket),
    do: {:noreply, assign(socket, :form, AshPhoenix.Form.validate(socket.assigns.form, params))}

  def handle_event("start", %{"poll" => params}, socket) do
    case AshPhoenix.Form.submit(socket.assigns.form, params: params) do
      {:ok, poll} -> {:noreply, socket |> new_form() |> push_patch(to: ~p"/polls/#{poll.id}")}
      {:error, form} -> {:noreply, assign(socket, :form, form)}
    end
  end

  def handle_event("vote", %{"choice" => choice}, %{assigns: %{actor: actor}} = socket)
      when actor != nil do
    case Polls.vote(socket.assigns.poll_id, %{choice: choice}, actor: actor) do
      {:ok, _vote} -> {:noreply, socket |> assign(:notice, nil) |> load_poll()}
      {:error, error} -> {:noreply, socket |> assign(:notice, refusal(error)) |> load_poll()}
    end
  end

  def handle_event("vote", _params, socket),
    do: {:noreply, assign(socket, :notice, "Choose one, then vote.")}

  def handle_event("end", _params, %{assigns: %{poll: %Read{value: %Poll{} = poll}}} = socket) do
    case Polls.end_poll(poll, actor: socket.assigns.actor) do
      {:ok, _poll} -> {:noreply, socket |> assign(:notice, nil) |> load_poll()}
      {:error, error} -> {:noreply, socket |> assign(:notice, refusal(error)) |> load_poll()}
    end
  end

  # The account as it reads now, before each event and each background result
  # (`Session.check_component_lease/2`).
  defp take_account(socket, account), do: assign(socket, :actor, Human.for_account(account))

  @impl true
  def render(assigns) do
    assigns = assign(assigns, :now, DateTime.utc_now())

    ~H"""
    <article id="polls-page" class="account-page">
      <.portal id="polls-sidebar" target="#shell-sidebar-page">
        <div class="shell-sidebar__page">
          <Primitives.notice :if={@polls.state in [:error, :stale]} tone="error">
            The polls couldn’t be loaded. Refresh the page to try again.
          </Primitives.notice>
          <.link patch={~p"/polls"} class="polls-new" aria-current={is_nil(@poll_id) && "page"}>
            Start a poll
          </.link>
          <ul id="polls-list" class="shell-sidebar__list polls-list" data-state={@polls.state}>
            <li :if={@polls.value == []} class="shell-sidebar__empty">No polls yet.</li>
            <li :for={poll <- sorted(@polls.value)} id={"polls-list-#{poll.id}"}>
              <.link
                patch={~p"/polls/#{poll.id}"}
                class="polls-list__item"
                aria-current={@poll_id == poll.id && "page"}
              >
                <span class="polls-list__question">{poll.question}</span>
                <span class="polls-list__state rg-muted">{list_state(poll)}</span>
              </.link>
            </li>
          </ul>
        </div>
      </.portal>

      <.page_head title={title(@poll)}>
        <:tip>
          A poll is open for the minutes its starter chose. Each person votes once, and the
          counts show when it closes.
        </:tip>
      </.page_head>

      <section :if={is_nil(@poll_id)} class="account-panel" aria-labelledby="poll-start-title">
        <h2 id="poll-start-title">New poll</h2>
        <.signed_out :if={is_nil(@actor)} id="polls-signed-out">
          Sign in to start a poll.
        </.signed_out>
        <.form
          :if={@actor}
          for={@form}
          id="poll-start-form"
          class="rooms-start"
          phx-change="validate"
          phx-submit="start"
          phx-target={@myself}
        >
          <Primitives.field
            :let={field}
            id="poll-start-question"
            label="Question"
            errors={FormErrors.messages(@form[:question])}
          >
            <input
              id={field.id}
              name={@form[:question].name}
              value={@form[:question].value}
              maxlength="200"
              autocomplete="off"
              phx-debounce="300"
              aria-invalid={field.aria_invalid}
              aria-describedby={field.described_by}
            />
          </Primitives.field>
          <Primitives.field
            :let={field}
            id="poll-start-choices"
            label="Choices"
            errors={FormErrors.messages(@form[:choices])}
          >
            <textarea
              id={field.id}
              name="poll[choices_text]"
              rows="4"
              phx-debounce="300"
              aria-invalid={field.aria_invalid}
              aria-describedby={field.described_by}
            >{@form.params["choices_text"]}</textarea>
            <:hint>One on each line.</:hint>
          </Primitives.field>
          <Primitives.field
            :let={field}
            id="poll-start-minutes"
            label="Open for"
            errors={FormErrors.messages(@form[:minutes])}
          >
            <select id={field.id} name={@form[:minutes].name} aria-describedby={field.described_by}>
              <option
                :for={minutes <- minutes()}
                value={minutes}
                selected={to_string(minutes) == to_string(@form[:minutes].value || 15)}
              >
                {minutes_label(minutes)}
              </option>
            </select>
          </Primitives.field>
          <Primitives.button type="submit" phx-disable-with="Starting…">Start poll</Primitives.button>
        </.form>
      </section>

      <Primitives.notice :if={@poll_id && @poll.state in [:error, :stale]} tone="error">
        This poll couldn’t be loaded. Refresh the page to try again.
      </Primitives.notice>

      <section
        :if={@poll_id && match?(%Poll{}, @poll.value)}
        id="poll"
        class="account-panel polls-poll"
        aria-labelledby="page-title"
        data-open={to_string(@poll.value.open)}
      >
        <p class="polls-poll__meta rg-muted">
          Started by <bdi>{@poll.value.starter.name}</bdi>
          <span :if={@poll.value.via_agent_id}>via agent</span>
          · {time_state(@poll.value, @now)} · {votes_label(@poll.value.votes_cast)}
        </p>

        <.form
          :if={@poll.value.open && @actor && is_nil(@poll.value.my_choice)}
          for={%{}}
          id="poll-vote-form"
          class="polls-vote"
          phx-submit="vote"
          phx-target={@myself}
        >
          <fieldset>
            <legend class="visually-hidden">Your vote</legend>
            <label :for={choice <- @poll.value.choices} class="polls-choice">
              <input type="radio" name="choice" value={choice} />
              <span>{choice}</span>
            </label>
          </fieldset>
          <Primitives.button type="submit" phx-disable-with="Voting…">Vote</Primitives.button>
        </.form>

        <ul
          :if={
            is_nil(@poll.value.totals) &&
              !(@poll.value.open && @actor && is_nil(@poll.value.my_choice))
          }
          class="polls-choices"
        >
          <li
            :for={choice <- @poll.value.choices}
            class="polls-choice"
            data-mine={to_string(choice == @poll.value.my_choice)}
          >
            {choice}
          </li>
        </ul>

        <ol :if={@poll.value.totals} id="poll-counts" class="polls-counts">
          <li
            :for={%{choice: choice, votes: votes} <- @poll.value.totals}
            class="polls-count"
            data-mine={to_string(choice == @poll.value.my_choice)}
            style={"--share: #{share(votes, @poll.value.votes_cast)}%"}
          >
            <span class="polls-count__choice">{choice}</span>
            <span class="polls-count__votes">{votes_label(votes)}</span>
          </li>
        </ol>

        <p :if={@poll.value.my_choice} id="poll-my-vote" class="polls-poll__mine">
          You voted for “{@poll.value.my_choice}”.
        </p>
        <p :if={@poll.value.open && is_nil(@actor)} class="rg-muted">Sign in to vote.</p>
        <p :if={@poll.value.open && is_nil(@poll.value.totals)} class="rg-muted">
          The counts show when the poll closes.
        </p>

        <Primitives.notice :if={@notice} tone="warning">{@notice}</Primitives.notice>

        <Primitives.button
          :if={@poll.value.open && @poll.value.mine}
          id="poll-end"
          type="button"
          variant="secondary"
          phx-click="end"
          phx-target={@myself}
          data-confirm="End this poll now? Nobody can vote after, and the counts show to everyone."
          data-confirm-action="End"
        >
          End poll
        </Primitives.button>
      </section>
    </article>
    """
  end

  defp minutes, do: @minutes

  defp minutes_label(1), do: "1 minute"
  defp minutes_label(minutes), do: "#{minutes} minutes"

  # Open polls first, then the rest; newest first within each.
  defp sorted(nil), do: []
  defp sorted(polls), do: Enum.sort_by(polls, &(!&1.open))

  defp list_state(%{open: true, votes_cast: votes}), do: "Open · #{votes_label(votes)}"
  defp list_state(%{votes_cast: votes}), do: "Closed · #{votes_label(votes)}"

  defp votes_label(1), do: "1 vote"
  defp votes_label(votes), do: "#{votes} votes"

  defp time_state(%{open: false, ended_at: nil}, _now), do: "Closed"
  defp time_state(%{open: false}, _now), do: "Ended early"

  defp time_state(poll, now) do
    case div(DateTime.diff(poll.closes_at, now, :second) + 59, 60) do
      minutes when minutes <= 1 -> "Closes within a minute"
      minutes -> "Closes in #{minutes} minutes"
    end
  end

  defp share(_votes, 0), do: 0
  defp share(votes, cast), do: round(votes * 100 / cast)

  defp title(%Read{value: %Poll{question: question}}), do: question
  defp title(_read), do: "Polls"

  defp refusal(%Ash.Error.Invalid{} = error) do
    case FormErrors.details(error) do
      [%{message: message} | _] -> message
      _none -> "That couldn’t be done. Refresh the page and try again."
    end
  end

  defp refusal(%Ash.Error.Forbidden{}), do: "Only the person who started this poll ends it."
  defp refusal(_error), do: "That couldn’t be done. Try again."

  defp load_polls(socket) do
    Read.now(socket, :polls, actor_id(socket), fn ->
      Polls.list_polls(actor: socket.assigns.actor)
    end)
  end

  defp load_poll(%{assigns: %{poll_id: nil}} = socket),
    do: socket |> Read.clear(:poll) |> stop_clock()

  defp load_poll(%{assigns: %{poll_id: id, actor: actor}} = socket) do
    socket
    |> Read.now(:poll, {id, actor_id(socket)}, fn ->
      case Polls.get_poll(id, actor: actor) do
        {:ok, nil} -> {:error, :gone}
        result -> result
      end
    end)
    |> start_clock()
  end

  # While the poll on the page is open, it is read again in a minute, or at its
  # close if that comes first.
  defp start_clock(%{assigns: %{poll: %Read{value: %Poll{open: true} = poll}}} = socket) do
    socket = stop_clock(socket)
    wait = poll.closes_at |> DateTime.diff(DateTime.utc_now(), :millisecond) |> max(0)

    timer =
      send_update_after(
        self(),
        __MODULE__,
        [id: socket.assigns.id, tick: true],
        min(wait + 50, @minute)
      )

    assign(socket, :clock, timer)
  end

  defp start_clock(socket), do: stop_clock(socket)

  defp stop_clock(%{assigns: %{clock: nil}} = socket), do: socket

  defp stop_clock(%{assigns: %{clock: timer}} = socket) do
    Process.cancel_timer(timer)
    assign(socket, :clock, nil)
  end

  defp actor_id(%{assigns: %{actor: nil}}), do: nil
  defp actor_id(%{assigns: %{actor: actor}}), do: actor.human_account_id

  defp new_form(%{assigns: %{actor: nil}} = socket), do: assign(socket, :form, nil)

  defp new_form(%{assigns: %{actor: actor}} = socket) do
    form =
      Poll
      |> AshPhoenix.Form.for_create(:start,
        actor: actor,
        as: "poll",
        prepare_params: fn params, _phase ->
          choices =
            (params["choices_text"] || "")
            |> String.split(~r/\R/u)
            |> Enum.map(&String.trim/1)
            |> Enum.reject(&(&1 == ""))

          Map.put(params, "choices", choices)
        end
      )
      |> to_form()

    assign(socket, :form, form)
  end
end
