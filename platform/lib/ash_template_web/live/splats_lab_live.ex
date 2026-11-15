defmodule AshTemplateWeb.SplatsLabLive do
  @moduledoc """
  Splats: a floating island at night, a big tree, two pines and a campfire, drawn
  as some fifty thousand small 3D gaussians (splats) and shown as pixel art, turning
  once every thirty seconds.

  The box always holds the still picture the server sends
  (`priv/static/images/animations/splats.png`, drawn by `npm run stills:splats`).
  Over it the `SplatIsland` hook draws the turning island with WebGPU and fades it in
  once its first frame has landed; without WebGPU the still stays. The island is grown
  from one fixed seed in `assets/js/splats/`, so the still and the live picture match.
  Nothing here reads or changes anything outside the page.
  """

  use AshTemplateWeb, :live_view

  alias AshTemplateWeb.PublicDocuments

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, PublicDocuments.page(~p"/animations/splats"))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <main id="splats-lab" class="motion-lab motion-lab--splats">
      <header class="motion-lab__head">
        <p class="motion-lab__kicker">
          <a href={~p"/"}>Ash Template</a> / <a href={~p"/animations"}>Motion lab</a> / Splats
        </p>
        <h1>Splats</h1>
        <p class="motion-lab__lede">
          A floating island at night, turning slowly. Drag it to turn it yourself.
        </p>
      </header>

      <div
        id="splats-island"
        class="splats-lab"
        tabindex="0"
        role="img"
        aria-label="A floating island at night with a large tree, two small pines, rocks, a stone crown and a campfire, turning slowly. Drag, or use the left and right arrow keys, to turn it."
        phx-hook="SplatIsland"
        phx-mounted={JS.ignore_attributes(["data-splats-ready"])}
      >
        <img
          class="splats-lab__still"
          src={~p"/images/animations/splats.png"}
          width="288"
          height="192"
          alt=""
        />
        <div id="splats-island-stage" class="splats-lab__stage" phx-update="ignore">
          <canvas data-splats-canvas></canvas>
        </div>
      </div>
    </main>
    """
  end
end
