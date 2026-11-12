defmodule AshTemplateWeb.InkLabLive do
  @moduledoc """
  Ink: hairlines in the page's own ink, in two views, each its own link
  (`?view=lines` and `?view=hero`) chosen by the shared tabs.

  - Lines: a small scene, hills, a sun, a road and two birds, whose strokes draw
    themselves once when the view arrives, then rest.
  - Hero: a ground ruled in squares, seen first flat from far away, that widens
    once into a deep view whose rules meet at the horizon, under a heading.

  Both are one GPU picture (the `InkLines` hook, one canvas island). The words
  are real text beside or over it, so the page reads the same with less motion
  asked for, off screen, or without the picture. Nothing here reads or changes
  anything outside the page.
  """

  use AshTemplateWeb, :live_view

  alias AshTemplateWeb.PublicDocuments
  alias Regent.Primitives

  @views [{"lines", "Lines"}, {"hero", "Hero"}]

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, PublicDocuments.page(~p"/animations/ink"))}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    view = if params["view"] == "hero", do: "hero", else: "lines"
    {:noreply, assign(socket, view: view)}
  end

  @impl true
  def render(assigns) do
    assigns = assign(assigns, :views, @views)

    ~H"""
    <main id="ink-lab" class="motion-lab motion-lab--ink">
      <header class="motion-lab__head">
        <p class="motion-lab__kicker">
          <a href={~p"/"}>Ash Template</a> / <a href={~p"/animations"}>Motion lab</a> / Ink
        </p>
        <h1>Ink</h1>
      </header>

      <Primitives.tabs
        id="ink-views"
        label="Views"
        phx-hook="MotionTravel"
        tabs={
          for {value, label} <- @views do
            %{label: label, patch: ~p"/animations/ink?#{[view: value]}", current: value == @view}
          end
        }
      />

      <figure
        id="ink-picture"
        class="ink-lab"
        phx-hook="InkLines"
        phx-mounted={JS.ignore_attributes(["data-ink-ready"])}
        data-ink-view={@view}
      >
        <div id="ink-picture-stage" class="ink-lab__stage" phx-update="ignore" aria-hidden="true">
          <canvas data-ink-canvas></canvas>
        </div>
        <figcaption :if={@view == "lines"} class="ink-lab__caption">Hills, drawn once</figcaption>
        <div :if={@view == "hero"} class="ink-lab__hero">
          <h2 class="ink-lab__title">Horizon</h2>
          <p class="ink-lab__line">Ruled ground, from far to near</p>
        </div>
      </figure>
    </main>
    """
  end
end
