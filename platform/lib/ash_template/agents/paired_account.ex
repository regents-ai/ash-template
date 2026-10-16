defmodule AshTemplate.Agents.PairedAccount do
  @moduledoc """
  How an agent's check-in (`GET /api/agents/v1/me`) names the account it is
  paired with, including its verified wallet fields. This callback runs after
  the shared signed check-in; it is not a passive identity probe.
  """

  alias AshTemplate.Accounts
  alias AshTemplate.Actors.System

  # Nil when this site has no account for the person; the check-in is then refused.
  def account(privy_user_id) do
    case Accounts.get_by_privy_did(privy_user_id, actor: %System{}) do
      {:ok, %{} = account} ->
        %{
          display_name: account.display_name,
          ens_name: account.ens_name,
          wallet_address: account.wallet_address,
          wallet_addresses: account.wallet_addresses || []
        }

      {:ok, nil} ->
        nil
    end
  end
end
