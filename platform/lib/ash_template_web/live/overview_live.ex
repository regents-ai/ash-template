defmodule AshTemplateWeb.OverviewLive do
  @moduledoc """
  The first page inside the shell. It renders for everyone; a signed-in person
  sees their own name and the places to go, an anonymous visitor sees the way in.
  Replace it with the first thing your customers should see once they are in.
  """

  use Phoenix.Component
  use AshTemplateWeb, :verified_routes

  import AshTemplateWeb.Components.PageHead

  alias AshTemplateWeb.RouteCatalog

  attr :account_control, AshTemplate.AccessContext.AccountControl, required: true
  attr :account, :map, default: nil

  def page(assigns) do
    assigns = assign(assigns, :places, places())

    ~H"""
    <section id="overview-page" class="overview-page">
      <.page_head id="overview-heading" title={title(@account, @account_control)} />

      <.signed_out :if={is_nil(@account)} id="overview-signed-out">
        Sign in to get started.
      </.signed_out>

      <nav class="overview-places" aria-label="Places">
        <.link :for={place <- @places} patch={place.path} class="overview-place">
          <span class="overview-place__title">{place.title}</span>
          <span class="overview-place__line">{place.line}</span>
        </.link>
      </nav>

      <nav class="overview-links" aria-label="For developers and agents">
        <a href="/docs">Docs</a>
        <a href="/agents.md">Agent guide</a>
        <a href="/openapi.json">API</a>
      </nav>
    </section>
    """
  end

  defp places do
    rooms = Enum.find(RouteCatalog.sections(), &(&1.id == :rooms)).path

    [
      %{path: ~p"/notes", title: "Notes", line: "Private notes, just for you"},
      %{path: rooms, title: "Rooms", line: "Talk with people and agents"},
      %{path: ~p"/chat", title: "Chat", line: "Ask the assistant"},
      %{path: ~p"/account/points", title: "Points", line: "Earned by you and your agents"},
      %{path: ~p"/account", title: "Agents", line: "Pair an agent with your account"}
    ]
  end

  defp title(nil, _account_control), do: "Welcome"
  defp title(_account, account_control), do: "Welcome, #{account_control.label}"
end
