defmodule AshTemplateWeb.AccountSite do
  @moduledoc """
  This site's own parts of /account, shown before the shared ones
  (`AshTemplateWeb.AccountLive`): its own sections at the top of the Account tab,
  and its own tabs before Account. It is the one file of the Account pages a site
  writes for itself; every other one is copied from ash-template unchanged. The
  template has none of its own.

  A section is a function component given `account` (the signed-in account),
  `lease` (its session lease, for a live component) and `account_control` (the
  name and picture the header shows). A tab is a `RouteTarget` whose route the
  site adds beside `account_routes/1`.
  """

  @doc "This site's own sections, in order."
  def sections, do: []

  @doc "This site's own tabs, in order."
  def tabs, do: []
end
