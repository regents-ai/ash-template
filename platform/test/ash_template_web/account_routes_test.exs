defmodule AshTemplateWeb.AccountRoutesTest do
  # Account is the same on every Regent site, with one page a site may add for its
  # own settings. Its tabs, routes and titles come from one list, so a tab never
  # leads nowhere and a route is never without its tab. The template has no
  # Settings page; a site that has one is stood in for by `WithSettings`, routed by
  # a router of its own as a site's router routes Account.
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias AshTemplateWeb.{AccountLive, AccountRoutes, PublicDocuments, RouteCatalog, Router}

  defmodule WithSettings do
    use Phoenix.Component

    def settings, do: &page/1

    def page(assigns), do: ~H|<form id="site-settings-form" data-account={@account.id}></form>|
  end

  defmodule WithSettingsRouter do
    use Phoenix.Router
    import Phoenix.LiveView.Router
    import AshTemplateWeb.AccountRoutes, only: [account_routes: 2]

    scope "/", AshTemplateWeb do
      live_session :account do
        account_routes(ShellLive, WithSettings)
      end
    end
  end

  test "every Account tab leads to its own page, and every Account page is a tab" do
    tabs = RouteCatalog.fetch!(:account).tabs

    for tab <- tabs,
        do: assert(shell_page(Router, tab.path) == tab.route_id, tab.path)

    assert account_paths(Router) == tabs |> Enum.map(& &1.path) |> Enum.sort()

    for tab <- tabs,
        do: assert(PublicDocuments.page(tab.path)[:page_title] == tab.label, tab.path)
  end

  test "the template has no Settings page: no tab, no route" do
    refute Enum.any?(AccountRoutes.pages(), &(&1.action == :account_settings))
    refute Enum.any?(RouteCatalog.fetch!(:account).tabs, &(&1.route_id == :account_settings))
    assert Phoenix.Router.route_info(Router, "GET", "/account/settings", "localhost") == :error
  end

  test "a site with a Settings page gets its tab last, and its route" do
    pages = AccountRoutes.pages(WithSettings)

    assert List.last(pages).action == :account_settings
    assert Enum.drop(pages, -1) == AccountRoutes.pages()
    assert shell_page(WithSettingsRouter, "/account/settings") == :account_settings
    assert account_paths(WithSettingsRouter) == pages |> Enum.map(& &1.path) |> Enum.sort()
  end

  test "the site's Settings body is drawn once signed in, never before" do
    page = WithSettings.settings()

    signed_in =
      render_component(&AccountLive.settings/1, page: page, lease: %{}, account: %{id: "a1"})
      |> LazyHTML.from_fragment()

    assert signed_in |> LazyHTML.query("#site-settings-form") |> LazyHTML.attribute("data-account") ==
             ["a1"]

    signed_out =
      render_component(&AccountLive.settings/1, page: page, lease: %{}, account: nil)
      |> LazyHTML.from_fragment()

    assert signed_out |> LazyHTML.query("#site-settings-form") |> Enum.count() == 0
    assert signed_out |> LazyHTML.query("#account-settings-page-signed-out") |> Enum.count() == 1
  end

  defp shell_page(router, path) do
    %{phoenix_live_view: {AshTemplateWeb.ShellLive, action, _opts, _session}} =
      Phoenix.Router.route_info(router, "GET", path, "localhost")

    action
  end

  defp account_paths(router) do
    paths = for %{path: "/account" <> _ = path} <- router.__routes__(), do: path
    Enum.sort(paths)
  end
end
