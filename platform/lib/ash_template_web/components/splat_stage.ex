defmodule AshTemplateWeb.Components.SplatStage do
  @moduledoc """
  A turning splat scene and its Download GIF control, the same wherever a scene is
  shown: the Splats page (`AshTemplateWeb.SplatsLabLive`), the Scenes page
  (`AshTemplateWeb.ScenesLabLive`) and each scene's own page
  (`AshTemplateWeb.SceneHTML`).

  `stage/1` is the box: the scene's still picture, the canvas the `SplatIsland` hook
  draws on once WebGPU is there (`assets/js/hooks/splat_island.ts`), and Zoom out,
  Zoom in and Reset view in its corner, unseen until the scene has drawn. The box is
  a labelled group, not a picture, so the buttons inside it stay reachable to a
  screen reader. Its look is `assets/css/components/splat_stage.css`.

  `gif/1` is Download GIF for one box, which its own `SplatGif` hook runs
  (`assets/js/hooks/splat_gif.ts`). A page offers it by placing one; a page that
  places none offers none.

  `meta/1`, `rarity/1` and `traits/1` show a numbered scene's facts
  (`AshTemplateWeb.Scenes`): its number and kind, its rarity score, and every trait it
  was dealt as a table. The Scenes page folds the table away under Traits; the Splats
  page shows it open. Each page places them in its own layout.
  """

  use Phoenix.Component

  alias Phoenix.LiveView.JS

  @moving "Drag, or use the arrow keys, to turn and tilt it. Pinch, or press plus and minus, to look closer, and 0 to go back to the start."

  attr :id, :string, required: true, doc: "the box's id; the GIF control names it"
  attr :scene, :string, required: true, doc: "the scene's name, which a saved GIF is named after"
  attr :label, :string, required: true, doc: "what the scene shows, in a sentence or two"
  attr :file, :string, required: true, doc: "the scene's baked file"
  attr :still, :string, required: true, doc: "the wide still, one pixel to an art pixel"

  attr :square, :string,
    default: nil,
    doc: "the square still, one pixel to an art pixel, for a box that turns square under 36rem"

  attr :class, :any, default: nil

  def stage(assigns) do
    assigns = assign(assigns, :moving, @moving)

    ~H"""
    <div
      id={@id}
      class={["splat-stage", @class]}
      tabindex="0"
      role="group"
      aria-label={"#{@label} #{@moving}"}
      data-splats-scene={@scene}
      data-splats-file={@file}
      phx-hook="SplatIsland"
      phx-mounted={JS.ignore_attributes(["data-splats-ready"])}
    >
      <picture>
        <source :if={@square} media="(max-width: 36rem)" srcset={@square} width="360" height="360" />
        <img class="splat-stage__still" src={@still} width="480" height="320" alt="" />
      </picture>
      <div id={"#{@id}-stage"} class="splat-stage__live" phx-update="ignore">
        <canvas data-splats-canvas></canvas>
      </div>
      <%!-- The SplatIsland hook finds these by data-splats-zoom and keeps their
      aria-disabled; the server sends them as the opening view has them. --%>
      <div class="splat-zoom">
        <.zoom_button box={@id} action="out" label="Zoom out" icon="minus" at_limit />
        <.zoom_button box={@id} action="in" label="Zoom in" icon="plus" />
        <.zoom_button box={@id} action="home" label="Reset view" icon="scan" at_limit />
      </div>
    </div>
    """
  end

  attr :box, :string, required: true
  attr :action, :string, required: true, values: ~w(in out home)
  attr :label, :string, required: true
  attr :icon, :string, required: true

  attr :at_limit, :boolean,
    default: false,
    doc: "true when the opening view leaves it nothing to do"

  defp zoom_button(assigns) do
    ~H"""
    <Regent.Primitives.button
      id={"#{@box}-zoom-#{@action}"}
      variant="secondary"
      arrow={false}
      class="splat-zoom__button"
      data-splats-zoom={@action}
      aria-label={@label}
      aria-disabled={to_string(@at_limit)}
      phx-mounted={JS.ignore_attributes(["aria-disabled"])}
    >
      <Regent.Icons.icon name={@icon} />
    </Regent.Primitives.button>
    """
  end

  attr :for, :string, required: true, doc: "the id of the box whose scene it saves"
  attr :class, :any, default: nil

  @doc """
  Download GIF for the box `for` names. The `SplatGif` hook keeps its state
  (`data-gif`: `making` or `failed`) and its words. Every word it can say shares one
  place, so it keeps the widest, and the line saying it failed keeps its place
  unseen, so nothing round it moves.
  """
  def gif(assigns) do
    ~H"""
    <div
      id={"#{@for}-gif"}
      class={["splat-gif", @class]}
      data-splats-box={@for}
      phx-hook="SplatGif"
      phx-mounted={JS.ignore_attributes(["data-gif"])}
    >
      <p class="splat-gif__failed">Could not make the GIF. Try again.</p>
      <Regent.Primitives.button
        id={"#{@for}-gif-button"}
        variant="secondary"
        arrow={false}
        class="splat-gif__button"
        phx-mounted={JS.ignore_attributes(["aria-disabled", "aria-busy"])}
      >
        <span class="splat-gif__words">
          <span class="splat-gif__idle">Download GIF</span>
          <span class="splat-gif__making">
            Making
            <Regent.Primitives.figure
              id={"#{@for}-gif-done"}
              value="0%"
              width={4}
              phx-update="ignore"
            />
          </span>
        </span>
      </Regent.Primitives.button>
      <span id={"#{@for}-gif-status"} class="visually-hidden" role="status" phx-update="ignore"></span>
    </div>
    """
  end

  attr :scene, :map, required: true, doc: "a numbered scene, as `AshTemplateWeb.Scenes` gives it"
  attr :class, :any, default: nil

  @doc "A numbered scene's number, and whether it is Action or Chill as a small tag."
  def meta(assigns) do
    ~H"""
    <p class={["splat-meta", @class]}>
      <span>Scene {@scene.number}</span>
      <span class="splat-meta__kind">{@scene.kind}</span>
    </p>
    """
  end

  attr :scene, :map, required: true, doc: "a numbered scene, as `AshTemplateWeb.Scenes` gives it"
  attr :class, :any, default: nil

  @doc "A numbered scene's rarity score."
  def rarity(assigns) do
    ~H"""
    <span class={["splat-rarity", @class]}>Rarity <b>{@scene.rarity}</b></span>
    """
  end

  attr :scene, :map, required: true, doc: "a numbered scene, as `AshTemplateWeb.Scenes` gives it"

  @doc """
  Every trait a numbered scene was dealt: category, trait, tier and share, in the order
  its trait list gives them. Wider than the narrowest phones, the table scrolls in its
  own box, which a keyboard can reach and a screen reader names.
  """
  def traits(assigns) do
    ~H"""
    <div class="splat-traits" tabindex="0" role="region" aria-label={"#{@scene.title} traits"}>
      <table>
        <thead>
          <tr>
            <th scope="col">Category</th>
            <th scope="col">Trait</th>
            <th scope="col">Tier</th>
            <th scope="col">Share</th>
          </tr>
        </thead>
        <tbody>
          <tr :for={trait <- @scene.traits}>
            <td>{trait.category}</td>
            <td>{trait.trait}</td>
            <td>{trait.tier}</td>
            <td>{trait.share}</td>
          </tr>
        </tbody>
      </table>
    </div>
    """
  end
end
