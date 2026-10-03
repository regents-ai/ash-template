defmodule AshTemplate.Actors.Human do
  @moduledoc """
  A signed-in person: the account's id, every wallet it links, lowercased, and
  the name others see beside what they write: their display name, or their
  short wallet address when they have not set one.
  """
  @enforce_keys [:human_account_id]
  defstruct [:human_account_id, :name, wallet_addresses: [], role: :human]

  def for_account(account) do
    %__MODULE__{
      human_account_id: account.id,
      name: account.display_name || RegentFormat.short_address(account.wallet_address),
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
