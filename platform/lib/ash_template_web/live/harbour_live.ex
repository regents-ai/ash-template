defmodule AshTemplateWeb.HarbourLive do
  @moduledoc """
  The agent harbour: one ship for each agent, sailing to the island of the
  agent's last action and circling it. The inn is a chat, the forge is work and
  the castle is a proposal.

  The agents here are samples. While the page is connected, one of them does
  something new every few seconds, so a ship sets sail for another island.
  Nothing here reads or changes anything outside the page.

  The harbour is drawn as a blueprint.
  """

  use AshTemplateWeb, :live_view

  alias Phoenix.LiveView.JS

  # Each island, the action that sends a ship there, and what the legend calls it.
  @places [
    %{id: "inn", name: "Inn", action: "Chat"},
    %{id: "forge", name: "Forge", action: "Work"},
    %{id: "castle", name: "Castle", action: "Proposal"}
  ]

  # The sample agents, each with the colour of its sail and the place of its last action.
  @crew [
    %{id: "ada", name: "Ada", color: "#e4572e", place: "inn"},
    %{id: "basil", name: "Basil", color: "#17bebb", place: "forge"},
    %{id: "clio", name: "Clio", color: "#f2c14e", place: "castle"},
    %{id: "dot", name: "Dot", color: "#7b61ff", place: "inn"},
    %{id: "ezra", name: "Ezra", color: "#4caf50", place: "forge"},
    %{id: "fern", name: "Fern", color: "#2e86de", place: "castle"}
  ]

  @every :timer.seconds(7)

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: :timer.send_interval(@every, :act)

    {:ok,
     socket
     |> assign(AshTemplateWeb.PublicDocuments.page("/animations/harbour"))
     |> assign(places: @places, crew: @crew)}
  end

  # One agent, chosen at random, does something at a different place.
  @impl true
  def handle_info(:act, socket) do
    agent = Enum.random(socket.assigns.crew)
    place = @places |> Enum.map(& &1.id) |> List.delete(agent.place) |> Enum.random()

    crew =
      Enum.map(socket.assigns.crew, &if(&1.id == agent.id, do: %{&1 | place: place}, else: &1))

    {:noreply, assign(socket, crew: crew)}
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
        data-harbour-crew={Jason.encode!(Enum.map(@crew, &Map.take(&1, [:id, :place, :color])))}
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
        <canvas id="harbour-canvas" phx-update="ignore" data-harbour-canvas></canvas>
      </div>
      <ul class="harbour__legend" aria-label="Where each agent is">
        <li :for={place <- @places}>
          <p><strong>{place.name}</strong> {place.action}</p>
          <ul>
            <li :for={agent <- @crew} :if={agent.place == place.id} style={"--sail: #{agent.color}"}>
              {agent.name}
            </li>
          </ul>
        </li>
      </ul>
    </main>
    """
  end
end
