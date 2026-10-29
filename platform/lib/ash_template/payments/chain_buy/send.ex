defmodule AshTemplate.Payments.ChainBuy.Send do
  @moduledoc """
  Sends the buy before the update's transaction starts. It first commits when
  the send began (`:begin`), so a buy that stops mid-send is told apart from
  one still waiting its turn. The wallet then approves exactly the price to
  the sale and sends the sale's call for the item, addressed to the buyer's
  wallet. The update commits what came back, and
  `Follow` queues what happens next.
  """

  use Ash.Resource.Change

  alias AshTemplate.Payments.ChainBuy.Settings

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.before_transaction(changeset, fn changeset ->
      buy = begin(changeset.data)
      Ash.Changeset.force_change_attributes(changeset, buy |> send() |> outcome())
    end)
  end

  # Runs inside the send job, which the trigger already authorized for this
  # one buy; marking when its send began is part of that same job.
  defp begin(buy), do: Ash.update!(buy, %{}, action: :begin, authorize?: false)

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
