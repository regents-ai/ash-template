defmodule AshTemplate.Payments.ChainBuy.Quote do
  @moduledoc """
  Reads the item's price from the sale before the buy's transaction starts,
  so no chain call runs inside it. A buy is refused while buying is off, or
  in the sale's own words when the item cannot be bought now.
  """

  use Ash.Resource.Change

  alias AshTemplate.Payments.ChainBuy.Settings

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.before_transaction(changeset, fn
      %{valid?: true} = changeset -> priced(changeset)
      changeset -> changeset
    end)
  end

  defp priced(changeset) do
    with {:ok, sale} <- Settings.sale(),
         {:ok, _signer} <- Settings.signer(),
         {:ok, price} <- sale.price(Ash.Changeset.get_attribute(changeset, :item)) do
      Ash.Changeset.force_change_attributes(changeset, %{
        sale: price.sale,
        price_atomic: price.price_atomic
      })
    else
      :off -> refuse(changeset, "Buying is not open on this site.")
      {:error, words} -> refuse(changeset, words)
    end
  end

  defp refuse(changeset, words),
    do: Ash.Changeset.add_error(changeset, field: :item, message: words)
end
