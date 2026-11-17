defmodule AshTemplateWeb.SplatsLabLive do
  @moduledoc """
  Splats: two small worlds in pixel art, a robot factory and a floating island, each a
  few hundred thousand 3D splats, turning once every thirty seconds while everything in
  them plays an eight-second loop. The robot factory comes first; `?scene=island` shows
  the floating island at night instead, and any other value shows the factory.

  Each scene is one baked file, `priv/static/splats/<scene>.bin` (laid out in
  `assets/js/splats/studio/FORMAT.md`), served gzipped and digested like the other
  static files. The box always holds the scene's still picture for its shape
  (`priv/static/images/animations/splats-<scene>-wide.png`, or `-square.png` on a phone,
  both drawn from the same files by `npm run stills:splats`). Over it the `SplatIsland`
  hook downloads the file the box names (`data-splats-file`), draws the scene with
  WebGPU and fades it in once its first frame has landed; until then, and without
  WebGPU, the still stays. Each scene's box has its own id, so switching ends one
  scene's drawing before the next begins.

  Download GIF, at the end of the tabs' row, saves one seamless loop of the scene
  showing as `regents-<scene>.gif`, drawn and encoded in the browser
  (`assets/js/splats/gif.ts`). It is offered once the scene has drawn, so never without
  WebGPU, and keeps its place on the row before then. Its control has the box's id with
  `-gif` after it, which is how the `SplatIsland` hook finds it. Nothing here reads or
  changes anything outside the page.
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
      "A solarpunk robot factory on a floating island at dusk: a workshop hall with a sawtooth roof of glass, plants and solar panels, a brick chimney, two wind turbines, a water wheel, robot arms over an assembly line and robots at work, with a brass engine underneath. Drag, or use the arrow keys, to turn and tilt it."

  defp label("island"),
    do:
      "A floating island at night with a great tree, two pines, a cottage, a campfire and a pond whose stream falls off the edge, over glowing crystals. Drag, or use the arrow keys, to turn and tilt it."

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
        <%!-- The SplatIsland hook finds this by the box's id and keeps its state
        (data-gif) and words; it shows once the scene has drawn (splats_lab.css). --%>
        <div
          id={"splats-#{@scene}-gif"}
          class="splats-gif"
          phx-mounted={JS.ignore_attributes(["data-gif"])}
        >
          <p class="splats-gif__failed">Could not make the GIF. Try again.</p>
          <Regent.Primitives.button
            id={"splats-#{@scene}-gif-button"}
            variant="secondary"
            arrow={false}
            class="splats-gif__button"
            phx-mounted={JS.ignore_attributes(["aria-disabled", "aria-busy"])}
          >
            <span class="splats-gif__words">
              <span class="splats-gif__idle">Download GIF</span>
              <span class="splats-gif__making">
                Making
                <Regent.Primitives.figure
                  id={"splats-#{@scene}-gif-done"}
                  value="0%"
                  width={4}
                  phx-update="ignore"
                />
              </span>
            </span>
          </Regent.Primitives.button>
          <span
            id={"splats-#{@scene}-gif-status"}
            class="visually-hidden"
            role="status"
            phx-update="ignore"
          ></span>
        </div>
      </div>
      <div
        id={"splats-#{@scene}"}
        class="splats-lab"
        tabindex="0"
        role="img"
        aria-label={label(@scene)}
        data-splats-scene={@scene}
        data-splats-file={scene_file(@scene)}
        phx-hook="SplatIsland"
        phx-mounted={JS.ignore_attributes(["data-splats-ready"])}
      >
        <%!-- The same width as the CSS that turns the box square (splats_lab.css). --%>
        <picture>
          <source media="(max-width: 36rem)" srcset={@stills.square} width="360" height="360" />
          <img class="splats-lab__still" src={@stills.wide} width="480" height="320" alt="" />
        </picture>
        <div id={"splats-#{@scene}-stage"} class="splats-lab__stage" phx-update="ignore">
          <canvas data-splats-canvas></canvas>
        </div>
      </div>
    </main>
    """
  end
end
