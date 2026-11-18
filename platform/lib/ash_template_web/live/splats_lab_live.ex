defmodule AshTemplateWeb.SplatsLabLive do
  @moduledoc """
  Splats: two small worlds in pixel art, a robot factory and a floating island, each a
  few hundred thousand 3D splats, turning once every thirty seconds while everything in
  them plays an eight-second loop. A drag turns and tilts the scene, and a pinch, a
  wheel with Ctrl or Cmd held, the keys + and - or the box's Zoom in and Zoom out
  buttons bring it nearer, up to four times, at the pointer or the middle; Reset view,
  0, a double-click or a double tap goes back to the opening view. The robot factory
  comes first; `?scene=island` shows the floating island at night instead, and any
  other value shows the factory.

  Each scene is one baked file, `priv/static/splats/<scene>.bin` (laid out in
  `assets/js/splats/studio/FORMAT.md`), served gzipped and digested like the other
  static files. The box always holds the scene's still picture for its shape
  (`priv/static/images/animations/splats-<scene>-wide.png`, or `-square.png` on a phone,
  both drawn from the same files by `npm run stills:splats`). The box, with its zoom
  buttons, is the shared stage (`AshTemplateWeb.Components.SplatStage.stage/1`): over
  the still the `SplatIsland` hook downloads the file the box names, draws the scene
  with WebGPU and fades it in once its first frame has landed; until then, and without
  WebGPU, the still stays. Each scene's box has its own id, so switching ends one
  scene's drawing before the next begins. Here the box turns square on a phone.

  Download GIF, at the end of the tabs' row (`SplatStage.gif/1`), saves one seamless
  loop of the scene showing as `regents-<scene>.gif`, drawn and encoded in the browser
  (`assets/js/splats/gif.ts`). It is offered once the scene has drawn, so never without
  WebGPU, and keeps its place on the row before then. The lede links the Scenes page.
  Nothing here reads or changes anything outside the page.
  """

  use AshTemplateWeb, :live_view

  alias AshTemplateWeb.Components.SplatStage
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

  defp scene_file("factory"), do: ~p"/splats/factory.bin"
  defp scene_file("island"), do: ~p"/splats/island.bin"

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
      "A solarpunk robot factory on a floating island at dusk: a workshop hall with a sawtooth roof of glass, plants and solar panels, a brick chimney, two wind turbines, a water wheel, robot arms over an assembly line and robots at work, with a brass engine underneath."

  defp label("island"),
    do:
      "A floating island at night with a great tree, two pines, a cottage, a campfire and a pond whose stream falls off the edge, over glowing crystals."

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
          Pinch, or use the buttons in its corner, to look closer.
          Five more are on <.link navigate={~p"/animations/scenes"}>Scenes</.link>.
        </p>
      </header>
      <div class="splats-lab__bar">
        <nav class="flair-tabs" aria-label="Scenes">
          <.link
            :for={scene <- @scenes}
            patch={scene_path(scene.id)}
            aria-current={scene.id == @scene && "page"}
          >
            {scene.name}
          </.link>
        </nav>
        <SplatStage.gif for={"splats-#{@scene}"} class="splats-lab__gif" />
      </div>
      <%!-- The square still's width is the one at which splats_lab.css turns the box square. --%>
      <SplatStage.stage
        id={"splats-#{@scene}"}
        class="splats-lab"
        scene={@scene}
        label={label(@scene)}
        file={scene_file(@scene)}
        still={@stills.wide}
        square={@stills.square}
      />
    </main>
    """
  end
end
