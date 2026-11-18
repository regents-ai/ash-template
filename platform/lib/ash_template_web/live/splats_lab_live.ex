defmodule AshTemplateWeb.SplatsLabLive do
  @moduledoc """
  Splats: seven small worlds in pixel art, each a few hundred thousand 3D splats,
  turning once every thirty seconds while everything in them plays an eight-second
  loop. A drag turns and tilts the scene, and a pinch, a wheel with Ctrl or Cmd held,
  the keys + and - or the box's Zoom in and Zoom out buttons bring it nearer, up to four
  times, at the pointer or the middle; Reset view, 0, a double-click or a double tap goes
  back to the opening view. The robot factory comes first; `?scene=<id>` shows another
  of `@scenes` instead (`island`, `campfire`, `battle`, `circus`, `fishing`, `meteor`),
  and any other value shows the factory.

  Each scene is one baked file, `priv/static/splats/<id>.bin` (laid out in
  `assets/js/splats/studio/FORMAT.md`, baked from `studio/<id>.cjs`), served gzipped and
  digested like the other static files. The box always holds the scene's still picture
  for its shape (`priv/static/images/animations/splats-<id>-wide.png`, or `-square.png`
  on a phone, both drawn from the same files by `npm run stills:splats`, one pixel an art
  pixel, so `wide` and `square` in `@scenes` are their sizes). Over it the `SplatIsland`
  hook downloads the file the box names (`data-splats-file`), draws the scene with
  WebGPU and fades it in once its first frame has landed; until then, and without
  WebGPU, the still stays. Each scene's box has its own id, so switching ends one
  scene's drawing before the next begins, and only the scene showing is downloaded.

  The zoom buttons sit in a corner of the stage, inside the box, and show once the
  scene has drawn. The hook finds them by `data-splats-zoom` (`in`, `out`, `home`) and
  keeps their `aria-disabled` up to date; the server sends them as the opening view
  has them, Zoom out and Reset view with nothing to do. The box is a labelled group,
  not a picture, so the buttons inside it stay reachable to a screen reader.

  Download GIF, at the end of the tabs' row, saves one seamless loop of the scene
  showing as `regents-<scene>.gif`, drawn and encoded in the browser
  (`assets/js/splats/gif.ts`). It is offered once the scene has drawn, so never without
  WebGPU, and keeps its place on the row before then. Its control has the box's id with
  `-gif` after it, which is how the `SplatIsland` hook finds it. Nothing here reads or
  changes anything outside the page.
  """

  use AshTemplateWeb, :live_view

  alias AshTemplateWeb.PublicDocuments

  @moving "Drag, or use the arrow keys, to turn and tilt it. Pinch, or press plus and minus, to look closer, and 0 to go back to the start."

  # In tab order, the first the default. `wide` and `square` are the stills' sizes: the
  # art-pixel grid of a 1440 by 960 stage and of a 1080 square one, which is coarser for
  # a scene whose camera stands nearer (fishing).
  @scenes [
    %{
      id: "factory",
      name: "Factory",
      wide: {480, 320},
      square: 360,
      label:
        "A solarpunk robot factory on a floating island at dusk: a workshop hall with a sawtooth roof of glass, plants and solar panels, a brick chimney, two wind turbines, a water wheel, robot arms over an assembly line and robots at work, with a brass engine underneath."
    },
    %{
      id: "island",
      name: "Island",
      wide: {480, 320},
      square: 360,
      label:
        "A floating island at night with a great tree, two pines, a cottage, a campfire and a pond whose stream falls off the edge, over glowing crystals."
    },
    %{
      id: "campfire",
      name: "Campfire",
      wide: {480, 320},
      square: 360,
      label:
        "A robot factory on a snowy floating rock at blue hour, where a robot owl tells a story round a campfire to a frog and two robots, beside a lava pool that falls off the edge."
    },
    %{
      id: "battle",
      name: "Battle",
      wide: {480, 320},
      square: 360,
      label:
        "A green crater on a giant twenty-sided die at golden hour, where a crowned toad throws a spark at a spider in front of a castle keep."
    },
    %{
      id: "circus",
      name: "Circus",
      wide: {480, 320},
      square: 360,
      label:
        "A drive-in cinema inside a snow globe at midnight, with a jet-pack flyer dodging a swarm of missiles on curling smoke trails round the glass."
    },
    %{
      id: "fishing",
      name: "Fishing",
      wide: {360, 240},
      square: 270,
      label:
        "A glass greenhouse dome on a black slab in golden smog, where a dragon in a wizard hat fishes in a hot spring beside a standing monolith."
    },
    %{
      id: "meteor",
      name: "Meteor",
      wide: {480, 320},
      square: 360,
      label:
        "A coral reef on a floating rock under a starry noon sky, where a chrome neighbour on a disco floor bats a falling meteor back into the sky."
    }
  ]

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket |> assign(PublicDocuments.page(~p"/animations/splats")) |> assign(scenes: @scenes)}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply,
     assign(socket, scene: Enum.find(@scenes, hd(@scenes), &(&1.id == params["scene"])))}
  end

  defp scene_path(%{id: "factory"}), do: ~p"/animations/splats"
  defp scene_path(%{id: id}), do: ~p"/animations/splats?#{[scene: id]}"

  defp scene_file(%{id: id}), do: ~p"/splats/#{id <> ".bin"}"

  defp still(%{id: id}, shape), do: ~p"/images/animations/#{"splats-#{id}-#{shape}.png"}"

  defp label(%{label: label}), do: "#{label} #{@moving}"

  attr :scene, :string, required: true
  attr :action, :string, required: true, values: ~w(in out home)
  attr :label, :string, required: true
  attr :icon, :string, required: true

  attr :at_limit, :boolean,
    default: false,
    doc: "true when the opening view leaves it nothing to do"

  defp zoom_button(assigns) do
    ~H"""
    <Regent.Primitives.button
      id={"splats-#{@scene}-zoom-#{@action}"}
      variant="secondary"
      arrow={false}
      class="splats-zoom__button"
      data-splats-zoom={@action}
      aria-label={@label}
      aria-disabled={to_string(@at_limit)}
      phx-mounted={JS.ignore_attributes(["aria-disabled"])}
    >
      <Regent.Icons.icon name={@icon} />
    </Regent.Primitives.button>
    """
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
          Seven small worlds, turning slowly. Drag one to turn it, or to look from above or below.
          Pinch, or use the buttons in its corner, to look closer.
        </p>
      </header>
      <div class="splats-lab__bar">
        <nav class="flair-tabs" aria-label="Scenes">
          <.link
            :for={scene <- @scenes}
            patch={scene_path(scene)}
            aria-current={scene == @scene && "page"}
          >
            {scene.name}
          </.link>
        </nav>
        <%!-- The SplatIsland hook finds this by the box's id and keeps its state
        (data-gif) and words; it shows once the scene has drawn (splats_lab.css). --%>
        <div
          id={"splats-#{@scene.id}-gif"}
          class="splats-gif"
          phx-mounted={JS.ignore_attributes(["data-gif"])}
        >
          <p class="splats-gif__failed">Could not make the GIF. Try again.</p>
          <Regent.Primitives.button
            id={"splats-#{@scene.id}-gif-button"}
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
                  id={"splats-#{@scene.id}-gif-done"}
                  value="0%"
                  width={4}
                  phx-update="ignore"
                />
              </span>
            </span>
          </Regent.Primitives.button>
          <span
            id={"splats-#{@scene.id}-gif-status"}
            class="visually-hidden"
            role="status"
            phx-update="ignore"
          ></span>
        </div>
      </div>
      <div
        id={"splats-#{@scene.id}"}
        class="splats-lab"
        tabindex="0"
        role="group"
        aria-label={label(@scene)}
        data-splats-scene={@scene.id}
        data-splats-file={scene_file(@scene)}
        phx-hook="SplatIsland"
        phx-mounted={JS.ignore_attributes(["data-splats-ready"])}
      >
        <%!-- The same width as the CSS that turns the box square (splats_lab.css). --%>
        <picture>
          <source
            media="(max-width: 36rem)"
            srcset={still(@scene, "square")}
            width={@scene.square}
            height={@scene.square}
          />
          <img
            class="splats-lab__still"
            src={still(@scene, "wide")}
            width={elem(@scene.wide, 0)}
            height={elem(@scene.wide, 1)}
            alt=""
          />
        </picture>
        <div id={"splats-#{@scene.id}-stage"} class="splats-lab__stage" phx-update="ignore">
          <canvas data-splats-canvas></canvas>
        </div>
        <%!-- The SplatIsland hook finds these by data-splats-zoom and keeps their
        aria-disabled; they show once the scene has drawn (splats_lab.css). --%>
        <div class="splats-zoom">
          <.zoom_button scene={@scene.id} action="out" label="Zoom out" icon="minus" at_limit />
          <.zoom_button scene={@scene.id} action="in" label="Zoom in" icon="plus" />
          <.zoom_button scene={@scene.id} action="home" label="Reset view" icon="scan" at_limit />
        </div>
      </div>
    </main>
    """
  end
end
