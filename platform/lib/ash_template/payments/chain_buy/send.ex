defmodule AshTemplate.Payments.ChainBuy.Send do
  @moduledoc """
  Sends the buy before the update's transaction starts: the wallet approves
  exactly the price to the sale, then sends the sale's call for the item,
  addressed to the buyer's wallet. The update commits what came back, and
  `Follow` queues what happens next.
  """

  use Ash.Resource.Change

  alias AshTemplate.Payments.ChainBuy.Settings

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.before_transaction(changeset, fn changeset ->
      Ash.Changeset.force_change_attributes(changeset, changeset.data |> send() |> outcome())
    end)
  end

  defp send(buy) do
    with {:ok, sale} <- Settings.sale(),
         {:ok, signer} <- Settings.signer() do
      Settings.wallet().buy(
        %{
          sale: buy.sale,
          price_atomic: buy.price_atomic,
          call: sale.call(buy.item, buy.receiver, buy.price_atomic)
        },
        signer
      )
    end
  end

  defp outcome({:ok, sent}),
    do: %{state: :bought, approval_hash: sent.approval, call_hash: sent.call}

  defp outcome({:error, {:approval_failed, approval}}),
    do: %{state: :failed, approval_hash: approval, failure: "The approval did not go through."}

  defp outcome({:error, {:call_reverted, sent}}),
    do: %{
      state: :failed,
      approval_hash: sent.approval,
      call_hash: sent.call,
      failure: "The sale refused the purchase."
    }

  defp outcome({:error, {:call_unknown, sent}}),
    do: %{state: :unknown, approval_hash: sent.approval, call_hash: sent.call}

  defp outcome(:off),
    do: %{state: :failed, failure: "Buying was turned off before this buy was sent."}
end
