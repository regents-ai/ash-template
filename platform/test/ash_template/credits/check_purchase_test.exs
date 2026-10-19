defmodule AshTemplate.Credits.CheckPurchaseTest do
  # Invariants for following a sent Buy:
  # - one job follows a purchase at a time, however often the page asks;
  # - however often the job runs, the purchase is credited once, and the page
  #   hears how it ended.
  use ExUnit.Case, async: false
  use Oban.Testing, repo: AshTemplate.Repo

  alias AshTemplate.Credits.CheckPurchase
  alias AshTemplate.Repo

  setup do
    owner = Ecto.Adapters.SQL.Sandbox.start_owner!(Repo, shared: true)
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(owner) end)
  end

  test "a credited Buy is followed by one job and stays credited once, however often it runs" do
    wallet = "0x" <> Base.encode16(:crypto.strong_rand_bytes(20), case: :lower)
    hash = "0x" <> Base.encode16(:crypto.strong_rand_bytes(32), case: :lower)
    number = Ecto.UUID.generate()

    account = %{
      id: System.unique_integer([:positive]),
      privy_user_id: "did:privy:check-purchase-" <> Ecto.UUID.generate(),
      wallet_addresses: [wallet]
    }

    credited(account, wallet, 5, number, hash)
    Phoenix.PubSub.subscribe(AshTemplate.PubSub, CheckPurchase.topic(account.privy_user_id))

    assert {:ok, first} = CheckPurchase.start(account, wallet, 5, number, hash)
    assert {:ok, again} = CheckPurchase.start(account, wallet, 5, number, hash)
    assert again.conflict? and again.id == first.id
    assert [_one] = all_enqueued(worker: CheckPurchase)

    for _run <- 1..3 do
      assert :ok = perform_job(CheckPurchase, first.args)
      assert_receive {:credits_purchase, ^hash, %{purchase: %{status: :credited}, stalled?: false}}
    end

    assert Decimal.eq?(RegentCredits.balance(account.privy_user_id).available, 5)
  end

  # A paid purchase, recorded and credited as the chain check does once the
  # payment lands; there is no chain in tests to check.
  defp credited(account, wallet, dollars, number, hash) do
    {:ok, purchase} =
      RegentCredits.Purchase
      |> Ash.Changeset.for_create(
        :record,
        %{
          privy_user_id: account.privy_user_id,
          wallet: wallet,
          chain: :base,
          amount: dollars,
          number: number,
          tx_hash: hash
        },
        authorize?: false
      )
      |> Ash.create()

    {:ok, credited} =
      RegentCredits.Purchase
      |> Ash.ActionInput.for_action(:credit, %{id: purchase.id}, authorize?: false)
      |> Ash.run_action()

    credited
  end
end
