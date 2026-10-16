defmodule AshTemplateWeb.HeaderFooterLive do
  @moduledoc """
  The header and footer of every public page, on a short page and on a long
  one: on the short page the footer rests at the foot of the screen, on the
  long one it follows the page. The footer is the page's own
  (`AshTemplateWeb.Layouts.product_links/1`, drawn by the root layout). Nothing
  here reads or changes anything outside the page.
  """

  use AshTemplateWeb, :live_view

  alias AshTemplateWeb.Components.SiteHeader
  alias AshTemplateWeb.WorldCubeLive

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, AshTemplateWeb.PublicDocuments.page("/animations/header-footer"))}
  end

  @impl true
  def handle_params(_params, _uri, socket),
    do: {:noreply, assign(socket, :worlds, worlds(socket.assigns.live_action))}

  @impl true
  def render(assigns) do
    ~H"""
    <div class="hf-page">
      <SiteHeader.header id="site-header" />
      <main id="header-footer-lab" class="motion-lab">
        <header class="motion-lab__head">
          <p class="motion-lab__kicker">
            <a href={~p"/"}>Ash Template</a>
            / <a href={~p"/animations"}>Motion lab</a>
            / Header and footer
          </p>
          <h1>Header and footer</h1>
          <p class="motion-lab__lede">
            Rest on Products, or tap it on a phone. On a short page the footer stays at the foot of
            the screen; on a long one it follows the page.
          </p>
        </header>

        <nav class="hf-lab__choice" aria-label="Page length">
          <.link patch={~p"/animations/header-footer"} aria-current={@live_action == :short && "page"}>
            Short page
          </.link>
          <.link
            patch={~p"/animations/header-footer/long"}
            aria-current={@live_action == :long && "page"}
          >
            Long page
          </.link>
        </nav>

        <section
          :for={world <- @worlds}
          class="hf-lab__world"
          aria-labelledby={"hf-world-#{world.face}"}
        >
          <h2 id={"hf-world-#{world.face}"}>{world.name}</h2>
          <p class="hf-lab__line">{world.line}</p>
          <dl class="hf-lab__facts">
            <div :for={card <- world.cards}>
              <dt>{card.title}</dt>
              <dd>{card.copy}</dd>
            </div>
          </dl>
        </section>
      </main>
    </div>
    """
  end

  # The long page reads the world cube's rooms for the products, each card a
  # title and a line. The room of posts on X has no titles, so it is left out.
  defp worlds(:short), do: []

  defp worlds(:long),
    do:
      Enum.filter(WorldCubeLive.worlds(), fn world ->
        Enum.all?(world.cards, &is_map_key(&1, :title))
      end)
end
