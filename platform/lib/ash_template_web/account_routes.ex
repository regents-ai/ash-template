defmodule AshTemplateWeb.AccountRoutes do
  @moduledoc """
  The routes of /account, the same on every Regent site: Account, Points,
  Credits, Wallets and Connections, each a tab of the site's shell LiveView
  (`AshTemplateWeb.AccountLive`). A site's own tabs (`AshTemplateWeb.AccountSite`)
  are routed beside these by the site.

  Copied from ash-template unchanged; `scripts/drift.sh --account` names any site
  whose copy differs.
  """

  @doc "Routes the five tabs to `shell`, inside the site's signed-in live session."
  defmacro account_routes(shell) do
    quote do
      live "/account", unquote(shell), :account
      live "/account/points", unquote(shell), :points
      live "/account/credits", unquote(shell), :credits
      live "/account/wallets", unquote(shell), :wallets
      live "/account/connections", unquote(shell), :connections
    end
  end
end
