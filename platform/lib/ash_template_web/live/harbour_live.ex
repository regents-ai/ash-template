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
     |> assign(PublicDocuments.page(harbour_path(place)))
     |> assign(place: place, agent_id: agent_id)}
  end

  # The harbour's own page, or an island's.
  defp harbour_path(place, query \\ [])
  defp harbour_path(nil, query), do: ~p"/animations/harbour?#{query}"
  defp harbour_path(place, query), do: ~p"/animations/harbour/#{place.id}?#{query}"

  # What each island's own page says about it.
  defp about("inn"),
    do: "Agents chat at the inn. A ship circles the inn while its agent's last action is a chat."

  defp about("forge"),
    do:
      "Agents work at the forge. A ship circles the forge while its agent's last action is work."

  defp about("castle"),
    do:
      "Agents make proposals at the castle. A ship circles the castle while its agent's last action is a proposal."

  # One agent, chosen at random, does something at a different place.
  @impl true
  def handle_info(:act, socket) do
    now = DateTime.utc_now()
    {:noreply, assign(socket, crew: SampleCrew.act(socket.assigns.crew, now), now: now)}
  end

  @impl true
  def handle_event("show_agent", %{"id" => id}, socket) do
    {:noreply, push_patch(socket, to: harbour_path(socket.assigns.place, agent: id))}
  end

  def handle_event("close_agent", _params, socket) do
    {:noreply, push_patch(socket, to: harbour_path(socket.assigns.place))}
  end

  @impl true
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
            do: about(@place.id),
            else:
              "Each ship is an agent. It sails to the island of its last action and circles there until it does something new."}
        </p>
      </header>
      <div
        id="harbour"
        class="harbour"
        phx-hook="Harbour"
        phx-mounted={JS.ignore_attributes(["data-harbour-ready"])}
        data-harbour-crew={SampleCrew.drawn(@crew)}
        role="img"
        aria-label="The agent harbour"
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
      </div>
      <div class="harbour__legend">
        <ul class="harbour__islands" aria-label="Islands">
          <li :for={place <- @places}>
            <.link
              patch={~p"/animations/harbour/#{place.id}"}
              aria-current={@place == place && "page"}
            >
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
            <.link patch={harbour_path(@place, agent: agent.id)}>{agent.name}</.link>
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
