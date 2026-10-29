defmodule AshTemplateWeb.SwarmCityLive do
  @moduledoc """
  The swarm city: a dense city of thin outlined towers with three downtowns,
  and each agent a disc flying to the district of its last action and circling
  its towers. The inn is a chat, the forge is work and the castle is a
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

  The city comes in several looks, each with its own colours and way of
  drawing it; `?look=` names one, and the first needs no name. Changing the look
  repaints the city where it stands. The looks in a site's palette follow
  the page's theme, light or dark.
  """

  use AshTemplateWeb, :live_view

  alias AshTemplateWeb.{NotFoundError, PublicDocuments, SampleCrew}
  alias Phoenix.LiveView.JS

  # A themed look paints the city one way while the page is light and another while it is dark.
  @looks [
    %{id: "neon", name: "Neon", themed: false},
    %{id: "regents-neon", name: "Regents neon", themed: true},
    %{id: "techtree-neon", name: "Techtree neon", themed: true},
    %{id: "autolaunch-neon", name: "Autolaunch neon", themed: true},
    %{id: "patchbay-neon", name: "Patchbay neon", themed: true},
    %{id: "blueprint", name: "Blueprint", themed: false},
    %{id: "porcelain", name: "Porcelain", themed: false},
    %{id: "lamplight", name: "Lamplight", themed: false},
    %{id: "sunset", name: "Sunset", themed: false},
    %{id: "hologram", name: "Hologram", themed: false},
    %{id: "afterglow", name: "Afterglow", themed: false},
    %{id: "showroom", name: "Showroom", themed: false},
    %{id: "opal", name: "Opal", themed: false},
    %{id: "obsidian", name: "Obsidian", themed: false}
  ]
  @looks_by_id Map.new(@looks, &{&1.id, &1})
  @first_look hd(@looks)

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: :timer.send_interval(SampleCrew.every(), :act)
    now = DateTime.utc_now()

    {:ok,
     assign(socket,
       places: SampleCrew.places(),
       looks: @looks,
       crew: SampleCrew.crew(now),
       now: now
     )}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    place = SampleCrew.place!(params["place"])
    look = look!(params["look"])
    agent_id = SampleCrew.agent_id(socket.assigns.crew, params["agent"])

    {:noreply,
     socket
     |> assign(PublicDocuments.page(city_path(place, @first_look)))
     |> assign(place: place, look: look, agent_id: agent_id)}
  end

  # The look an address names, or the first for none; a look that does not exist is not found.
  defp look!(nil), do: @first_look
  defp look!(id), do: Map.get(@looks_by_id, id) || raise(NotFoundError)

  # The city's own page, or a district's, in a look.
  defp city_path(place, look, query \\ [])
  defp city_path(nil, look, query), do: ~p"/animations/swarm-city?#{look_query(look) ++ query}"

  defp city_path(place, look, query),
    do: ~p"/animations/swarm-city/#{place.id}?#{look_query(look) ++ query}"

  # The picture shown before the city draws: one for each theme of a themed look.
  defp stills(%{themed: true, id: id}),
    do: for(theme <- ~w(light dark), do: %{theme: theme, file: "#{id}-#{theme}.webp"})

  defp stills(%{id: id}), do: [%{theme: nil, file: "#{id}.webp"}]

  defp look_query(@first_look), do: []
  defp look_query(look), do: [look: look.id]

  # What each district's own page says about it.
  defp about("inn"),
    do:
      "Agents chat at the inn. An agent circles the inn's tower while its last action is a chat."

  defp about("forge"),
    do:
      "Agents work at the forge. An agent circles the forge's stacks while its last action is work."

  defp about("castle"),
    do:
      "Agents make proposals at the castle. An agent circles the castle's spire while its last action is a proposal."

  # One agent, chosen at random, does something at a different place.
  @impl true
  def handle_info(:act, socket) do
    now = DateTime.utc_now()
    {:noreply, assign(socket, crew: SampleCrew.act(socket.assigns.crew, now), now: now)}
  end

  @impl true
  def handle_event("show_agent", %{"id" => id}, socket) do
    {:noreply,
     push_patch(socket, to: city_path(socket.assigns.place, socket.assigns.look, agent: id))}
  end

  def handle_event("close_agent", _params, socket) do
    {:noreply, push_patch(socket, to: city_path(socket.assigns.place, socket.assigns.look))}
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
          / <.link patch={city_path(nil, @look)}>Swarm city</.link>
          / {@place.name}
        </p>
        <h1>{if @place, do: @place.name, else: "Swarm city"}</h1>
        <p class="motion-lab__lede">
          {if @place,
            do: about(@place.id),
            else:
              "Each disc is an agent. It flies to the district of its last action and circles the towers there until it does something new. Drag to turn the city."}
        </p>
      </header>
      <nav class="flair-tabs" aria-label="Looks">
        <.link
          :for={look <- @looks}
          patch={city_path(@place, look)}
          aria-current={look == @look && "page"}
        >
          {look.name}
        </.link>
      </nav>
      <div
        id="swarm-city"
        class="swarm-city"
        phx-hook="SwarmCity"
        phx-mounted={JS.ignore_attributes(["data-swarm-ready"])}
        data-swarm-crew={SampleCrew.drawn(@crew)}
        data-swarm-focus={@place && @place.id}
        data-swarm-look={@look.id}
        data-swarm-themed={@look.themed}
        data-swarm-query={URI.encode_query(look_query(@look))}
        role="img"
        aria-label="The swarm city"
      >
        <img
          :for={still <- stills(@look)}
          class={["swarm-city__still", still.theme && "swarm-city__still--#{still.theme}"]}
          src={~p"/images/animations/swarm-city/#{still.file}"}
          width="1280"
          height="720"
          alt=""
        />
        <div id="swarm-city-stage" class="swarm-city__stage" phx-update="ignore" data-swarm-stage>
          <canvas id="swarm-city-canvas" data-swarm-canvas></canvas>
          <span class="harbour__tag" data-swarm-tag hidden></span>
          <.link
            :for={place <- @places}
            patch={city_path(place, @look)}
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
            <.link patch={city_path(place, @look)} aria-current={@place == place && "page"}>
              {place.name}
            </.link>
            <span>{place.action}</span>
          </li>
        </ul>
        <ul class="harbour__crew" aria-label="Crew" style={"--rows: #{length(@crew)}"}>
          <li
            :for={{agent, row} <- Enum.with_index(@crew, 1)}
            style={"--sail: #{agent.color}; grid-area: #{row} / #{SampleCrew.column(agent.place)}"}
          >
            <.link patch={city_path(@place, @look, agent: agent.id)}>{agent.name}</.link>
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
