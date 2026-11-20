defmodule AshTemplateWeb.ScenesLabLive do
  @moduledoc """
  Scenes: every numbered scene (`AshTemplateWeb.Scenes`), each on a card with its
  own turning stage (`AshTemplateWeb.Components.SplatStage.stage/1`), which turns,
  tilts and zooms as the Splats page's does. Under each stage are the scene's title,
  its number and whether it is Action or Chill, Download GIF, five of its traits as
  tags (World, Ground, Resident, Landmark and Hour), every trait folded away under
  Traits with the rarity score (the number, kind, rarity and trait table are the
  stage's shared parts, which the Splats page shows open), and links that open the scene's own page and its trait
  file in a new tab. One column on a phone, two on a wide screen. Each stage draws only
  while it is on screen. Nothing here reads or changes anything outside the page.
  """

  use AshTemplateWeb, :live_view

  alias AshTemplateWeb.Components.SplatStage
  alias AshTemplateWeb.{PublicDocuments, Scenes}

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(PublicDocuments.page(~p"/animations/scenes"))
     |> assign(scenes: Scenes.all())}
  end

  attr :scene, :map, required: true

  defp card(assigns) do
    assigns = assign(assigns, :id, "scene-#{assigns.scene.number}")

    ~H"""
    <article class="scenes-lab__card" aria-labelledby={"#{@id}-title"}>
      <SplatStage.stage
        id={@id}
        scene={@scene.name}
        label={"#{@scene.title}. #{@scene.description}"}
        file={Scenes.file(@scene)}
        still={Scenes.still(@scene, :wide)}
      />
      <div class="scenes-lab__body">
        <div class="scenes-lab__head">
          <h2 id={"#{@id}-title"}>{@scene.title}</h2>
          <SplatStage.meta scene={@scene} class="scenes-lab__meta" />
          <SplatStage.gif for={@id} class="scenes-lab__gif" />
        </div>
        <ul class="scenes-lab__tags" aria-label="Highlights">
          <li :for={trait <- Scenes.headline(@scene)}>
            <span>{trait.category}</span> {trait.trait}
          </li>
        </ul>
        <details
          id={"#{@id}-traits"}
          class="scenes-lab__traits"
          phx-mounted={JS.ignore_attributes(["open"])}
        >
          <summary>
            Traits <Regent.Icons.icon name="chevron-down" />
            <SplatStage.rarity scene={@scene} class="scenes-lab__rarity" />
          </summary>
          <SplatStage.traits scene={@scene} />
        </details>
        <p class="splat-links scenes-lab__links">
          <a href={~p"/scenes/#{@scene.number}"} target="_blank" rel="noopener">
            Full view <Regent.Icons.icon name="arrow-up-right" />
          </a>
          <a href={~p"/scenes/#{@scene.number}/metadata.json"} target="_blank" rel="noopener">
            Metadata <Regent.Icons.icon name="arrow-up-right" />
          </a>
        </p>
      </div>
    </article>
    """
  end

  @impl true
  def render(assigns) do
    ~H"""
    <main id="scenes-lab" class="motion-lab motion-lab--scenes">
      <header class="motion-lab__head">
        <p class="motion-lab__kicker">
          <a href={~p"/"}>Ash Template</a>
          / <a href={~p"/animations"}>Motion lab</a>
          / <.link navigate={~p"/animations/splats"}>Splats</.link>
          / Scenes
        </p>
        <h1>Scenes</h1>
        <p class="motion-lab__lede">
          Small worlds and their traits. Drag one to turn it, pinch to look closer, double-click to start again.
        </p>
      </header>
      <div class="scenes-lab">
        <.card :for={scene <- @scenes} scene={scene} />
      </div>
    </main>
    """
  end
end
