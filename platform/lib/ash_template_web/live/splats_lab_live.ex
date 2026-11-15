defmodule AshTemplateWeb.SplatsLabLive do
  @moduledoc """
  Splats: two small worlds drawn as a few hundred thousand 3D gaussians (splats) and
  shown as pixel art, turning once every thirty seconds. The robot factory comes
  first; `?scene=island` shows the floating island at night instead, and any other
  value shows the factory.

  The box always holds the scene's still picture for its shape
  (`priv/static/images/animations/splats-<scene>-wide.png`, or `-square.png` on a phone,
  both drawn by `npm run stills:splats`).
  Over it the `SplatIsland` hook draws the scene with WebGPU and fades it in once its
  first frame has landed; without WebGPU the still stays. Each scene's box has its own
  id, so switching ends one scene's drawing before the next begins. The scenes are
  grown from fixed seeds in `assets/js/splats/`, so the stills and the live pictures
  match. Nothing here reads or changes anything outside the page.
  """

  use AshTemplateWeb, :live_view

  alias AshTemplateWeb.PublicDocuments

  @scenes [
    %{id: "factory", name: "Factory"},
    %{id: "island", name: "Island"}
  ]

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket |> assign(PublicDocuments.page(~p"/animations/splats")) |> assign(scenes: @scenes)}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    scene = scene(params["scene"])
    {:noreply, assign(socket, scene: scene, stills: stills(scene))}
  end

  defp scene("island"), do: "island"
  defp scene(_other), do: "factory"

  defp scene_path("factory"), do: ~p"/animations/splats"
  defp scene_path(scene), do: ~p"/animations/splats?#{[scene: scene]}"

  defp stills("factory"),
    do: %{
      wide: ~p"/images/animations/splats-factory-wide.png",
      square: ~p"/images/animations/splats-factory-square.png"
    }

  defp stills("island"),
    do: %{
      wide: ~p"/images/animations/splats-island-wide.png",
      square: ~p"/images/animations/splats-island-square.png"
    }

  defp label("factory"),
    do:
      "A solarpunk robot factory on a floating island at dusk: a plaster hall with a planted roof and the Regents crown lit over its open door, a glass hall of plants, solar panels, two wind turbines, a water tower and robots at work. Drag, or use the arrow keys, to turn and tilt it."

  defp label("island"),
    do:
      "A floating island at night with a large tree, two small pines, rocks, a stone crown and a campfire. Drag, or use the arrow keys, to turn and tilt it."

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
          Two small worlds, turning slowly. Drag one to turn it, or to look from above or below.
        </p>
      </header>
      <nav class="flair-tabs" aria-label="Scenes">
        <.link
          :for={scene <- @scenes}
          patch={scene_path(scene.id)}
          aria-current={scene.id == @scene && "page"}
        >
          {scene.name}
        </.link>
      </nav>
      <div
        id={"splats-#{@scene}"}
        class="splats-lab"
        tabindex="0"
        role="img"
        aria-label={label(@scene)}
        data-splats-scene={@scene}
        phx-hook="SplatIsland"
        phx-mounted={JS.ignore_attributes(["data-splats-ready"])}
      >
        <%!-- The same width as the CSS that turns the box square (splats_lab.css). --%>
        <picture>
          <source media="(max-width: 36rem)" srcset={@stills.square} width="432" height="432" />
          <img class="splats-lab__still" src={@stills.wide} width="432" height="288" alt="" />
        </picture>
        <div id={"splats-#{@scene}-stage"} class="splats-lab__stage" phx-update="ignore">
          <canvas data-splats-canvas></canvas>
        </div>
      </div>
    </main>
    """
  end
end
