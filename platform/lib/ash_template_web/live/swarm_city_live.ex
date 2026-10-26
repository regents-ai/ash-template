defmodule AshTemplateWeb.SwarmCityLive do
  @moduledoc """
  The swarm city: a dense city of thin outlined towers with three downtowns,
  and each agent a yellow disc flying to the district of its last action and
  circling its towers. The inn is a chat, the forge is work and the castle is a
  proposal.

  The agents are the same samples as the agent harbour's. While the page is
  connected, one of them does something new every few seconds, so its disc
  crosses the city to another district. Nothing here reads or changes anything
  outside the page.

  Pressing a disc, or an agent's name under the city, opens that agent's card;
  `?agent=` names the agent, so each card has its own link.

  Each district has its own page at `/animations/swarm-city/<district>`, where
  the camera flies to it and lights it. A mouse over a district shows a card
  with the link; pressing the district, or its name under the city, follows it.
  """

  use AshTemplateWeb, :live_view

  alias AshTemplateWeb.{PublicDocuments, SampleCrew}
  alias Phoenix.LiveView.JS

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: :timer.send_interval(SampleCrew.every(), :act)
    now = DateTime.utc_now()

    {:ok, assign(socket, places: SampleCrew.places(), crew: SampleCrew.crew(now), now: now)}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    place = SampleCrew.place!(params["place"])
    agent_id = SampleCrew.agent_id(socket.assigns.crew, params["agent"])

    {:noreply,
     socket
     |> assign(PublicDocuments.page(city_path(place)))
     |> assign(place: place, agent_id: agent_id)}
  end

  # The city's own page, or a district's.
  defp city_path(place, query \\ [])
  defp city_path(nil, query), do: ~p"/animations/swarm-city?#{query}"
  defp city_path(place, query), do: ~p"/animations/swarm-city/#{place.id}?#{query}"

  # What each district's own page says about it.
  defp about("inn"),
    do: "Where agents chat. An agent circles the inn's tower while its last action is a chat."

  defp about("forge"),
    do: "Where agents work. An agent circles the forge's stacks while its last action is work."

  defp about("castle"),
    do:
      "Where agents make proposals. An agent circles the castle's spire while its last action is a proposal."

  # One agent, chosen at random, does something at a different place.
  @impl true
  def handle_info(:act, socket) do
    now = DateTime.utc_now()
    {:noreply, assign(socket, crew: SampleCrew.act(socket.assigns.crew, now), now: now)}
  end

  @impl true
  def handle_event("show_agent", %{"id" => id}, socket) do
    {:noreply, push_patch(socket, to: city_path(socket.assigns.place, agent: id))}
  end

  def handle_event("close_agent", _params, socket) do
    {:noreply, push_patch(socket, to: city_path(socket.assigns.place))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <main id="swarm-city-lab" class="motion-lab">
      <header class="motion-lab__head">
        <p :if={!@place} class="motion-lab__kicker">
          <a href={~p"/"}>Ash Template</a> / <a href={~p"/animations"}>Motion lab</a> / Swarm city
        </p>
        <p :if={@place} class="motion-lab__kicker">
          <a href={~p"/"}>Ash Template</a>
          / <a href={~p"/animations"}>Motion lab</a>
          / <.link patch={~p"/animations/swarm-city"}>Swarm city</.link>
          / {@place.name}
        </p>
        <h1>{if @place, do: @place.name, else: "Swarm city"}</h1>
        <p class="motion-lab__lede">
          {if @place,
            do: about(@place.id),
            else:
              "Each yellow disc is an agent. It flies to the district of its last action and circles the towers there until it does something new. Drag to turn the city."}
        </p>
      </header>
      <div
        id="swarm-city"
        class="swarm-city"
        phx-hook="SwarmCity"
        phx-mounted={JS.ignore_attributes(["data-swarm-ready"])}
        data-swarm-crew={SampleCrew.drawn(@crew)}
        data-swarm-focus={@place && @place.id}
        role="img"
        aria-label="The swarm city"
      >
        <img
          class="swarm-city__still"
          src={~p"/images/animations/swarm-city.webp"}
          width="1280"
          height="720"
          alt=""
        />
        <div id="swarm-city-stage" class="swarm-city__stage" phx-update="ignore" data-swarm-stage>
          <canvas id="swarm-city-canvas" data-swarm-canvas></canvas>
          <span class="harbour__tag" data-swarm-tag hidden></span>
          <.link
            :for={place <- @places}
            patch={~p"/animations/swarm-city/#{place.id}"}
            class="harbour__isle"
            data-swarm-district={place.id}
            tabindex="-1"
            hidden
          >
            <strong>{place.name}</strong>
            <span>Visit</span>
          </.link>
        </div>
      </div>
      <div class="harbour__legend">
        <ul class="harbour__islands" aria-label="Districts">
          <li :for={place <- @places}>
            <.link
              patch={~p"/animations/swarm-city/#{place.id}"}
              aria-current={@place == place && "page"}
            >
              {place.name}
            </.link>
            <span>{place.action}</span>
          </li>
        </ul>
        <ul class="harbour__crew" aria-label="Where each agent is" style={"--rows: #{length(@crew)}"}>
          <li
            :for={{agent, row} <- Enum.with_index(@crew, 1)}
            style={"--sail: #{agent.color}; grid-area: #{row} / #{SampleCrew.column(agent.place)}"}
          >
            <.link patch={city_path(@place, agent: agent.id)}>{agent.name}</.link>
            <span class="visually-hidden">at the {SampleCrew.place_name(agent.place)}</span>
          </li>
        </ul>
      </div>
      <SampleCrew.agent_card
        :if={@agent_id}
        agent={Enum.find(@crew, &(&1.id == @agent_id))}
        now={@now}
      />
    </main>
    """
  end
end
