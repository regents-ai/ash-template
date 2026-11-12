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
    "/animations/swarm-city" => "Agents flying over a city of thin lines",
    "/animations/datascape" => "An endless plane you fly over",
    "/animations/frosted-glass" => "A tree through frosted glass",
    "/animations/menu" => "A menu that grows from its button",
    "/animations/parts" => "Shared parts in motion",
    "/animations/value" => "A figure lit where you point",
    "/animations/ask" => "An answer drawn from blocks",
    "/animations/glow" => "A soft light that follows a status",
    "/animations/ink" => "Ink lines and a ruled horizon",
    "/animations/grain" => "Harbour water in fine grain",
    "/animations/cards" => "A moving picture on every card",
    "/animations/particles" => "Grains that take any shape",
    "/animations/cells" => "A meter of twinkling cells"
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
