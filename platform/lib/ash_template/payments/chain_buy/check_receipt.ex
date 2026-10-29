defmodule AshTemplate.Payments.ChainBuy.CheckReceipt do
  @moduledoc """
  Reads the receipt of a buy's call that may still have landed, every ten
  seconds for up to an hour, one job per buy. The chain's answer settles the
  buy: charged if the call went through, given back if the sale refused it.
  A call the chain still has not answered stays `:unknown`, its Credits
  held, for a person to look up.
  """

  use Oban.Worker,
    queue: :outside_calls,
    unique: [keys: [:id], period: :infinity, states: :incomplete]

  alias AshTemplate.Payments
  alias AshTemplate.Payments.ChainBuy
  alias AshTemplate.Payments.ChainBuy.Settings

  @wait_seconds 10
  @tries 360

  @impl true
  def perform(%Oban.Job{args: %{"id" => id}, meta: meta}) do
    # Runs in the background job with no person behind it; the job names the
    # one buy it settles, so reading it is not a choice made by anyone.
    buy = Ash.get!(ChainBuy, id, authorize?: false)
    tries = Map.get(meta, "snoozed", 0)

    case read(buy) do
      :settled -> :ok
      :not_yet when tries < @tries -> {:snooze, @wait_seconds}
      :not_yet -> :ok
      outcome -> with {:ok, _buy} <- Payments.settle_buy(buy, outcome), do: :ok
    end
  end

  defp read(%{state: :unknown, call_hash: call}) do
    case Settings.signer() do
      {:ok, signer} -> Settings.wallet().status(call, signer.rpc_url)
      :off -> :not_yet
    end
  end

  defp read(_settled), do: :settled
end
