defmodule AshTemplateWeb.DesignLive do
  @moduledoc """
  The Design page inside the shell: one card for each design page, in the order
  the Design sidebar lists them (`AshTemplateWeb.RouteCatalog.design_pages/0`).
  The pages themselves stand outside the shell, so each card opens a full page.
  """

  use Phoenix.Component

  import AshTemplateWeb.Components.PageHead

  alias AshTemplateWeb.RouteCatalog

  def page(assigns) do
    assigns = assign(assigns, :pages, RouteCatalog.design_pages())

    ~H"""
    <section id="design-page" class="overview-page">
      <.page_head id="design-heading" title="Design" />

      <nav class="design-places" aria-label="Design pages">
        <a :for={page <- @pages} href={page.path} class="overview-place">
          <span class="overview-place__title">{page.label}</span>
        </a>
      </nav>
    </section>
    """
  end
end
