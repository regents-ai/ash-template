defmodule AshTemplateWeb.DatascapeLive do
  @moduledoc """
  The datascape: an endless dark plane of panels, tubes and specks in three
  layers of depth, drawn live on the visitor's graphics card. Moving the pointer
  towards an edge of the picture flies that way; panels open as they come into
  view, the one under the pointer grows, and a pressed one starts again.

  The picture is a canvas island with a still picture the server draws first,
  kept for a visitor who asked for less motion or whose browser cannot draw it.
  Nothing here reads or changes anything outside the page.
  """

  use AshTemplateWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, AshTemplateWeb.PublicDocuments.page("/animations/datascape"))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <main id="datascape-lab" class="motion-lab datascape-lab">
      <header class="motion-lab__head">
        <p class="motion-lab__kicker">
          <a href={~p"/"}>Ash Template</a> / <a href={~p"/animations"}>Motion lab</a> / Datascape
        </p>
        <h1>Datascape</h1>
        <p class="motion-lab__lede">
          Move the pointer towards an edge to fly that way, or hold a finger there. Panels open as
          they come into view. Rest on one and it grows; press it and it starts again.
        </p>
      </header>
      <div
        id="datascape"
        class="datascape"
        phx-hook="Datascape"
        phx-mounted={JS.ignore_attributes(["data-datascape-ready"])}
        role="img"
        aria-label="The datascape"
      >
        <img
          class="datascape__still"
          src={~p"/images/animations/datascape.webp"}
          width="1600"
          height="900"
          alt=""
        />
        <div id="datascape-stage" class="datascape__stage" phx-update="ignore">
          <canvas id="datascape-canvas" data-datascape-canvas></canvas>
        </div>
      </div>
    </main>
    """
  end
end
