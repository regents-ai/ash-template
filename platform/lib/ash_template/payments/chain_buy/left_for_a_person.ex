defmodule AshTemplate.Payments.ChainBuy.LeftForAPerson do
  @moduledoc """
  Logs one line for a buy whose Credits stay held until a person looks the
  wallet up on the chain, so the site's watcher sees it. The line names the
  buy and its state, never an address.
  """

  use Ash.Resource.Change

  require Logger

  @impl true
  def change(changeset, _opts, _context),
    do: Ash.Changeset.after_action(changeset, fn _changeset, buy -> {:ok, log(buy)} end)

  @doc "Logs the buy as left for a person; returns it."
  def log(buy) do
    :telemetry.execute([:ash_template, :chain_buy, :left_for_a_person], %{count: 1}, %{
      state: buy.state
    })

    Logger.error("Buy left for a person: id=#{buy.id} state=#{buy.state}")
    buy
  end
end
