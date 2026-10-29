defmodule AshTemplate.Actors.Human do
  @moduledoc """
  A signed-in person: the account's id, every wallet it links, lowercased, and
  how others see them beside what they write (`AshTemplate.PublicIdentity.author/1`).

  Agent delegation uses `AshTemplate.Actors.Agent`; it never grants this role.
  """
  alias AshTemplate.PublicIdentity

  @enforce_keys [:human_account_id]
  defstruct [
    :human_account_id,
    :author,
    :acting_agent_id,
    :pairing_id,
    wallet_addresses: [],
    role: :human
  ]

  def for_account(account) do
    %__MODULE__{
      human_account_id: account.id,
      author: PublicIdentity.author(account),
      wallet_addresses: wallets(account)
    }
  end

  defp wallets(account) do
    [account.wallet_address | List.wrap(account.wallet_addresses)]
    |> Enum.filter(&is_binary/1)
    |> Enum.map(&String.downcase/1)
    |> Enum.uniq()
  end
end
