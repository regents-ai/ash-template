defmodule AshTemplate.Agents.PairedAccount do
  @moduledoc """
  How an agent's check-in (`GET /api/agents/v1/me`) names the account it is
  paired with, including its verified wallet fields. This callback runs after
  the shared signed check-in; it is not a passive identity probe.
  """

  alias AshTemplate.Agents.ForPerson

  # Nil while the agent does not act for its person (`ForPerson.account/1`),
  # and when the account could not be read; the check-in then answers as for a
  # person not here, which asks for their sign-in.
  def account(privy_user_id) do
    case ForPerson.account(privy_user_id) do
      {:ok, account} ->
        %{
          display_name: account.display_name,
          ens_name: account.ens_name,
          wallet_address: account.wallet_address,
          wallet_addresses: account.wallet_addresses
        }

      {:error, _not_here_or_unread} ->
        nil
    end
  end
end
