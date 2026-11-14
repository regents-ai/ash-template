defmodule AshTemplateWeb.AccountRoutes do
  @moduledoc """
  The Account pages, the same on every Regent site: Account, Agents, Points,
  Wallets and Connections, then Settings when the site has a Settings page of its
  own (`AshTemplateWeb.AccountSite.settings/0`). The router routes them with
  `account_routes/1`, and the route catalog and the page titles take them from
  `pages/0`, so a tab, its route and its title never disagree.

  Every site copies this file from ash-template unchanged (`scripts/drift.sh`
  compares it). A page only one site has belongs in that site's own menu, never
  under Account.
  """

  alias AshTemplateWeb.AccountSite

  @shared [
    %{
      action: :account,
      label: "Account",
      path: "/account",
      description: "Your profile and the session on this browser."
    },
    %{
      action: :account_agents,
      label: "Agents",
      path: "/account/agents",
      description: "The agents you paired, and pairing a new one."
    },
    %{
      action: :points,
      label: "Points",
      path: "/account/points",
      description: "Your points and activity."
    },
    %{
      action: :wallets,
      label: "Wallets",
      path: "/account/wallets",
      description: "The wallets your sign-in verified."
    },
    %{
      action: :connections,
      label: "Connections",
      path: "/account/connections",
      description: "The accounts you have connected, such as X, GitHub and Farcaster."
    }
  ]

  @settings %{
    action: :account_settings,
    label: "Settings",
    path: "/account/settings",
    description: "Your settings for this site."
  }

  @doc """
  The Account pages in tab order, each with its live action, its tab label (also
  its title), its path and its description. Settings comes last, and only when
  `site` has a Settings page.
  """
  def pages(site \\ AccountSite),
    do: if(site.settings(), do: @shared ++ [@settings], else: @shared)

  @doc """
  Routes every Account page to `shell`, a live action each, inside the site's
  signed-in live session.
  """
  defmacro account_routes(shell, site \\ AccountSite) do
    site = Macro.expand(site, __CALLER__)

    for page <- pages(site) do
      quote do
        live unquote(page.path), unquote(shell), unquote(page.action)
      end
    end
  end
end
