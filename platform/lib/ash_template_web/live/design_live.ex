defmodule AshTemplateWeb.DesignLive do
  @moduledoc """
  The Design page inside the shell: one card for each design page, in the order
  the Design sidebar lists them (`AshTemplateWeb.RouteCatalog.design_pages/0`).
  The pages themselves stand outside the shell, so each card opens a full page.
  """

  use Phoenix.Component

  import AshTemplateWeb.Components.PageHead

  alias AshTemplateWeb.RouteCatalog

  @lines %{
    "/showcase" => "Every shared piece, light and dark",
    "/animations" => "Every motion, side by side",
    "/animations/cube" => "A room behind every side",
    "/animations/twin-cube" => "One for people, one for agents",
    "/animations/foil" => "A card for each site",
    "/animations/buttons" => "Each site's main button, in motion",
    "/animations/crown" => "Glass cubes that follow you",
    "/animations/keyfleet" => "A fleet's front door, in motion",
    "/animations/header-footer" => "Every product under one menu",
    "/animations/harbour" => "Ships that sail to their last action",
    "/animations/wonders" => "Ten pictures that answer your hand",
    "/animations/swarm-city" => "Agents flying over a city of thin lines"
  }

  def page(assigns) do
    assigns =
      assign(
        assigns,
        :pages,
        Enum.map(
          RouteCatalog.design_pages(),
          &%{path: &1.path, title: &1.label, line: @lines[&1.path]}
        )
      )

    ~H"""
    <section id="design-page" class="overview-page">
      <.page_head id="design-heading" title="Design" />

      <nav class="design-places" aria-label="Design pages">
        <a :for={page <- @pages} href={page.path} class="overview-place">
          <span class="overview-place__title">{page.title}</span>
          <span class="overview-place__line">{page.line}</span>
        </a>
      </nav>
    </section>
    """
  end
end
