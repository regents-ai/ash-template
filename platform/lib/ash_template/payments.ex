defmodule AshTemplate.Payments do
  @moduledoc """
  Purchases on the chain the site's buying wallet makes for a person who pays
  in purchased Credits (`AshTemplate.Payments.ChainBuy`).
  """

  use Ash.Domain

  resources do
    resource AshTemplate.Payments.ChainBuy do
      define :buy, args: [:item, :receiver]
      define :my_buys, action: :read

      # Only `AshTemplate.Payments.ChainBuy.CheckReceipt` calls this, with what
      # the chain said of a call that may still have landed.
      define :settle_buy,
        action: :settle,
        args: [:outcome],
        default_options: [authorize?: false]
    end
  end
end
