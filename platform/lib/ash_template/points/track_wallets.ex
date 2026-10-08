defmodule AshTemplate.Points.TrackWallets do
  @moduledoc false
  use Ash.Resource.Change
  @impl true
  def change(changeset, _, _) do
    Ash.Changeset.after_action(changeset, fn _, account ->
      if RegentPoints.Nfts.tracking?(),
        do: RegentPoints.Enqueue.call(RegentPoints.RefreshHoldings, %{account_id: account.id})

      {:ok, account}
    end)
  end
end
