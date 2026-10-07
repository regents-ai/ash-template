defmodule AshTemplate.Agents.PairedAccount do
  @moduledoc """
  How an agent's check-in (`GET /api/agents/v1/me`) names the account it is
  paired with, the way this site's pages name it.
  """

  alias AshTemplate.Accounts
  alias AshTemplate.Actors.System

  def account(privy_user_id) do
    account = Accounts.get_by_privy_did!(privy_user_id, actor: %System{})
    %{display_name: account.display_name, ens_name: account.ens_name}
  end
end
