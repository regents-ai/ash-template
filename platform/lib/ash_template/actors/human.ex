defmodule AshTemplate.Actors.Human do
  @moduledoc """
  A signed-in person: the account's id, every wallet it links, lowercased, and
  the name others see beside what they write: their display name, or their
  short wallet address when they have not set one.

  An agent whose own wallet signs in to the account is that account's owner, so
  its signed request is this actor too (`owner/2`), with `agent_id` naming the
  agent for its own profile. An agent a person paired acts as
  `AshTemplate.Actors.Agent`, which never grants this role.
  """
  @enforce_keys [:human_account_id]
  defstruct [
    :human_account_id,
    :privy_user_id,
    :name,
    :agent_id,
    :acting_agent_id,
    :pairing_id,
    wallet_addresses: [],
    role: :human
  ]

  def for_account(account) do
    %__MODULE__{
      human_account_id: account.id,
      privy_user_id: account.privy_user_id,
      name: name(account),
      wallet_addresses: wallets(account)
    }
  end

  @doc "The owner of `account`, acting through `agent`, the agent its sign-in wallet is."
  def owner(account, agent), do: %{for_account(account) | agent_id: agent.id}

  defp name(account),
    do: account.display_name || RegentFormat.short_address(account.wallet_address)

  defp wallets(account) do
    [account.wallet_address | List.wrap(account.wallet_addresses)]
    |> Enum.filter(&is_binary/1)
    |> Enum.map(&String.downcase/1)
    |> Enum.uniq()
  end
end
