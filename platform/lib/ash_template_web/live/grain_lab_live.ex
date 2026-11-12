defmodule AshTemplateWeb.GrainLabLive do
  @moduledoc """
  Grain: a banner of harbour water seen from above, under a heading. A slow
  swell and two boats' wakes move under a fine grain that never moves, so the
  water reads like a print and stays calm enough to read the heading over.

  The water is one GPU picture (the `GrainWater` hook, one canvas island) that
  draws only while it is on screen. The heading is real text above it, so with
  less motion asked for, or without the picture, the banner is the plain page
  ground with its words. Nothing here reads or changes anything outside the page.
  """

  use AshTemplateWeb, :live_view

  alias AshTemplateWeb.PublicDocuments

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, PublicDocuments.page(~p"/animations/grain"))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <main id="grain-lab" class="motion-lab motion-lab--grain">
      <header class="motion-lab__head">
        <p class="motion-lab__kicker">
          <a href={~p"/"}>Ash Template</a> / <a href={~p"/animations"}>Motion lab</a> / Grain
        </p>
        <h1>Grain</h1>
      </header>

      <section
        id="grain-banner"
        class="grain-lab"
        phx-hook="GrainWater"
        phx-mounted={JS.ignore_attributes(["data-grain-ready"])}
        aria-labelledby="grain-title"
      >
        <div id="grain-banner-stage" class="grain-lab__stage" phx-update="ignore" aria-hidden="true">
          <canvas data-grain-canvas></canvas>
        </div>
        <div class="grain-lab__words" data-grain-words>
          <h2 id="grain-title" class="grain-lab__title">Harbour</h2>
          <p class="grain-lab__line">Fine grain, slow wakes</p>
        </div>
      </section>
    </main>
    """
  end
end
