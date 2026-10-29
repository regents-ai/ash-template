defmodule AshTemplate.Payments.ChainBuy.CloseHold do
  @moduledoc """
  Settles the buy's Credits in the same transaction as its new state: a buy
  that went through charges them, a failed one gives them back. A call that
  may still land keeps them held and queues `CheckReceipt`; one whose call
  was never seen by the chain is left for a person to look up.
  """

  use Ash.Resource.Change

  alias AshTemplate.Credits
  alias AshTemplate.Payments.ChainBuy.CheckReceipt

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.after_action(changeset, fn _changeset, buy ->
      with {:ok, _closed} <- close(buy), do: {:ok, buy}
    end)
  end

  defp close(%{state: :bought, id: id}), do: RegentCredits.charge(id, actor: Credits.site_actor())

  defp close(%{state: :failed, id: id, failure: failure}),
    do: RegentCredits.give_back(id, failure, actor: Credits.site_actor())

  defp close(%{state: :unknown, call_hash: nil}), do: {:ok, :left_for_a_person}
  defp close(%{state: :unknown, id: id}), do: %{id: id} |> CheckReceipt.new() |> Oban.insert()
end
