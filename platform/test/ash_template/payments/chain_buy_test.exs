defmodule AshTemplate.Payments.ChainBuyTest do
  # Invariants for the buying wallet (Sean 8 a, 29 Oct 2026):
  # - a buy is paid only in purchased Credits, held before anything is sent;
  # - the Credits are charged once the chain takes the sale's call, and given
  #   back when the approval or the call is refused;
  # - the outcome and its hashes are committed before the Credits are settled;
  # - a call that may still land keeps them held until its receipt answers;
  # - a buy left for a person keeps its Credits held and logs one line;
  # - everything bought in one day stays within the site's daily limit.
  use ExUnit.Case, async: false
  use Oban.Testing, repo: AshTemplate.Repo, prefix: "ash_template_app"

  import ExUnit.CaptureLog

  alias AshTemplate.Payments
  alias AshTemplate.Payments.ChainBuy
  alias AshTemplate.Payments.ChainBuy.CheckReceipt
  alias RegentCredits.Actor

  @sale "0x" <> String.duplicate("c", 40)
  @settings Application.compile_env!(:ash_template, ChainBuy)

  defmodule Sale do
    @moduledoc "One item at 2 USDC."
    @behaviour AshTemplate.Payments.Sale

    @impl true
    def price("key-1"),
      do: {:ok, %{sale: "0x" <> String.duplicate("c", 40), price_atomic: 2_000_000}}

    def price(_item), do: {:error, "This Key is sold out."}

    @impl true
    def call(item, receiver, price), do: %{data: :erlang.term_to_binary({item, receiver, price})}
  end

  defmodule Wallet do
    @moduledoc "Answers each buy and receipt read with what the test set, and records each buy."

    def buy(buy, signer) do
      send(self(), {:bought, buy, signer.address})
      Process.get(:buy_answer)
    end

    def status(call, _rpc_url), do: Process.get({:status, call})
  end

  setup do
    owner = Ecto.Adapters.SQL.Sandbox.start_owner!(AshTemplate.Repo)

    Application.put_env(
      :ash_template,
      ChainBuy,
      Keyword.merge(@settings,
        sale: Sale,
        wallet: Wallet,
        daily_limit_atomic: 5_000_000,
        private_key: "0x" <> String.duplicate("1", 64),
        rpc_url: "http://127.0.0.1:1"
      )
    )

    on_exit(fn ->
      Application.put_env(:ash_template, ChainBuy, @settings)
      Ecto.Adapters.SQL.Sandbox.stop_owner(owner)
    end)
  end

  test "a buy holds purchased Credits, sends once, and charges them when the chain takes it" do
    person = person(3)
    sent = %{approval: hash(1), call: hash(2)}
    Process.put(:buy_answer, {:ok, sent})

    assert {:ok, buy} = Payments.buy("key-1", person.wallet, actor: person.actor)
    assert {buy.state, buy.sale, buy.price_atomic} == {:sending, @sale, 2_000_000}
    assert held(person) == %{available: "1", held: "2"}

    assert %{success: 1} = Oban.drain_queue(queue: :chain_buys)
    assert_received {:bought, %{sale: @sale, price_atomic: 2_000_000, call: %{data: _}}, _wallet}

    assert %{state: :bought, hold: :held, approval_hash: approval, call_hash: call} = reload(buy)
    assert {approval, call} == {sent.approval, sent.call}
    assert held(person) == %{available: "1", held: "2"}

    assert %{success: 1} = Oban.drain_queue(queue: :default)
    assert %{hold: :charged} = reload(buy)
    assert held(person) == %{available: "1", held: "0"}
    assert [%{status: :charged}] = holds(person)
  end

  test "given Credits never pay for a buy" do
    person = person(1)
    given(person, 5)

    assert {:error, error} = Payments.buy("key-1", person.wallet, actor: person.actor)
    assert Exception.message(error) =~ "enough"
    assert Ash.read!(ChainBuy, authorize?: false) == []
  end

  test "a refused approval or call gives the Credits back" do
    person = person(4)

    Process.put(:buy_answer, {:error, {:approval_failed, hash(1)}})
    {:ok, first} = Payments.buy("key-1", person.wallet, actor: person.actor)
    Oban.drain_queue(queue: :chain_buys)

    Process.put(:buy_answer, {:error, {:call_reverted, %{approval: hash(2), call: hash(3)}}})
    {:ok, second} = Payments.buy("key-1", person.wallet, actor: person.actor)
    Oban.drain_queue(queue: :chain_buys)
    Oban.drain_queue(queue: :default)

    assert %{state: :failed, failure: "The approval did not go through."} = reload(first)
    assert %{state: :failed, failure: "The sale refused the purchase."} = reload(second)
    assert held(person) == %{available: "4", held: "0"}
    assert [%{status: :given_back}, %{status: :given_back}] = holds(person)
  end

  test "a call that may still land stays held until its receipt answers" do
    person = person(2)
    Process.put(:buy_answer, {:error, {:call_unknown, %{approval: hash(1), call: hash(2)}}})

    {:ok, buy} = Payments.buy("key-1", person.wallet, actor: person.actor)
    Oban.drain_queue(queue: :chain_buys)

    assert %{state: :unknown} = reload(buy)
    assert held(person) == %{available: "0", held: "2"}
    assert_enqueued(worker: CheckReceipt, args: %{id: buy.id})

    Process.put({:status, hash(2)}, :not_yet)
    assert {:snooze, 10} = perform_job(CheckReceipt, %{id: buy.id})

    Process.put({:status, hash(2)}, :ok)
    assert :ok = perform_job(CheckReceipt, %{id: buy.id})
    Oban.drain_queue(queue: :default)
    assert %{state: :bought, hold: :charged} = reload(buy)
    assert [%{status: :charged}] = holds(person)
  end

  test "a send that never finished is found, logged and keeps its Credits held" do
    person = person(2)
    {:ok, buy} = Payments.buy("key-1", person.wallet, actor: person.actor)

    AshTemplate.Repo.query!(
      "UPDATE ash_template_app.chain_buys SET updated_at = now() - interval '11 minutes' WHERE id = $1",
      [Ecto.UUID.dump!(buy.id)]
    )

    log = capture_log(fn -> AshOban.Test.schedule_and_run_triggers(ChainBuy) end)

    assert log =~ "Buy left for a person: id=#{buy.id} state=unknown"
    assert %{state: :unknown, hold: :held} = reload(buy)
    assert held(person) == %{available: "0", held: "2"}
  end

  test "the day's buys stay within the daily limit; failed buys do not count" do
    person = person(10)
    Process.put(:buy_answer, {:error, {:approval_failed, nil}})
    {:ok, _failed} = Payments.buy("key-1", person.wallet, actor: person.actor)
    Oban.drain_queue(queue: :chain_buys)

    assert {:ok, _first} = Payments.buy("key-1", person.wallet, actor: person.actor)
    assert {:ok, _second} = Payments.buy("key-1", person.wallet, actor: person.actor)
    assert {:error, error} = Payments.buy("key-1", person.wallet, actor: person.actor)
    assert Exception.message(error) =~ "Today's buying is used up."
  end

  test "an item the sale will not sell, or another wallet, is refused before anything is held" do
    person = person(3)

    assert {:error, sold_out} = Payments.buy("key-2", person.wallet, actor: person.actor)
    assert Exception.message(sold_out) =~ "This Key is sold out."

    assert {:error, elsewhere} = Payments.buy("key-1", wallet(), actor: person.actor)
    assert Exception.message(elsewhere) =~ "must be one of your own wallets"
    assert held(person) == %{available: "3", held: "0"}
  end

  defp person(credits) do
    did = "did:privy:chain-buy-" <> Ecto.UUID.generate()
    wallet = wallet()

    # A paid purchase, recorded and credited as the site's chain check does
    # once the payment lands; there is no chain in tests to check.
    {:ok, purchase} =
      RegentCredits.Purchase
      |> Ash.Changeset.for_create(
        :record,
        %{
          privy_user_id: did,
          wallet: wallet,
          chain: :base,
          amount: credits,
          number: Ecto.UUID.generate(),
          tx_hash: hash(:rand.uniform(1_000_000))
        },
        authorize?: false
      )
      |> Ash.create()

    {:ok, _credited} =
      RegentCredits.Purchase
      |> Ash.ActionInput.for_action(:credit, %{id: purchase.id}, authorize?: false)
      |> Ash.run_action()

    %{did: did, wallet: wallet, actor: Actor.person(did, [wallet], "template")}
  end

  defp given(person, amount) do
    admin = "did:privy:chain-buy-admin"
    Application.put_env(:regent_credits, :admins, [admin])
    on_exit(fn -> Application.put_env(:regent_credits, :admins, []) end)
    RegentCredits.give!(Ecto.UUID.generate(), [person.did], amount, actor: Actor.admin(admin))
  end

  defp held(person) do
    balance = RegentCredits.balance(person.did)
    %{available: Decimal.to_string(balance.available), held: Decimal.to_string(balance.held)}
  end

  defp holds(person),
    do: person.actor |> then(&RegentCredits.holds!(actor: &1)) |> Enum.sort_by(& &1.held_at)

  defp reload(buy), do: Ash.get!(ChainBuy, buy.id, authorize?: false)

  defp hash(n),
    do: "0x" <> (n |> Integer.to_string(16) |> String.downcase() |> String.pad_leading(64, "0"))

  defp wallet, do: "0x" <> Base.encode16(:crypto.strong_rand_bytes(20), case: :lower)
end
