defmodule AshTemplate.Credits do
  @moduledoc """
  This site's part in Regent Credits (`RegentCredits`): the name it acts under
  and the actors it passes. The library keeps the balance; the site says who
  is asking, from what its own sign-in verified.
  """

  alias RegentCredits.Actor

  @site "template"

  @doc "The name this site places holds and attaches wallets under."
  def site, do: @site

  @doc "The signed-in account, with the wallets its sign-in verified."
  def person(account), do: Actor.person(account.privy_user_id, account.wallet_addresses, @site)

  @doc "The site's own server code."
  def site_actor, do: Actor.site(@site)
end
