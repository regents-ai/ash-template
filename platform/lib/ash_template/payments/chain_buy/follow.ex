defmodule AshTemplate.Payments.ChainBuy.Follow do
  @moduledoc """
  Queues what follows a send, in the transaction that saves its outcome: a
  buy that went through or failed has its Credits settled (`:close_hold`); a
  call that may still land has its receipt read (`CheckReceipt`); a call the
  chain never saw is left for a person (`LeftForAPerson`).
  """

  use Ash.Resource.Change

  alias AshTemplate.Payments.ChainBuy.{CheckReceipt, LeftForAPerson}

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.after_action(changeset, fn _changeset, buy ->
      with {:ok, _followed} <- follow(buy), do: {:ok, buy}
    end)
  end

  defp follow(%{state: state} = buy) when state in [:bought, :failed],
    do: buy |> AshOban.build_trigger(:close_hold) |> Oban.insert()

  defp follow(%{state: :unknown, call_hash: nil} = buy), do: {:ok, LeftForAPerson.log(buy)}
  defp follow(%{state: :unknown, id: id}), do: %{id: id} |> CheckReceipt.new() |> Oban.insert()
end
