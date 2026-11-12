defmodule AshTemplateWeb.FrostedGlassLive do
  @moduledoc """
  The frosted glass: one large branching tree seen through a leaning pane of
  frosted glass, with a lamp in front of it. At the top of the page the
  visitor is among the tree's boughs; scrolling down steps back to the whole
  tree, and on back until it stands in a forest.

  The glass comes in several looks, each its own surface and light; `?look=`
  names one, and the first needs no name. Changing the look repaints the glass
  where it stands. Nothing here reads or changes anything outside the page.
  """

  use AshTemplateWeb, :live_view

  alias AshTemplateWeb.{NotFoundError, PublicDocuments}

  @looks [
    %{id: "lifelike", name: "Lifelike"},
    %{id: "reeded", name: "Reeded"},
    %{id: "blocks", name: "Blocks"},
    %{id: "mist", name: "Mist"},
    %{id: "night", name: "Night"},
    %{id: "ember", name: "Ember"}
  ]
  @looks_by_id Map.new(@looks, &{&1.id, &1})
  @first_look hd(@looks)

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, looks: @looks)}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply,
     socket
     |> assign(PublicDocuments.page(glass_path(@first_look)))
     |> assign(look: look!(params["look"]))}
  end

  # The look an address names, or the first for none; a look that does not exist is not found.
  defp look!(nil), do: @first_look
  defp look!(id), do: Map.get(@looks_by_id, id) || raise(NotFoundError)

  defp glass_path(@first_look), do: ~p"/animations/frosted-glass"
  defp glass_path(look), do: ~p"/animations/frosted-glass?#{[look: look.id]}"

  defp lede(%{id: "mist"}), do: "Wipe the glass, then scroll down."
  defp lede(_look), do: "Scroll down to step back from the tree."

  @impl true
  def render(assigns) do
    ~H"""
    <main id="frosted-glass-lab" class="motion-lab motion-lab--glass">
      <header class="motion-lab__head">
        <p class="motion-lab__kicker">
          <a href={~p"/"}>Ash Template</a> / <a href={~p"/animations"}>Motion lab</a> / Frosted Glass
        </p>
        <h1>Frosted Glass</h1>
        <p class="motion-lab__lede">{lede(@look)}</p>
      </header>
      <nav class="flair-tabs" aria-label="Looks">
        <.link
          :for={look <- @looks}
          patch={glass_path(look)}
          aria-current={look == @look && "page"}
        >
          {look.name}
        </.link>
      </nav>
      <div
        id="frosted-glass"
        class="frosted-glass"
        phx-hook="FrostedGlass"
        phx-mounted={JS.ignore_attributes(["data-glass-ready"])}
        data-glass-look={@look.id}
        role="img"
        aria-label="Frosted glass"
      >
        <div class="frosted-glass__stage" data-glass-stage>
          <img
            class="frosted-glass__still"
            src={~p"/images/animations/frosted-glass/#{@look.id <> ".webp"}"}
            width="1280"
            height="800"
            alt=""
          />
          <div id="frosted-glass-stage" class="frosted-glass__canvas" phx-update="ignore">
            <canvas id="frosted-glass-canvas" data-glass-canvas></canvas>
          </div>
        </div>
      </div>
    </main>
    """
  end
end
