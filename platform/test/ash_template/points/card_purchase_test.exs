defmodule AshTemplate.Points.CardPurchaseTest do
  # Invariant: Credits bought by card or Link earn Points as Credits bought in
  # USDC do, one Point per Credit and nothing for the card fee, once Points'
  # check reads the credited purchase; Credits a test card paid for earn none.
  use ExUnit.Case, async: false

  import Ecto.Query
  require Ash.Query
  alias AshTemplate.{Accounts, Repo}
  alias AshTemplate.Actors.System
  alias RegentPoints.{Entry, Event, IntakeWorker, Rejection, Store, Worker}

  @rule "credits.purchase_settled"

  setup do
    owner = Ecto.Adapters.SQL.Sandbox.start_owner!(Repo)
    starts_at = Application.get_env(:regent_points, :starts_at)
    rules = Application.get_env(:regent_points, :approved_rules)
    Application.put_env(:regent_points, :starts_at, ~U[2020-01-01 00:00:00Z])
    Application.put_env(:regent_points, :approved_rules, [@rule])

    on_exit(fn ->
      Application.put_env(:regent_points, :starts_at, starts_at)
      Application.put_env(:regent_points, :approved_rules, rules)
      Ecto.Adapters.SQL.Sandbox.stop_owner(owner)
    end)
  end

  test "a card purchase paid for real earns a Point per Credit once it is credited" do
    account = account()
    purchase = credited(account, 25, true)

    assert [job] = jobs("RegentPoints.IntakeWorker", "source_event_key", [purchase.id])
    assert job.args["source_kind"] == "card_purchase"
    assert IntakeWorker.perform(job) == :ok

    [event] = Ash.read!(Ash.Query.filter(Event, account_id == ^account.id), actor: Store.system())
    assert event.processing_status == :pending
    [award] = jobs("RegentPoints.Worker", "event_id", [event.id])
    assert Worker.perform(award) == :ok

    assert [%{points_micro_delta: 25_000_000}] =
             Ash.read!(Ash.Query.filter(Entry, account_id == ^account.id), actor: Store.system())
  end

  test "Credits a test card paid for earn no Points" do
    account = account()
    purchase = credited(account, 25, false)

    [job] = jobs("RegentPoints.IntakeWorker", "source_event_key", [purchase.id])
    assert IntakeWorker.perform(job) == :ok

    assert [%{reason_code: "card_test_payment"}] =
             Rejection
             |> Ash.read!(actor: Store.system())
             |> Enum.filter(&(&1.source["source_event_key"] == purchase.id))

    assert Ash.read!(Ash.Query.filter(Entry, account_id == ^account.id), actor: Store.system()) ==
             []
  end

  # A card purchase as Stripe's notice or the panel credits it.
  defp credited(account, credits, livemode) do
    price = RegentCredits.card_price(credits)
    id = Ecto.UUID.generate()

    RegentCredits.CardPurchase
    |> Ash.Changeset.for_create(
      :record,
      Map.merge(price, %{
        id: id,
        privy_user_id: account.privy_user_id,
        site: "template",
        credits: credits,
        session_id: "cs_" <> id,
        livemode: livemode
      }),
      authorize?: false
    )
    |> Ash.create!()
    |> Ash.Changeset.for_update(:credited, %{payment_intent_id: "pi_" <> id}, authorize?: false)
    |> Ash.update!()
  end

  defp jobs(worker, key, values) do
    Repo.all(
      from j in Oban.Job,
        where:
          j.worker == ^worker and j.state == "available" and
            fragment("?->>?", j.args, ^key) in ^Enum.map(values, &to_string/1)
    )
  end

  defp account do
    did = "did:privy:card-points-" <> Ecto.UUID.generate()
    wallet = "0x" <> Base.encode16(:crypto.strong_rand_bytes(20), case: :lower)
    Accounts.register_verified!(did, wallet, [wallet], actor: %System{})
  end
end
