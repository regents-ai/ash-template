defmodule AshTemplateWeb.AccountSite do
  @moduledoc """
  This site's own parts of Account, and the one Account file a site writes for
  itself: every other one is copied from ash-template unchanged
  (`AshTemplateWeb.AccountRoutes`). A page only this site has belongs in the
  site's own menu, never under Account.

  - Settings: the one Account page that is only this site's, holding this site's
    settings and nothing else (`settings/0`). The template has none, so its Account
    has no Settings tab and `/account/settings` is not a page.
  - The Agents page's part: something beside each paired agent in the list
    (`AshTemplateWeb.AgentsPanel`), and a line under the pairing box once an agent
    has paired (`AshTemplateWeb.PairingBox`). The template has none, so it reads
    nothing and both parts draw nothing. A site with its own, such as the Keys
    Keyfleet's agents hold a shard of, keeps it in its copy of this module, and the
    Agents page, its list and its pairing box stay the template's.

  A site whose Agents part changes while the page is open sends the agents list
  `site_changed: true` (`Phoenix.LiveView.send_update/3`), and it reads again.
  """
  use AshTemplateWeb, :html

  @doc """
  This site's Settings page, or nil when it has none. A site with one answers its
  body as a function component (`&settings_page/1`, defined here), given
  `account` (the signed-in account) and `lease` (its session lease, for a live
  component). Account draws it under the Settings title, once signed in. Its
  events reach the site's shell; a body with a form of its own renders a live
  component defined here.
  """
  def settings, do: nil

  @doc """
  What this site shows for each of the account's agents, by the agent's wallet.
  A wallet with nothing to show is left out, and one whose part couldn't be read
  is `:unavailable`, so its agent says so.
  """
  def read(_account, _wallets), do: %{}

  attr :id, :string, required: true
  attr :part, :any, required: true, doc: "the agent's entry from `read/2`, or nil"

  @doc "Beside an agent in the list, before its own actions."
  def agent(assigns), do: ~H""

  attr :id, :string, required: true
  attr :agent, :map, required: true, doc: "the agent that has just paired"
  attr :part, :any, required: true, doc: "its entry from `read/2`, or nil"

  @doc "Under the pairing box once the agent has paired."
  def paired(assigns), do: ~H""
end
