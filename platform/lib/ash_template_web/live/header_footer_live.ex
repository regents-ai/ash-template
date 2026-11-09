defmodule AshTemplateWeb.HeaderFooterLive do
  @moduledoc """
  The header and footer of every public page, on a short page and on a long
  one: on the short page the footer rests at the foot of the screen, on the
  long one it follows the page. The footer is the page's own
  (`AshTemplateWeb.Layouts.product_links/1`, drawn by the root layout). Nothing
  here reads or changes anything outside the page.
  """

  use AshTemplateWeb, :live_view

  alias AshTemplateWeb.Components.Shell
  alias AshTemplateWeb.HomeLive

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
      <.site_header id="site-header" />
      <main id="header-footer-lab" class="motion-lab">
        <header class="motion-lab__head">
          <p class="motion-lab__kicker">
            <a href={~p"/"}>Ash Template</a> / <a href={~p"/animations"}>Motion lab</a> / Navigation
          </p>
          <h1>Navigation</h1>
          <p class="motion-lab__lede">
            Rest on Products, or tap it. The footer keeps to the foot of the screen.
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
      Enum.filter(HomeLive.worlds(), fn world ->
        Enum.all?(world.cards, &is_map_key(&1, :title))
      end)

  # The header of a public page, the same on every Regent site: the site's name
  # and every Regents product under one Products menu. A mouse opens the menu by
  # resting on it, a finger or a key with a press
  # (`assets/js/hooks/products_menu.ts`). The footer below a public page is
  # `AshTemplateWeb.Layouts.product_links/1`.
  attr :id, :string, required: true

  defp site_header(assigns) do
    assigns = assign(assigns, :products, Shell.regents_products())

    ~H"""
    <header id={@id} class="site-header">
      <a class="site-header__brand" href={~p"/"}>
        <span class="shell-apps__tile" data-tone="protocol"><Shell.crown /></span>
        <span class="site-header__name">Ash Template</span>
      </a>
      <nav class="site-header__nav" aria-label="Ash Template">
        <details
          id={"#{@id}-products"}
          class="site-products"
          phx-hook="ProductsMenu"
          phx-mounted={JS.ignore_attributes(["open", "data-settled"])}
        >
          <summary class="site-header__link">
            Products <Regent.Icons.icon name="chevron-down" class="site-header__chevron" />
          </summary>
          <div class="site-products__panel" data-panel="menu">
            <ul class="site-products__list">
              <li :for={product <- @products}>
                <a class="site-products__item" href={product.url} target="_blank" rel="noopener">
                  <span class="shell-apps__tile" data-tone={product.tone}><Shell.crown /></span>
                  <span>{product.name}</span>
                </a>
              </li>
            </ul>
          </div>
        </details>
        <a class="site-header__link" href={~p"/docs"}>Docs</a>
      </nav>
    </header>
    """
  end
end
