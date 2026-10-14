defmodule AshTemplateWeb.TwinCubeLive do
  @moduledoc """
  The world cube and its twin, side by side: the world cube on the left for
  people browsing the sites, and the code cube on the right for agents, whose
  faces open a card of the browser tools each site's home page offers, or of
  how to connect to siwa-server. The six browser tools of this page open the
  same cards for an agent.
  """

  use AshTemplateWeb, :live_view

  alias AshTemplate.SiteTools
  alias AshTemplateWeb.Components.{CodeCube, WorldCube}
  alias AshTemplateWeb.{Read, WorldCubeLive}

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(AshTemplateWeb.PublicDocuments.page("/animations/twin-cube"))
     |> assign(
       worlds: WorldCubeLive.worlds(),
       help: SiteTools.connection_help(),
       open: nil,
       tools: %Read{}
     )}
  end

  @impl true
  def handle_event("open_card", %{"site" => site}, socket) do
    case CodeCube.face(site) do
      nil ->
        {:noreply, socket}

      %{site: "siwa"} = face ->
        {:noreply, socket |> Read.clear(:tools) |> assign(:open, face)}

      face ->
        {:noreply,
         socket
         |> assign(:open, face)
         |> Read.start(:tools, site, fn -> SiteTools.tools(site) end)}
    end
  end

  def handle_event("close_card", _params, socket) do
    {:noreply, socket |> Read.clear(:tools) |> assign(:open, nil)}
  end

  @impl true
  def handle_async({Read, :tools, _generation} = name, result, socket) do
    {:noreply, Read.settle(socket, name, result)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <main id="twin-cube-lab" class="motion-lab">
      <header class="motion-lab__head">
        <p class="motion-lab__kicker">
          <a href={~p"/"}>Ash Template</a> / <a href={~p"/animations"}>Motion lab</a> / Twin cubes
        </p>
        <h1>Twin cubes</h1>
        <p class="motion-lab__lede">
          The world cube for people, and its twin for agents. Click a side of the twin for the tools
          that site offers agents.
        </p>
      </header>
      <section
        id="twin-cube"
        class="twin-cube"
        aria-label="Two ways into the sites"
        phx-hook="TwinCube"
        phx-mounted={JS.ignore_attributes(["data-webmcp-status"])}
      >
        <div id="twin-cube-labels" class="twin-cube__labels" phx-update="ignore" aria-hidden="true">
          <p class="twin-cube__label" data-twin-label>Human Browsing</p>
          <p class="twin-cube__label" data-twin-label>Agentic WebMCP</p>
        </div>
        <WorldCube.cube id="twin-world" label="The six worlds" worlds={@worlds} />
        <CodeCube.cube id="twin-code" label="The tools each site offers agents" click="open_card" />
      </section>
      <CodeCube.card
        :if={@open}
        id="twin-card"
        face={@open}
        state={card_state(@tools)}
        tools={@tools.value || []}
        help={@help}
        close="close_card"
        retry="open_card"
      />
    </main>
    """
  end

  # A list already read stays on the card while it is read again.
  defp card_state(%Read{value: [_ | _]}), do: :ready
  defp card_state(%Read{state: state}) when state in [:empty, :error], do: state
  defp card_state(_read), do: :loading
end
