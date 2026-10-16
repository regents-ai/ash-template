defmodule AshTemplateWeb.HarbourLive do
  @moduledoc """
  The agent harbour: one ship for each agent, sailing to the island of the
  agent's last action and circling it. The inn is a chat, the forge is work and
  the castle is a proposal.

  The agents here are samples. While the page is connected, one of them does
  something new every few seconds, so a ship sets sail for another island.
  Nothing here reads or changes anything outside the page.

  The harbour is drawn as a blueprint. Pressing a ship, or an agent's name under
  the harbour, opens that agent's card; `?agent=` names the agent, so each card
  has its own link.
  """

  use AshTemplateWeb, :live_view

  alias Phoenix.LiveView.JS

  # Each island, the action that sends a ship there, and what the legend calls it.
  @places [
    %{id: "inn", name: "Inn", action: "Chat"},
    %{id: "forge", name: "Forge", action: "Work"},
    %{id: "castle", name: "Castle", action: "Proposal"}
  ]

  @place_ids Enum.map(@places, & &1.id)
  @places_by_id Map.new(@places, &{&1.id, &1})

  # The sample agents: the Key each one holds, the colour of its sail, and the
  # place of its last action.
  @crew [
    %{id: "ada", name: "Ada", key: 17, color: "#e4572e", place: "inn"},
    %{id: "basil", name: "Basil", key: 204, color: "#17bebb", place: "forge"},
    %{id: "clio", name: "Clio", key: 388, color: "#f2c14e", place: "castle"},
    %{id: "dot", name: "Dot", key: 512, color: "#7b61ff", place: "inn"},
    %{id: "ezra", name: "Ezra", key: 731, color: "#4caf50", place: "forge"},
    %{id: "fern", name: "Fern", key: 966, color: "#2e86de", place: "castle"}
  ]

  @every :timer.seconds(7)

  # How many actions an agent's card lists, newest first.
  @kept 4

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: :timer.send_interval(@every, :act)
    now = DateTime.utc_now()

    {:ok,
     socket
     |> assign(AshTemplateWeb.PublicDocuments.page("/animations/harbour"))
     |> assign(
       places: @places,
       crew: Enum.with_index(@crew, &with_history(&1, &2, now)),
       now: now
     )}
  end

  # A sample agent's earlier actions: its last one a little while ago, and one
  # at each other place before that.
  defp with_history(agent, index, now) do
    earlier = List.delete(@place_ids, agent.place)
    last = DateTime.add(now, -(40 + index * 70))

    actions =
      [agent.place | earlier]
      |> Enum.with_index(fn place, step ->
        %{place: place, at: DateTime.add(last, -step * 260)}
      end)

    Map.put(agent, :actions, actions)
  end

  @impl true
  def handle_params(params, _uri, socket) do
    agent_id = if Enum.any?(socket.assigns.crew, &(&1.id == params["agent"])), do: params["agent"]
    {:noreply, assign(socket, agent_id: agent_id)}
  end

  # One agent, chosen at random, does something at a different place.
  @impl true
  def handle_info(:act, socket) do
    now = DateTime.utc_now()
    agent = Enum.random(socket.assigns.crew)
    place = @place_ids |> List.delete(agent.place) |> Enum.random()

    acted = %{
      agent
      | place: place,
        actions: Enum.take([%{place: place, at: now} | agent.actions], @kept)
    }

    crew = Enum.map(socket.assigns.crew, &if(&1.id == agent.id, do: acted, else: &1))

    {:noreply, assign(socket, crew: crew, now: now)}
  end

  @impl true
  def handle_event("show_agent", %{"id" => id}, socket) do
    {:noreply, push_patch(socket, to: ~p"/animations/harbour?#{[agent: id]}")}
  end

  def handle_event("close_agent", _params, socket) do
    {:noreply, push_patch(socket, to: ~p"/animations/harbour")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <main id="harbour-lab" class="motion-lab">
      <header class="motion-lab__head">
        <p class="motion-lab__kicker">
          <a href={~p"/"}>Ash Template</a> / <a href={~p"/animations"}>Motion lab</a> / Harbour
        </p>
        <h1>Agent harbour</h1>
        <p class="motion-lab__lede">
          Each ship is an agent. It sails to the island of its last action and circles there
          until it does something new.
        </p>
      </header>
      <div
        id="harbour"
        class="harbour"
        phx-hook="Harbour"
        phx-mounted={JS.ignore_attributes(["data-harbour-ready"])}
        data-harbour-crew={
          Jason.encode!(Enum.map(@crew, &Map.take(&1, [:id, :name, :place, :color])))
        }
        aria-hidden="true"
      >
        <img
          class="harbour__still harbour__still--light"
          src={~p"/images/animations/harbour-light.webp"}
          width="1035"
          height="581"
          alt=""
        />
        <img
          class="harbour__still harbour__still--dark"
          src={~p"/images/animations/harbour-dark.webp"}
          width="1035"
          height="581"
          alt=""
        />
        <div id="harbour-stage" class="harbour__stage" phx-update="ignore">
          <canvas id="harbour-canvas" data-harbour-canvas></canvas>
          <span class="harbour__tag" data-harbour-tag hidden></span>
        </div>
      </div>
      <ul class="harbour__legend" aria-label="Where each agent is">
        <li :for={place <- @places}>
          <p><strong>{place.name}</strong> {place.action}</p>
          <ul>
            <li :for={agent <- @crew} :if={agent.place == place.id} style={"--sail: #{agent.color}"}>
              <.link patch={~p"/animations/harbour?#{[agent: agent.id]}"}>{agent.name}</.link>
            </li>
          </ul>
        </li>
      </ul>
      <.agent_card
        :if={@agent_id}
        agent={Enum.find(@crew, &(&1.id == @agent_id))}
        now={@now}
      />
    </main>
    """
  end

  attr :agent, :map, required: true
  attr :now, DateTime, required: true

  # An agent's card: its Key, its last action and the ones before it. It opens as
  # it is rendered and closes with its X, Escape or the browser's back button.
  defp agent_card(assigns) do
    ~H"""
    <dialog
      id="harbour-agent"
      class="harbour-card"
      aria-labelledby="harbour-agent-title"
      phx-hook="InfoDialog"
      data-open
      data-close-event="close_agent"
    >
      <header class="harbour-card__head">
        <span class="harbour-card__sail" style={"--sail: #{@agent.color}"}></span>
        <div>
          <h2 id="harbour-agent-title">{@agent.name}</h2>
          <p>Key #{@agent.key}</p>
        </div>
        <form method="dialog">
          <button type="submit" class="harbour-card__close" aria-label="Close">
            <svg viewBox="0 0 16 16" aria-hidden="true">
              <path d="M3 3l10 10M13 3L3 13" fill="none" stroke="currentColor" stroke-width="1.5" />
            </svg>
          </button>
        </form>
      </header>
      <ol class="harbour-card__actions" aria-label="Recent actions">
        <li :for={action <- @agent.actions}>
          <span>{doing(action.place)}</span>
          <time datetime={DateTime.to_iso8601(action.at)}>{ago(action.at, @now)}</time>
        </li>
      </ol>
    </dialog>
    """
  end

  defp doing(place) do
    %{name: name, action: action} = Map.fetch!(@places_by_id, place)
    "#{action} at the #{name}"
  end

  defp ago(at, now) do
    case DateTime.diff(now, at) do
      seconds when seconds < 10 -> "Just now"
      seconds when seconds < 60 -> "#{seconds} s ago"
      seconds -> "#{div(seconds, 60)} min ago"
    end
  end
end
