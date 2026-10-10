defmodule AshTemplateWeb.Components.InformationNavigation do
  @moduledoc "Persistent navigation shared by the public information and legal pages."
  use AshTemplateWeb, :html

  @pages [
    {"Docs", "/docs"},
    {"Skills", "/skills"},
    {"What's new", "/changelog"},
    {"About", "/about"},
    {"Contact", "/contact"},
    {"Privacy", "/privacy"},
    {"Terms", "/terms"}
  ]

  attr(:current_path, :string, required: true)

  def header(assigns) do
    pages =
      Enum.reject(@pages, fn {_, path} ->
        path == "/skills" and !AshTemplateWeb.Showcase.linked?()
      end)

    assigns = assign(assigns, :pages, pages)

    ~H"""
    <header class="legal-header">
      <a href={~p"/"} class="legal-home">Ash Template</a>
      <nav class="legal-nav" aria-label="Information">
        <a
          :for={{label, path} <- @pages}
          href={path}
          aria-current={if @current_path == path, do: "page"}
        >
          {label}
        </a>
      </nav>
    </header>
    """
  end
end
