defmodule AshTemplateWeb.WorldCubeLive do
  @moduledoc """
  The world cube, shown by itself: the example a site copies when it wants the
  cube on a page of its own, with the homepage's six worlds. Nothing here reads
  or changes anything outside the page.
  """

  use AshTemplateWeb, :live_view

  alias AshTemplateWeb.Components.WorldCube

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(AshTemplateWeb.PublicDocuments.page("/animations/cube"))
     |> assign(worlds: AshTemplateWeb.HomeLive.worlds())}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <main id="world-cube-lab" class="motion-lab">
      <header class="motion-lab__head">
        <p class="motion-lab__kicker">
          <a href={~p"/"}>Ash Template</a> / <a href={~p"/animations"}>Motion lab</a> / World cube
        </p>
        <h1>World cube</h1>
        <p class="motion-lab__lede">
          Six rooms in one cube. Turn it, rest on a side to bring it closer, click to step in.
          Inside, look left, up or right: a pane of glass shows each way.
        </p>
      </header>
      <WorldCube.cube id="world-cube" label="The six worlds" worlds={@worlds} />
    </main>
    """
  end
end
