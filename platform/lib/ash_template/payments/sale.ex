defmodule AshTemplate.Payments.Sale do
  @moduledoc """
  What a site sells on the chain through its buying wallet: a module named as
  `sale` in `config :ash_template, AshTemplate.Payments.ChainBuy`.

  `price/1` reads the sale contract and the item's price at the latest block,
  or answers in a few words why it cannot be bought now (sold out, closed).
  `call/3` builds the sale's own call for that item, sent to `receiver`, at
  most `price_atomic`: the call the wallet sends right after approving that
  price.
  """

  @type item :: String.t()

  @callback price(item()) ::
              {:ok, %{sale: String.t(), price_atomic: pos_integer()}} | {:error, String.t()}

  @callback call(item(), receiver :: String.t(), price_atomic :: pos_integer()) ::
              %{data: binary()}
end
