defmodule AshTemplateWeb.AskLabLive do
  @moduledoc """
  The ask bar: one field where a person types what they want, and the page answers
  with a view built only from a closed list of blocks (a figure, a list, a chart, an
  agent's activity, a confirm step). The question lives in the address as `?q=`, so
  the same link draws the same view on any visit, and the form works without script
  as a plain GET.

  `AshTemplateWeb.AskLab` turns the question into a plan and checks it before any of
  it is drawn: a plain keyword match over sample data, with no model and no network.
  An unknown question shows "No match" and three questions it does know. The States
  section shows the answer loading, empty and failed. Nothing here reads or changes
  anything outside the page; the confirm step's button never sends anything.
  """

  use AshTemplateWeb, :live_view

  alias AshTemplateWeb.{AskLab, PublicDocuments}
  alias Regent.{Agents, Charts, Primitives}

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, PublicDocuments.page(~p"/animations/ask"))}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    question = String.trim(params["q"] || "")
    now = DateTime.utc_now(:second)
    {:noreply, assign(socket, question: question, now: now, answer: answer(question, now))}
  end

  @impl true
  def handle_event("ask", %{"q" => question}, socket) do
    to =
      case String.trim(question) do
        "" -> ~p"/animations/ask"
        question -> ~p"/animations/ask?#{[q: question]}"
      end

    {:noreply, push_patch(socket, to: to)}
  end

  defp answer("", _now), do: :idle

  defp answer(question, now) do
    with {:ok, plan} <- AskLab.answer(question, now),
         {:ok, plan} <- AskLab.check(plan) do
      {:plan, plan}
    else
      :no_match -> :no_match
      {:error, _reason} -> :failed
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <main id="ask-lab" class="motion-lab motion-lab--ask">
      <header class="motion-lab__head">
        <p class="motion-lab__kicker">
          <a href={~p"/"}>Ash Template</a> / <a href={~p"/animations"}>Motion lab</a> / Ask
        </p>
        <h1>Ask</h1>
      </header>

      <form
        id="ask-form"
        class="ask-bar"
        action={~p"/animations/ask"}
        method="get"
        role="search"
        phx-submit="ask"
        phx-hook="AskBar"
      >
        <label for="ask-q" class="visually-hidden">Ask</label>
        <Regent.Icons.icon name="search" class="ask-bar__icon" />
        <input
          id="ask-q"
          class="ask-bar__input"
          type="search"
          name="q"
          value={@question}
          placeholder="Points, offers, notes"
          autocomplete="off"
          enterkeyhint="go"
        />
        <kbd class="ask-bar__key" aria-hidden="true">/</kbd>
      </form>

      <section id="ask-answer" class="ask-answer" aria-live="polite">
        <.answer answer={@answer} now={@now} />
      </section>

      <section class="ask-states" aria-labelledby="ask-states-title">
        <h2 id="ask-states-title" class="ask-states__title">States</h2>
        <div class="ask-states__grid">
          <div class="ask-states__state">
            <h3 class="ask-block__label">Loading</h3>
            <Primitives.waiting id="ask-state-loading-figure" class="ask-block ask-block--figure">
              <span></span>
            </Primitives.waiting>
            <Primitives.waiting id="ask-state-loading-chart" class="ask-block ask-block--chart">
              <span></span>
            </Primitives.waiting>
          </div>
          <div class="ask-states__state">
            <h3 class="ask-block__label">Empty</h3>
            <.no_match id="ask-state-empty" />
          </div>
          <div class="ask-states__state">
            <h3 class="ask-block__label">Failed</h3>
            <.failed id="ask-state-failed" />
          </div>
        </div>
      </section>
    </main>
    """
  end

  attr :answer, :any, required: true
  attr :now, DateTime, required: true

  defp answer(%{answer: :idle} = assigns) do
    ~H"""
    <ul class="ask-examples" aria-label="Examples">
      <li :for={example <- AskLab.examples()}>
        <.link patch={~p"/animations/ask?#{[q: example]}"} class="ask-example">{example}</.link>
      </li>
    </ul>
    """
  end

  defp answer(%{answer: :no_match} = assigns), do: ~H|<.no_match id="ask-none" />|
  defp answer(%{answer: :failed} = assigns), do: ~H|<.failed id="ask-failed" />|

  defp answer(%{answer: {:plan, plan}} = assigns) do
    assigns = assign(assigns, plan: plan)

    ~H"""
    <div id="ask-plan" class="ask-plan">
      <h2 class="ask-plan__title">{@plan.title}</h2>
      <div class="ask-plan__blocks">
        <.block
          :for={{block, i} <- Enum.with_index(@plan.blocks)}
          id={"ask-block-#{i}"}
          block={block}
          now={@now}
        />
      </div>
    </div>
    """
  end

  attr :id, :string, required: true

  defp no_match(assigns) do
    ~H"""
    <Primitives.empty_state id={@id} title="No match" class="ask-block">
      <ul class="ask-examples" aria-label="Examples">
        <li :for={example <- AskLab.examples()}>
          <.link patch={~p"/animations/ask?#{[q: example]}"} class="ask-example">{example}</.link>
        </li>
      </ul>
    </Primitives.empty_state>
    """
  end

  attr :id, :string, required: true

  defp failed(assigns) do
    ~H"""
    <Primitives.waiting id={@id} state={:error} class="ask-block ask-block--figure">
      <span></span>
    </Primitives.waiting>
    """
  end

  attr :id, :string, required: true
  attr :block, :map, required: true
  attr :now, DateTime, required: true

  defp block(%{block: %{block: :figure}} = assigns) do
    ~H"""
    <article id={@id} class="ask-block ask-block--figure">
      <h3 class="ask-block__label">{@block.props.label}</h3>
      <p class="ask-block__figure">
        <Primitives.figure value={@block.props.value} />
        <span :if={@block.props.unit} class="ask-block__unit">{@block.props.unit}</span>
      </p>
      <p class="ask-block__line">{@block.props.line}</p>
    </article>
    """
  end

  defp block(%{block: %{block: :list}} = assigns) do
    ~H"""
    <article id={@id} class="ask-block ask-block--list">
      <h3 class="ask-block__label">{@block.props.label}</h3>
      <ul :if={@block.props.rows != []} class="ask-list">
        <li :for={row <- @block.props.rows} class="ask-list__row">
          <span>{row.name}</span>
          <Primitives.figure value={row.value} />
        </li>
      </ul>
      <p :if={@block.props.rows == []} class="ask-block__line">{@block.props.none}</p>
    </article>
    """
  end

  defp block(%{block: %{block: :chart}} = assigns) do
    ~H"""
    <Charts.line
      id={@id}
      class="ask-block ask-block--chart"
      label={@block.props.label}
      phx-hook="MotionChart"
      series={[%{name: @block.props.label, points: @block.props.points}]}
      fill
    />
    """
  end

  defp block(%{block: %{block: :activity}} = assigns) do
    ~H"""
    <Agents.activity
      id={@id}
      class="ask-block ask-block--activity"
      label={@block.props.label}
      phx-hook="MotionActivity"
      steps={@block.props.steps}
      now={@now}
    />
    """
  end

  defp block(%{block: %{block: :confirm}} = assigns) do
    ~H"""
    <article id={@id} class="ask-block ask-block--confirm">
      <h3 class="ask-block__label">{@block.props.label}</h3>
      <dl class="ask-confirm">
        <div :for={row <- @block.props.rows} class="ask-list__row">
          <dt>{row.name}</dt>
          <dd><Primitives.figure value={row.value} /></dd>
        </div>
      </dl>
      <div class="ask-confirm__action">
        <Primitives.button disabled>{@block.props.action}</Primitives.button>
        <span class="ask-block__line">Sample only</span>
      </div>
    </article>
    """
  end
end
