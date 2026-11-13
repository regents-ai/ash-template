defmodule AshTemplate.Agents.PairedAccount do
  @moduledoc """
  How an agent's check-in (`GET /api/agents/v1/me`) names the account it is
  paired with, including its verified wallet fields. This callback runs after
  the shared signed check-in; it is not a passive identity probe.
  """

  alias AshTemplate.Accounts
  alias AshTemplate.Accounts.VerifiedSession
  alias AshTemplate.Actors.System

  # Nil until the person first signs in here, and after a sign-in with no linked
  # wallet, as for the agent's signed requests (`AshTemplateWeb.Plugs.AgentWallet`);
  # the check-in then asks for that sign-in.
  def account(privy_user_id) do
    {:ok, account} = Accounts.get_by_privy_did(privy_user_id, actor: %System{})

    if VerifiedSession.current?(account) do
      %{
        display_name: account.display_name,
        ens_name: account.ens_name,
        wallet_address: account.wallet_address,
        wallet_addresses: account.wallet_addresses
      }
    end
  end
end
