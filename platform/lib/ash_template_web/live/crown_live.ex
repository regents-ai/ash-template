defmodule AshTemplateWeb.CrownLive do
  @moduledoc """
  The glass crown, shown by itself: the example a site copies when it wants the
  crown on a page of its own. Nothing here reads or changes anything outside
  the page.
  """

  use AshTemplateWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, AshTemplateWeb.PublicDocuments.page("/animations/crown"))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <main id="crown-lab" class="motion-lab">
      <header class="motion-lab__head">
        <p class="motion-lab__kicker">
          <a href={~p"/"}>Ash Template</a> / <a href={~p"/animations"}>Motion lab</a> / Crown
        </p>
        <h1>Crown</h1>
        <p class="motion-lab__lede">
          Thirteen glass cubes and three beams of light. Move the pointer to swing the light;
          each quarter of the stage gives it a colour of its own.
        </p>
      </header>
      <div class="crown-stage">
        <.crown id="crown" look="hero">
          <img
            class="crown__still"
            src={~p"/images/home/hero-bg-dark.svg"}
            width="1700"
            height="1200"
            alt=""
            fetchpriority="high"
          />
        </.crown>
      </div>
    </main>
    """
  end

  # The glass crown: thirteen cubes and three beams of light, drawn behind the
  # stage it decorates.
  #
  # Where the crown can be drawn live, the `Crown` hook draws it on the canvas; for
  # a visitor who asked for less motion it is drawn once, at rest, and left alone.
  # Where it cannot be drawn (no WebGPU, no JavaScript) the stage shows what the
  # page put inside the component: a still picture marked `class="crown__still"`,
  # which steps aside once a live crown has really been drawn. A page that gives
  # none shows its bare stage.
  #
  # Put it first inside a positioned stage. It fills that stage, sits behind what
  # follows it and takes no pointer events; the pointer over the stage turns it.
  # `:look` names one of the looks in `assets/js/crown_looks.ts`.
  attr :id, :string, required: true
  attr :look, :string, required: true

  slot :inner_block, doc: "the still picture, an `<img class=\"crown__still\">`"

  defp crown(assigns) do
    ~H"""
    <div
      id={@id}
      class="crown"
      phx-hook="Crown"
      phx-mounted={JS.ignore_attributes(["data-crown-ready"])}
      data-crown-look={@look}
      aria-hidden="true"
    >
      {render_slot(@inner_block)}
      <canvas id={"#{@id}-canvas"} phx-update="ignore" data-crown-canvas></canvas>
    </div>
    """
  end
end
