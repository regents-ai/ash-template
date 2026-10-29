defmodule AshTemplate.Payments.ChainBuy.Reserve do
  @moduledoc """
  Inside the buy's transaction: takes the day's buying lock, refuses a buy
  that would carry the day's buys past the site's limit, then holds the
  price in the buyer's purchased Credits under the buy's id. Given Credits
  never pay for a buy, since Regents pays for it in USDC. An agent's hold
  counts against the limits its person set for it.

  The lock is held until the transaction ends, so two buys cannot both take
  the last of the day's limit. Failed buys do not count toward it.
  """

  use Ash.Resource.Change

  require Ash.Query

  alias AshTemplate.Payments.ChainBuy
  alias AshTemplate.Payments.ChainBuy.Settings

  @lock_key :erlang.phash2({__MODULE__, :daily_limit})

  @impl true
  def change(changeset, _opts, %{actor: actor}) do
    Ash.Changeset.before_action(changeset, fn changeset ->
      price = Ash.Changeset.get_attribute(changeset, :price_atomic)
      AshTemplate.Repo.query!("SELECT pg_advisory_xact_lock($1)", [@lock_key])

      if bought_today() + price > Settings.daily_limit_atomic() do
        Ash.Changeset.add_error(changeset,
          field: :item,
          message: "Today's buying is used up. Try again tomorrow."
        )
      else
        hold(changeset, price, actor)
      end
    end)
  end

  defp hold(changeset, price, actor) do
    case RegentCredits.hold(
           Ash.Changeset.get_attribute(changeset, :id),
           actor.privy_user_id,
           Decimal.div(price, 1_000_000),
           "chain_buy",
           %{purchased_only?: true},
           actor: actor
         ) do
      {:ok, _hold} -> changeset
      {:error, error} -> Ash.Changeset.add_error(changeset, error)
    end
  end

  # Every buyer's buys count, so the sum reads past the actor's own rows.
  defp bought_today do
    ChainBuy
    |> Ash.Query.filter(
      inserted_at >= ^DateTime.new!(Date.utc_today(), ~T[00:00:00]) and state != :failed
    )
    |> Ash.sum!(:price_atomic, authorize?: false)
    |> Kernel.||(0)
  end
end
