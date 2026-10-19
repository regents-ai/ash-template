defmodule AshTemplateWeb.Components.SiteHeader do
  @moduledoc """
  The header of a public page, the same on every Regent site: the site's name
  and every Regents product under one Products menu. A mouse opens the menu by
  resting on it, a finger or a key with a press
  (`assets/js/hooks/products_menu.ts`). The footer below a public page is
  `AshTemplateWeb.Layouts.product_links/1`.
  """

  use Phoenix.Component
  use AshTemplateWeb, :verified_routes

  alias AshTemplateWeb.Components.Shell
  alias Phoenix.LiveView.JS

  attr :id, :string, required: true

  def header(assigns) do
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
            Products <.chevron />
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

  defp chevron(assigns) do
    ~H"""
    <svg class="site-header__chevron" viewBox="0 0 12 12" aria-hidden="true">
      <path d="M2.5 4.5 6 8l3.5-3.5" fill="none" stroke="currentColor" stroke-width="1.5" />
    </svg>
    """
  end
end
