defmodule AshTemplateWeb.SplatsLabLive do
  @moduledoc """
  Splats: every small world in pixel art the site draws, each a few hundred thousand 3D
  splats, turning once every thirty seconds while everything in it plays an eight-second
  loop. One tab for each: the robot factory, the floating island at night, the gallery
  on its lawn, then every numbered scene (`AshTemplateWeb.Scenes`) in number order
  under its title. A drag
  turns and tilts the scene, and a pinch, a wheel with Ctrl or Cmd held, the keys + and
  - or the box's Zoom in and Zoom out buttons bring it nearer, up to four times, at the
  pointer or the middle; Reset view, 0, a double-click or a double tap goes back to the
  opening view. The factory comes first, at the bare address; `?scene=<name>` shows
  another (`island`, `gallery`, or a numbered scene's name such as `fishing`), and any other value
  shows the factory. On a wide screen the tabs wrap onto as many lines as they need; on
  a phone they keep to one row, which scrolls sideways on its own, and the shared
  `MotionTravel` hook keeps the current tab in view there.

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

  Under the box, Formats offers the scene in every form it exists in: Picture
  (`-item.png`, 1080 by 1080) and Card (`-card.png`, 1440 by 960), each in a new tab;
  for a numbered scene also Full view (its own page) and Metadata (its trait file); and
  Download GIF (`SplatStage.gif/1`), which saves one seamless loop of the scene as
  `regents-<scene>.gif`, drawn and encoded in the browser (`assets/js/splats/gif.ts`).
  Download GIF is offered once the scene has drawn, so never without WebGPU, and keeps
  its place before then.

  Under Formats, a numbered scene shows its traits, open: its number and whether it is
  Action or Chill (`SplatStage.meta/1`), its rarity score (`SplatStage.rarity/1`) and
  every trait it was dealt (`SplatStage.traits/1`), the same parts the Scenes page shows.
  The factory and the island have none, so nothing shows there. The lede links the
  Scenes page, which shows the numbered scenes side by side. Nothing here reads or
  changes anything outside the page.
  """

  use AshTemplateWeb, :live_view

  alias AshTemplateWeb.Components.SplatStage
  alias AshTemplateWeb.{PublicDocuments, Scenes}

  # The three scenes that are not numbered; the numbered ones follow, from Scenes.
  @unnumbered [
    %{
      name: "factory",
      title: "Factory",
      number: nil,
      label:
        "A solarpunk robot factory on a floating island at dusk: a workshop hall with a sawtooth roof of glass, plants and solar panels, a brick chimney, two wind turbines, a water wheel, robot arms over an assembly line and robots at work, with a brass engine underneath."
    },
    %{
      name: "island",
      title: "Island",
      number: nil,
      label:
        "A floating island at night with a great tree, two pines, a cottage, a campfire and a pond whose stream falls off the edge, over glowing crystals."
    },
    %{
      name: "gallery",
      title: "Gallery",
      number: nil,
      label:
        "A flat-roofed gallery of purple stone and warm wood on a floating lawn above morning cloud: portraits in its windows, a glass stairwell, a pond with a fish, a bench, a gentleman in a top hat saying GM and a sign reading M.o.B.A., while two small creatures fly round it together."
    }
  ]

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket |> assign(PublicDocuments.page(~p"/animations/splats")) |> assign(scenes: scenes())}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    scenes = socket.assigns.scenes
    scene = Enum.find(scenes, &(&1.name == params["scene"])) || hd(scenes)
    {:noreply, assign(socket, scene: scene)}
  end

  # Each numbered scene as Scenes gives it, traits and all, with the stage's label.
  defp scenes do
    @unnumbered ++
      for scene <- Scenes.all(),
          do: Map.put(scene, :label, "#{scene.title}. #{scene.description}")
  end

  defp scene_path(%{name: "factory"}), do: ~p"/animations/splats"
  defp scene_path(%{name: name}), do: ~p"/animations/splats?#{[scene: name]}"

  # Each form the scene exists in besides the GIF, as {name, address}.
  defp formats(scene),
    do:
      [{"Picture", Scenes.still(scene, :item)}, {"Card", Scenes.still(scene, :card)}] ++
        pages(scene)

  defp pages(%{number: nil}), do: []

  defp pages(%{number: number}),
    do: [{"Full view", ~p"/scenes/#{number}"}, {"Metadata", ~p"/scenes/#{number}/metadata.json"}]

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
          Small worlds, turning slowly. Drag one to turn it, or to look from above or below.
          Pinch, or use the buttons in its corner, to look closer.
          The numbered ones each list the traits they were dealt;
          <.link navigate={~p"/animations/scenes"}>Scenes</.link>
          shows them side by side.
        </p>
      </header>
      <%!-- More tabs than the shared tabs take: they wrap on a wide screen, and on a
      phone MotionTravel scrolls the current one into view inside the row. --%>
      <nav
        id="splats-tabs"
        class="flair-tabs splats-lab__tabs"
        aria-label="Scenes"
        phx-hook="MotionTravel"
      >
        <.link
          :for={scene <- @scenes}
          patch={scene_path(scene)}
          aria-current={scene.name == @scene.name && "page"}
        >
          {scene.title}
        </.link>
      </nav>
      <div class="splats-lab__view">
        <%!-- The square still's width is the one at which splats_lab.css turns the box square. --%>
        <SplatStage.stage
          id={"splats-#{@scene.name}"}
          class="splats-lab"
          scene={@scene.name}
          label={@scene.label}
          file={Scenes.file(@scene)}
          still={Scenes.still(@scene, :wide)}
          square={Scenes.still(@scene, :square)}
        />
        <section class="splats-lab__formats" aria-labelledby="splats-formats-title">
          <h2 id="splats-formats-title" class="splats-lab__title">Formats</h2>
          <p class="splat-links splats-lab__links">
            <a :for={{name, href} <- formats(@scene)} href={href} target="_blank" rel="noopener">
              {name} <Regent.Icons.icon name="arrow-up-right" />
            </a>
          </p>
          <SplatStage.gif for={"splats-#{@scene.name}"} class="splats-lab__gif" />
        </section>
        <section
          :if={@scene.number}
          class="splats-lab__traits"
          aria-labelledby="splats-traits-title"
        >
          <div class="splats-lab__traits-head">
            <h2 id="splats-traits-title" class="splats-lab__title">Traits</h2>
            <SplatStage.meta scene={@scene} />
            <SplatStage.rarity scene={@scene} class="splats-lab__rarity" />
          </div>
          <SplatStage.traits scene={@scene} />
        </section>
      </div>
    </main>
    """
  end
end
