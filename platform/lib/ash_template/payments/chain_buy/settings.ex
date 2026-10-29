defmodule AshTemplate.Payments.ChainBuy.Settings do
  @moduledoc """
  The buying wallet's settings, from `config :ash_template,
  AshTemplate.Payments.ChainBuy`: the sale a site sells through it, the
  wallet module that sends, the day's limit in USDC millionths, and the
  wallet's key and Base endpoint, which come from the server's secrets.
  Buying is off while the site names no sale or the key or endpoint is
  missing.
  """

  alias AshTemplate.Payments.ChainBuy

  @doc "The site's sale module, or `:off` while it names none."
  def sale do
    case setting(:sale) do
      nil -> :off
      sale -> {:ok, sale}
    end
  end

  @doc "The module that sends a buy and reads a call's receipt."
  def wallet, do: setting(:wallet)

  @doc "How much the wallet may buy in one UTC day, in USDC millionths."
  def daily_limit_atomic, do: setting(:daily_limit_atomic)

  @doc "The wallet that signs and the endpoint it sends through, or `:off` while either is missing."
  def signer do
    with key when key not in [nil, ""] <- setting(:private_key),
         rpc_url when rpc_url not in [nil, ""] <- setting(:rpc_url),
         {:ok, [address]} <- Ethers.Signer.Local.accounts(private_key: key) do
      {:ok, %{address: address, private_key: key, rpc_url: rpc_url}}
    else
      _missing -> :off
    end
  end

  defp setting(key), do: :ash_template |> Application.fetch_env!(ChainBuy) |> Keyword.get(key)
end
