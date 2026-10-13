defmodule AshTemplateWeb.CrownLive do
  @moduledoc """
  The glass crown, shown by itself: the example a site copies when it wants the
  crown on a page of its own. Nothing here reads or changes anything outside
  the page.
  """

  use AshTemplateWeb, :live_view

  alias AshTemplateWeb.Components.Crown

  # The beam colours on offer: the look's name in `assets/js/crown_looks.ts`,
  # the word the visitor sees for it and the colour of its swatch.
  @looks [
    %{name: "white", label: "White", swatch: "#FFFFFF"},
    %{name: "orange", label: "Orange", swatch: "#FF5B19"},
    %{name: "blue", label: "Blue", swatch: "#AECACD"},
    %{name: "sand", label: "Sand", swatch: "#B9B7A6"}
  ]
  @look_names Enum.map(@looks, & &1.name)

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(AshTemplateWeb.PublicDocuments.page("/animations/crown"))
     |> assign(looks: @looks, look: "white")}
  end

  @impl true
  def handle_event("look", %{"look" => look}, socket) when look in @look_names do
    {:noreply, assign(socket, look: look)}
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
          Thirteen glass cubes and three beams of light. Move the pointer to swing the light.
        </p>
      </header>
      <div class="crown-stage">
        <Crown.crown id="crown" look={@look} />
      </div>
      <div class="crown-looks" role="group" aria-label="Light colour">
        <button
          :for={look <- @looks}
          type="button"
          phx-click="look"
          phx-value-look={look.name}
          aria-pressed={to_string(@look == look.name)}
          style={"--crown-swatch: #{look.swatch}"}
        >
          {look.label}
        </button>
      </div>
    </main>
    """
  end
end
