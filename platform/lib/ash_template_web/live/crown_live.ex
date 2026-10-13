defmodule AshTemplateWeb.CrownLive do
  @moduledoc """
  The glass crown, shown by itself: the example a site copies when it wants the
  crown on a page of its own. Nothing here reads or changes anything outside
  the page.
  """

  use AshTemplateWeb, :live_view

  alias AshTemplateWeb.Components.Crown

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
        <Crown.crown id="crown" look="hero">
          <img
            class="crown__still"
            src={~p"/images/home/hero-bg-dark.svg"}
            width="1700"
            height="1200"
            alt=""
            fetchpriority="high"
          />
        </Crown.crown>
      </div>
    </main>
    """
  end
end
