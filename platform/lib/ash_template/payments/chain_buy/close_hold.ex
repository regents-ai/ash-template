defmodule AshTemplate.Payments.ChainBuy.CloseHold do
  @moduledoc """
  Settles a buy's Credits once its outcome is committed: a buy that went
  through charges them, a failed one gives them back. It runs in its own
  step, after the send's outcome and hashes are saved, so a settlement that
  fails is retried without losing what the chain was sent.
  """

  use Ash.Resource.Change

  alias AshTemplate.Credits

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.before_action(changeset, fn changeset ->
      case close(changeset.data) do
        {:ok, hold} -> Ash.Changeset.force_change_attribute(changeset, :hold, hold)
        {:error, error} -> Ash.Changeset.add_error(changeset, error)
      end
    end)
  end

  defp close(%{state: :bought, id: id}) do
    with {:ok, _charged} <- RegentCredits.charge(id, actor: Credits.site_actor()),
         do: {:ok, :charged}
  end

  defp close(%{state: :failed, id: id, failure: failure}) do
    with {:ok, _given_back} <- RegentCredits.give_back(id, failure, actor: Credits.site_actor()),
         do: {:ok, :given_back}
  end
end
