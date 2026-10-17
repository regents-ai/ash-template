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

  Each island has its own page at `/animations/harbour/<island>`, with the same
  harbour. A mouse over an island shows a card with the link; pressing the
  island, or its name under the harbour, follows it.

  `/animations/harbour/sea` shows the same harbour as a page's background: seen
  from low down, square to the page, the sea running out to the horizon, with a
  room's conversation over it. The button at the top lifts the page away to
  show the whole sea, and brings it back.
  """

  use AshTemplateWeb, :live_view

  alias AshTemplateWeb.{NotFoundError, PublicDocuments}
  alias Phoenix.LiveView.JS

  # Each island, the action that sends a ship there, what the legend calls it,
  # and what its own page says about it.
  @places [
    %{
      id: "inn",
      name: "Inn",
      action: "Chat",
      about: "Where agents chat. A ship circles the inn while its agent's last action is a chat."
    },
    %{
      id: "forge",
      name: "Forge",
      action: "Work",
      about: "Where agents work. A ship circles the forge while its agent's last action is work."
    },
    %{
      id: "castle",
      name: "Castle",
      action: "Proposal",
      about:
        "Where agents make proposals. A ship circles the castle while its agent's last action is a proposal."
    }
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

  # A few lines of a room, to show the sea behind a page of text.
  @room (for {id, text} <- [
               {"ada", "Morning. The forge queue is clear, so I'm taking the next task."},
               {"basil", "I'll run the notebook for the price study and post what it finds."},
               {"clio",
                "Proposal 12 is up: move 400 USDC to the build budget. Votes close Friday."},
               {"dot", "Seconded. I'll write the summary for the members tonight."}
             ] do
           agent = Enum.find(@crew, &(&1.id == id))
           %{name: agent.name, key: agent.key, color: agent.color, text: text}
         end)

  @every :timer.seconds(7)

  # How many actions an agent's card lists, newest first.
  @kept 4

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: :timer.send_interval(@every, :act)
    now = DateTime.utc_now()

    {:ok,
     assign(socket,
       places: @places,
       room: @room,
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
    place = place!(params["place"])
    agent_id = if Enum.any?(socket.assigns.crew, &(&1.id == params["agent"])), do: params["agent"]

    {:noreply,
     socket
     |> assign(PublicDocuments.page(harbour_path(socket.assigns.live_action, place)))
     |> assign(place: place, agent_id: agent_id)}
  end

  defp place!(nil), do: nil
  defp place!(id), do: Map.get(@places_by_id, id) || raise(NotFoundError)

  # The harbour's own page, an island's, or the sea behind a page.
  defp harbour_path(action, place, query \\ [])
  defp harbour_path(:sea, nil, query), do: ~p"/animations/harbour/sea?#{query}"
  defp harbour_path(_action, nil, query), do: ~p"/animations/harbour?#{query}"
  defp harbour_path(_action, place, query), do: ~p"/animations/harbour/#{place.id}?#{query}"

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
    %{live_action: action, place: place} = socket.assigns
    {:noreply, push_patch(socket, to: harbour_path(action, place, agent: id))}
  end

  def handle_event("close_agent", _params, socket) do
    %{live_action: action, place: place} = socket.assigns
    {:noreply, push_patch(socket, to: harbour_path(action, place))}
  end

  @impl true
  def render(%{live_action: :sea} = assigns) do
    ~H"""
    <main id="harbour-sea" class="sea">
      <div
        id="harbour"
        class="sea__harbour"
        phx-hook="Harbour"
        phx-mounted={JS.ignore_attributes(["data-harbour-ready"])}
        data-harbour-view="horizon"
        data-harbour-crew={
          Jason.encode!(Enum.map(@crew, &Map.take(&1, [:id, :name, :place, :color])))
        }
        aria-hidden="true"
      >
        <.stage places={@places} />
      </div>
      <button
        id="sea-lift"
        type="button"
        class="sea__lift"
        aria-controls="sea-page"
        aria-pressed="false"
        aria-label="Show the sea"
        title="Show the sea"
        phx-click={
          JS.toggle_class("sea--lifted", to: "#harbour-sea")
          |> JS.toggle_attribute({"aria-pressed", "true", "false"})
          |> JS.toggle_attribute({"aria-label", "Bring the page back", "Show the sea"})
          |> JS.toggle_attribute({"title", "Bring the page back", "Show the sea"})
        }
      >
        <svg viewBox="0 0 20 20" aria-hidden="true">
          <path d="M4 12l6-6 6 6M4 16h12" fill="none" stroke="currentColor" stroke-width="1.5" />
        </svg>
      </button>
      <div id="sea-page" class="sea__page">
        <header class="sea__head">
          <p class="motion-lab__kicker">
            <a href={~p"/"}>Ash Template</a>
            / <a href={~p"/animations"}>Motion lab</a>
            / <.link patch={~p"/animations/harbour"}>Harbour</.link>
            / Sea
          </p>
          <h1>The sea behind a page</h1>
          <p class="sea__lede">
            The harbour as a page's background. The arrow at the top lifts the page away.
          </p>
        </header>
        <nav class="sea__panel sea__places" aria-label="Where each agent is">
          <section :for={place <- @places}>
            <h2>
              <.link patch={~p"/animations/harbour/#{place.id}"}>{place.name}</.link>
            </h2>
            <ul>
              <li :for={agent <- @crew} :if={agent.place == place.id} style={"--sail: #{agent.color}"}>
                <.link patch={harbour_path(:sea, nil, agent: agent.id)}>{agent.name}</.link>
              </li>
            </ul>
          </section>
        </nav>
        <article class="sea__panel sea__room" aria-labelledby="sea-room-title">
          <h2 id="sea-room-title">General</h2>
          <ol>
            <li :for={line <- @room}>
              <p class="sea__who" style={"--sail: #{line.color}"}>
                {line.name} <span>Key #{line.key}</span>
              </p>
              <p>{line.text}</p>
            </li>
          </ol>
        </article>
      </div>
      <.agent_card
        :if={@agent_id}
        agent={Enum.find(@crew, &(&1.id == @agent_id))}
        now={@now}
      />
    </main>
    """
  end

  def render(assigns) do
    ~H"""
    <main id="harbour-lab" class="motion-lab">
      <header class="motion-lab__head">
        <p :if={!@place} class="motion-lab__kicker">
          <a href={~p"/"}>Ash Template</a> / <a href={~p"/animations"}>Motion lab</a> / Harbour
        </p>
        <p :if={@place} class="motion-lab__kicker">
          <a href={~p"/"}>Ash Template</a>
          / <a href={~p"/animations"}>Motion lab</a>
          / <.link patch={~p"/animations/harbour"}>Harbour</.link>
          / {@place.name}
        </p>
        <h1>{if @place, do: @place.name, else: "Agent harbour"}</h1>
        <p class="motion-lab__lede">
          {if @place,
            do: @place.about,
            else:
              "Each ship is an agent. It sails to the island of its last action and circles there until it does something new."}
        </p>
        <p :if={!@place} class="motion-lab__kicker">
          <.link patch={~p"/animations/harbour/sea"}>The sea behind a page</.link>
        </p>
      </header>
      <div
        id="harbour"
        class="harbour"
        phx-hook="Harbour"
        phx-mounted={JS.ignore_attributes(["data-harbour-ready"])}
        data-harbour-view="chart"
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
        <.stage places={@places} />
      </div>
      <ul class="harbour__legend" aria-label="Where each agent is">
        <li :for={place <- @places}>
          <p>
            <.link
              patch={~p"/animations/harbour/#{place.id}"}
              aria-current={@place == place && "page"}
            >
              <strong>{place.name}</strong>
            </.link>
            {place.action}
          </p>
          <ul>
            <li :for={agent <- @crew} :if={agent.place == place.id} style={"--sail: #{agent.color}"}>
              <.link patch={harbour_path(@live_action, @place, agent: agent.id)}>{agent.name}</.link>
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

  attr :places, :list, required: true

  # The canvas, the name over a ship under the mouse, and each island's card.
  # The browser draws here, so the page never patches it.
  defp stage(assigns) do
    ~H"""
    <div id="harbour-stage" class="harbour__stage" phx-update="ignore" data-harbour-stage>
      <canvas id="harbour-canvas" data-harbour-canvas></canvas>
      <span class="harbour__tag" data-harbour-tag hidden></span>
      <.link
        :for={place <- @places}
        patch={~p"/animations/harbour/#{place.id}"}
        class="harbour__isle"
        data-harbour-isle={place.id}
        tabindex="-1"
        hidden
      >
        <strong>{place.name}</strong>
        <span>Visit</span>
      </.link>
    </div>
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
