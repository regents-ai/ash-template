# The watcher

The code here compiles against Ash 3.33, AshPostgres 2.13 and Phoenix LiveView 1.2.11.
It was not run against a database; the readers it follows are the tested versions
(SKILL.md names them). `MyApp` stands for the site's module prefix, and `Actors.System`
(whose `role: :system` the policies check) is the template's own. The example watches
ERC-20 `Transfer` logs.

## Files

| File | Holds |
| --- | --- |
| `lib/my_app/chain/client.ex` | The behaviour every chain read goes through |
| `lib/my_app/chain/rpc_client.ex` | The behaviour over JSON-RPC with Req, reading `latest` |
| `lib/my_app/chain.ex` | The domain and its code interfaces |
| `lib/my_app/chain/cursor.ex` | How far each contract has been read |
| `lib/my_app/chain/validations/cursor_unmoved.ex` | The check that a cursor moves only from where its pass found it |
| `lib/my_app/chain/<event>.ex` | One resource per kind of event row |
| `lib/my_app/chain/scanner.ex` | One pass: each stretch's read, its check against the saved rows, its commit |
| `lib/my_app/chain/read_contract.ex` | The Oban job that runs passes |
| `lib/my_app/chain/watch.ex` | The cron job that gives each contract its reading job, and brings it forward when asked |
| `test/support/chain_stub_client.ex` | The chain a test describes |

## The client

```elixir
defmodule MyApp.Chain.Client do
  @moduledoc """
  The chain as the app reads it, always at `latest`: a JSON-RPC node in
  production, a stand-in held by the test process in tests.
  """

  @type head :: %{number: non_neg_integer(), hash: String.t(), timestamp: DateTime.t()}

  @callback chain_id() :: {:ok, pos_integer()} | {:error, :unavailable | term()}
  @callback head() :: {:ok, head()} | {:error, :unavailable | term()}
  @callback logs(addresses :: [String.t()], topic0s :: [String.t()], from :: non_neg_integer(), to :: non_neg_integer()) ::
              {:ok, [map()]} | {:error, :too_many_results | :unavailable | term()}
  @callback transaction(chain :: map(), hash :: String.t()) :: {:ok, map() | nil} | {:error, term()}
  @callback receipt(chain :: map(), hash :: String.t()) :: {:ok, map() | nil} | {:error, term()}

  def configured, do: Application.fetch_env!(:my_app, MyApp.Chain)[:client]
end
```

The JSON-RPC client asks for `"latest"` wherever a block tag goes and lowercases every
hash and address it returns. `logs/4` answers `{:error, :too_many_results}` when the node
refuses a range for size, so the pass can halve it. Every call answers
`{:error, :unavailable}` when the node does not answer: a timeout, a refused connection,
a 429 or a 5xx. That is the provider's weather, not a fault, and the reading job waits
for it without failing (below). Keep the node's URL in an environment
variable and never log it; provider URLs carry keys.

`transaction/2` and `receipt/2` serve `onchain-buttons`' check: `RegentChain.Outcome`
calls them with the review's chain (`chain_id`, `name`, `rpc_url`) and the hash. They
read through the site's own node for `chain_id`, not the review's `rpc_url`, which is the
public address wallets are given. A watcher that only reads logs may leave them out of
its client.

## Domain and cursor

```elixir
defmodule MyApp.Chain do
  use Ash.Domain, otp_app: :my_app

  resources do
    resource MyApp.Chain.Cursor do
      define :cursor, action: :read, get_by: [:chain_id, :name]
      define :open_cursor, action: :open
      define :advance_cursor, action: :advance
    end

    resource MyApp.Chain.Transfer do
      define :record_transfer, action: :record
      define :seen_transfers, action: :seen, args: [:chain_id, :token, :from, :to, :transactions]
      define :transfers_for, action: :for_holder, args: [:holder]
    end
  end
end
```

```elixir
defmodule MyApp.Chain.Cursor do
  @moduledoc """
  How far one contract's events have been read on one chain, at the latest
  block: the first block not read yet, and the head last seen and when. It
  moves only from where its pass found it, in the transaction that saves the
  rows that pass read.
  """
  use Ash.Resource,
    domain: MyApp.Chain,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "chain_cursors"
    repo MyApp.Repo
  end

  actions do
    defaults [:read]

    create :open do
      accept [:chain_id, :name, :next_block]
      upsert? true
      upsert_identity :unique_cursor
      upsert_fields []
      upsert_condition expr(false)
      return_skipped_upsert? true
    end

    # Moves only a cursor still where this pass found it, so a second
    # machine's pass is never undone.
    update :advance do
      accept [:next_block, :head_block, :head_block_hash, :observed_at]
      require_attributes [:next_block, :head_block, :head_block_hash, :observed_at]
      argument :from, :integer, allow_nil?: false
      validate MyApp.Chain.Validations.CursorUnmoved
    end
  end

  policies do
    policy action_type(:read) do
      authorize_if always()
    end

    policy action([:open, :advance]) do
      authorize_if actor_attribute_equals(:role, :system)
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :chain_id, :integer, allow_nil?: false, public?: true, constraints: [min: 1]
    attribute :name, :string, allow_nil?: false, public?: true
    # The first block not read yet.
    attribute :next_block, :integer, allow_nil?: false, public?: true, constraints: [min: 0]
    attribute :head_block, :integer, public?: true, constraints: [min: 0]
    attribute :head_block_hash, :string, public?: true, constraints: [match: ~r/\A0x[0-9a-f]{64}\z/]
    attribute :observed_at, :utc_datetime_usec, public?: true
  end

  identities do
    identity :unique_cursor, [:chain_id, :name]
  end
end
```

The cursor check runs inside the `UPDATE`, so a pass holding an old copy of the cursor
gets `StaleRecord` and writes nothing. It is a validation, not
`change filter(expr(...))`, because Ash 3.33.11 drops that filter from a single
record's atomic update (see `ash-data`).

```elixir
defmodule MyApp.Chain.Validations.CursorUnmoved do
  use Ash.Resource.Validation

  @impl true
  def atomic(changeset, _opts, _context) do
    from = Ash.Changeset.get_argument(changeset, :from)

    {:atomic, [:next_block], expr(next_block != ^from),
     expr(error(Ash.Error.Changes.StaleRecord, %{resource: "cursor", filter: %{next_block: ^from}}))}
  end
end
```

## The event row

```elixir
defmodule MyApp.Chain.Transfer do
  @moduledoc "One `Transfer` log, exactly as the chain first gave it. Never changed or removed."
  use Ash.Resource,
    domain: MyApp.Chain,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    notifiers: [Ash.Notifier.PubSub]

  @address ~r/\A0x[0-9a-f]{40}\z/
  @hash ~r/\A0x[0-9a-f]{64}\z/

  postgres do
    table "chain_transfers"
    repo MyApp.Repo
  end

  pub_sub do
    module Phoenix.PubSub
    name MyApp.PubSub
    prefix "transfers"
    transform fn notification -> {:transfers_changed, notification.data.to} end
    publish :record, [:to]
  end

  actions do
    defaults [:read]

    read :for_holder do
      argument :holder, :string, allow_nil?: false, constraints: [match: @address]
      filter expr(to == ^arg(:holder) or from == ^arg(:holder))
      prepare build(sort: [block_number: :desc, log_index: :desc])
    end

    # The rows already saved from one contract that a stretch reads again: those
    # in blocks `from` to `to`, and every row of the `transactions` it read,
    # wherever they were saved.
    read :seen do
      argument :chain_id, :integer, allow_nil?: false
      argument :token, :string, allow_nil?: false, constraints: [match: @address]
      argument :from, :integer, allow_nil?: false
      argument :to, :integer, allow_nil?: false
      argument :transactions, {:array, :string}, allow_nil?: false

      filter expr(
               chain_id == ^arg(:chain_id) and token == ^arg(:token) and
                 ((block_number >= ^arg(:from) and block_number <= ^arg(:to)) or
                    transaction_hash in ^arg(:transactions))
             )
    end

    create :record do
      accept [:chain_id, :transaction_hash, :log_index, :block_number, :block_hash, :token, :from, :to, :amount]
      upsert? true
      upsert_identity :unique_chain_event
      upsert_fields []
      upsert_condition expr(false)
      return_skipped_upsert? true
    end
  end

  policies do
    policy action_type(:read) do
      authorize_if always()
    end

    policy action(:record) do
      authorize_if actor_attribute_equals(:role, :system)
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :chain_id, :integer, allow_nil?: false, public?: true, constraints: [min: 1]
    attribute :transaction_hash, :string, allow_nil?: false, public?: true, constraints: [match: @hash]
    attribute :log_index, :integer, allow_nil?: false, public?: true, constraints: [min: 0]
    attribute :block_number, :integer, allow_nil?: false, public?: true, constraints: [min: 0]
    attribute :block_hash, :string, allow_nil?: false, public?: true, constraints: [match: @hash]
    attribute :token, :string, allow_nil?: false, public?: true, constraints: [match: @address]
    attribute :from, :string, allow_nil?: false, public?: true, constraints: [match: @address]
    attribute :to, :string, allow_nil?: false, public?: true, constraints: [match: @address]
    # Raw token units, exactly as the log carried them.
    attribute :amount, :decimal, allow_nil?: false, public?: true, constraints: [min: 0]
    create_timestamp :inserted_at
  end

  identities do
    identity :unique_chain_event, [:chain_id, :transaction_hash, :log_index]
  end
end
```

- The identity carries `chain_id`, so the same table can hold Base and Robinhood Chain.
- The resource has no update or destroy action: a saved row is never changed or removed.
- `upsert_fields []` with `upsert_condition expr(false)` means a row saved again changes
  nothing, and `return_skipped_upsert? true` hands back the stored row rather than an
  error, so of two passes saving the same row the second ends at the cursor check.
- The `for_holder` read is what pages call. Add reads for pages; do not read the table
  from a page with raw Ecto.
- Aggregates over raw amounts (a balance, a total) are calculations or aggregates on the
  resource, still in raw units.

## One pass

Write the pass after Autolaunch's covered-call reader
(`repos/autolaunch/platform/lib/autolaunch/covered_calls/sales.ex`), which keeps the
rows it saved first exactly as rule 6 says.

```elixir
defmodule MyApp.Chain.Scanner do
  @moduledoc """
  One pass over one contract's `Transfer` logs, read at the latest block. Each
  stretch is one log search from 300 blocks before the cursor (one minute of
  Base) to at most 10,000 blocks on, never above the head this pass read, and
  its new rows and the cursor's move commit in one transaction.

  A transaction's rows are saved by the first stretch that reads it and kept as
  first saved. Each saved transaction is checked once, by the stretch that reads
  its block for the last time: when its logs no longer match its saved rows
  (moved to another block, in a block whose hash changed, changed, or gone),
  that is one warning naming the contract and the transaction, and the pass
  reads on. A log that does not read as a `Transfer`, or one block the node
  refuses, ends the pass before its stretch is saved, to be read again.
  """
  require Logger

  alias MyApp.Chain

  @reread 300
  @stretch 10_000
  # keccak256("Transfer(address,address,uint256)")
  @transfer "0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef"
  @system %MyApp.Actors.System{}

  @doc """
  Reads `contract` (`chain_id`, `name` and lowercase `address`) on from `cursor`
  up to the head. `:ok` once the cursor is past the head this pass read, or when
  another pass moved it first; `{:error, reason}` when the node or the database
  failed, the cursor then standing after the last stretch saved.
  """
  def pass(client, contract, cursor) do
    with {:ok, head} <- client.head(), do: forward(client, contract, cursor, head)
  end

  # A node that is behind makes a shorter pass, never missing history.
  defp forward(_client, contract, %{next_block: next} = cursor, %{number: number} = head)
       when next > number,
       do: lag(contract, cursor, head)

  defp forward(client, contract, cursor, head) do
    from = max(cursor.next_block - @reread, 0)
    to = min(head.number, from + @stretch - 1)

    with {:ok, logs} <- logs(client, contract, from, to),
         {:ok, read} <- rows(contract.chain_id, logs),
         {:ok, saved} <-
           Chain.seen_transfers(
             contract.chain_id,
             contract.address,
             from,
             cursor.next_block - 1,
             read |> Enum.map(& &1.transaction_hash) |> Enum.uniq(),
             actor: @system
           ),
         {fresh, moved} = compare(read, saved, from, to - @reread),
         {:ok, cursor} <- commit(cursor, fresh, to, head) do
      Enum.each(moved, &warn(contract, &1))
      forward(client, contract, cursor, head)
    else
      :superseded -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  # A range the node refuses for its size is asked for in halves, down to one
  # block; one block it still refuses ends the pass.
  defp logs(client, contract, from, to) do
    case client.logs([contract.address], [@transfer], from, to) do
      {:error, :too_many_results} when from < to ->
        middle = div(from + to, 2)

        with {:ok, low} <- logs(client, contract, from, middle),
             {:ok, high} <- logs(client, contract, middle + 1, to),
             do: {:ok, low ++ high}

      answer ->
        answer
    end
  end

  # The rows of transactions not saved yet, and each saved transaction whose
  # block this stretch reads for the last time (`from` to `last`: the next
  # stretch's search starts after `last`) and whose logs read now differ from
  # its saved rows. A transaction's logs are all in one block.
  defp compare(read, saved, from, last) do
    saved = Enum.group_by(saved, & &1.transaction_hash)
    read_now = Enum.group_by(read, & &1.transaction_hash)
    fresh = Enum.reject(read, &Map.has_key?(saved, &1.transaction_hash))

    moved =
      for {transaction, [%{block_number: block} | _] = rows} <- saved,
          from <= block and block <= last,
          facts(rows) != facts(Map.get(read_now, transaction, [])),
          do: transaction

    {fresh, Enum.sort(moved)}
  end

  # What a transaction's logs say, in a form a saved row and a read one share.
  defp facts(rows) do
    rows
    |> Enum.map(&{&1.log_index, &1.block_number, &1.block_hash, &1.token, &1.from, &1.to, Decimal.to_integer(&1.amount)})
    |> Enum.sort()
  end

  # The stretch's new rows and the cursor's move to `to + 1` commit together, and
  # pages hear about the rows only after. An action that fails rolls the whole
  # transaction back with its own error, in whichever form Ash gives it.
  defp commit(cursor, rows, to, head) do
    MyApp.Repo.transact(fn ->
      with {:ok, notifications} <- record(rows),
           {:ok, cursor} <-
             Chain.advance_cursor(
               cursor,
               %{from: cursor.next_block, next_block: to + 1, head_block: head.number,
                 head_block_hash: head.hash, observed_at: DateTime.utc_now()},
               actor: @system
             ),
           do: {:ok, {cursor, notifications}}
    end)
    |> case do
      {:ok, {cursor, notifications}} ->
        Ash.Notifier.notify(notifications)
        {:ok, cursor}

      {:error, error} ->
        if stale?(error), do: :superseded, else: {:error, error}
    end
  end

  defp record(rows) do
    Enum.reduce_while(rows, {:ok, []}, fn row, {:ok, notifications} ->
      case Chain.record_transfer(row, actor: @system, return_notifications?: true) do
        {:ok, _row, more} -> {:cont, {:ok, more ++ notifications}}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
  end

  defp stale?(error),
    do: Enum.any?(Ash.Error.to_error_class(error).errors, &match?(%Ash.Error.Changes.StaleRecord{}, &1))

  defp warn(contract, transaction) do
    Logger.warning(
      "Transfers on #{contract.address} in transaction #{transaction} no longer match the chain; " <>
        "the rows saved first are kept"
    )
  end

  defp lag(contract, cursor, head) do
    :telemetry.execute(
      [:my_app, :indexer, :lag],
      %{blocks: max(head.number - (cursor.next_block - 1), 0)},
      %{indexer: :transfers, chain_id: contract.chain_id}
    )
  end

  # Each log as its row, in chain order; a log that does not read as a
  # `Transfer` ends the pass, naming its transaction.
  defp rows(chain_id, logs) do
    read = Enum.map(logs, &{&1, row(chain_id, &1)})

    case Enum.find(read, &match?({_log, :error}, &1)) do
      nil -> {:ok, for({_log, {:ok, row}} <- read, do: row)}
      {log, :error} -> {:error, {:unreadable_log, log["transactionHash"]}}
    end
  end

  # A raw `Transfer` log as a row: lowercase hex, amount in raw units.
  defp row(chain_id, %{"topics" => [_signature, from, to], "data" => "0x" <> data} = log) do
    with {:ok, from} <- topic_address(from),
         {:ok, to} <- topic_address(to),
         {:ok, <<amount::256>>} <- Base.decode16(data, case: :mixed) do
      {:ok,
       %{
         chain_id: chain_id,
         transaction_hash: String.downcase(log["transactionHash"]),
         log_index: quantity(log["logIndex"]),
         block_number: quantity(log["blockNumber"]),
         block_hash: String.downcase(log["blockHash"]),
         token: String.downcase(log["address"]),
         from: from,
         to: to,
         amount: Decimal.new(amount)
       }}
    else
      _unreadable -> :error
    end
  end

  defp row(_chain_id, _log), do: :error

  defp topic_address("0x" <> <<_padding::binary-size(24), address::binary-size(40)>>),
    do: {:ok, "0x" <> String.downcase(address)}

  defp topic_address(_topic), do: :error

  defp quantity("0x" <> digits), do: String.to_integer(digits, 16)
end
```

Each stretch, in order:

1. Search from 300 blocks before the cursor (`from`) to at most 10,000 blocks on (`to`),
   never above the head this pass read. The first 300 are blocks already recorded, read
   again; the next stretch's search starts 300 blocks before this one's end, so every
   block is read at least twice.
2. Read the saved rows of the blocks already recorded, and every saved row of the
   transactions the search returned, wherever they were saved.
3. Compare. A transaction not saved yet is new history: its rows are saved. A saved
   transaction is never saved again, wherever the chain puts it. A saved transaction
   whose block lies from `from` to `to - 300`, which no later search reaches, and whose
   logs read now differ from its rows, is named.
4. Commit the new rows and the cursor's move to the stretch's end in one transaction,
   then give one warning for each named transaction, then read the next stretch.

- The warning comes after the commit. The blocks a stretch checks end just before the
  next stretch's search begins, so the stretches that commit check each block exactly
  once: a saved transaction is named at most once, and a stretch that does not commit
  names nothing; the pass that reads it again names it.
- `Repo.transact/1` wraps the rows and the cursor; if either fails, neither is saved.
- `return_notifications?: true` keeps Ash from sending notices for rows that might still
  roll back; `Ash.Notifier.notify/1` sends them once the transaction has committed.
- A stale cursor (another pass moved it) fails `advance`; the pass ends with `:ok`, and
  the next one starts from where the cursor now stands.
- Nothing is passed over (rule 6): a log that does not decode, or one block the node
  keeps refusing, returns `{:error, reason}` before its stretch commits, and the job
  reads it again a minute later.

## The reading job

```elixir
defmodule MyApp.Chain.ReadContract do
  @moduledoc """
  Keeps one contract's history current. Each run is one scanner pass; the job then
  waits five minutes and runs again. `MyApp.Chain.Watch.refresh/1` brings the next
  run forward to ten seconds away, never later. When the node does not answer, the job
  waits a minute; any other failure is retried a minute later.
  """
  use Oban.Worker,
    queue: :chain,
    max_attempts: 20,
    unique: [keys: [:name], period: :infinity, states: :incomplete]

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"chain_id" => chain_id, "name" => name, "address" => address}}) do
    client = MyApp.Chain.Client.configured()
    contract = %{chain_id: chain_id, name: name, address: address}

    with {:ok, ^chain_id} <- client.chain_id(),
         :ok <- MyApp.Chain.Scanner.pass(client, contract, MyApp.Chain.cursor!(chain_id, name)) do
      {:snooze, 300}
    else
      {:ok, other_chain} ->
        Logger.error("#{name} is on chain #{chain_id} but the node serves #{other_chain}; not reading it")
        {:cancel, {:wrong_chain, other_chain}}

      {:error, :unavailable} ->
        Logger.warning("#{name} not read: the node did not answer; reading again in a minute")
        {:snooze, 60}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl Oban.Worker
  def backoff(%Oban.Job{}), do: 60
end

defmodule MyApp.Chain.Watch do
  @moduledoc """
  Every five minutes (`config :my_app, Oban, cron:`), makes sure each watched contract
  has its reading job. As the site's `ChainRefresh` reader, brings that job forward
  when a person's on-chain press lands.
  """
  use Oban.Worker, queue: :default, max_attempts: 1

  @behaviour MyApp.ChainRefresh

  alias MyApp.Chain.ReadContract

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    Enum.each(contracts(), &Oban.insert!(ReadContract.new(&1)))
  end

  @impl MyApp.ChainRefresh
  def refresh(chain_id) do
    soon = DateTime.add(DateTime.utc_now(), MyApp.ChainRefresh.gap_s())

    contracts()
    |> Enum.filter(&(&1.chain_id == chain_id))
    |> Enum.each(&(&1 |> ReadContract.new() |> Oban.insert!() |> bring_forward(soon)))
  end

  # A waiting job due later than `soon` moves to `soon`; one due sooner keeps its
  # time, so presses that keep coming never put the read off.
  defp bring_forward(%Oban.Job{state: state, scheduled_at: at} = job, soon)
       when state in ["scheduled", "retryable"] do
    if DateTime.after?(at, soon), do: {:ok, _job} = Oban.update_job(job, %{scheduled_at: soon})
    :ok
  end

  defp bring_forward(%Oban.Job{}, _soon), do: :ok

  defp contracts, do: Application.fetch_env!(:my_app, MyApp.Chain)[:contracts]
end
```

`:contracts` lists each watched contract as
`%{chain_id: 8453, name: "...", address: "0x..."}`, the address in lowercase; name
`MyApp.Chain.Watch` among `config :my_app, MyApp.ChainRefresh, readers:`. The job is
unique while it is incomplete, so inserting it again is how the watch says "make sure
it exists": `Oban.insert!/1` then answers the job already there, read from the
database, and a new job runs at once. `refresh/1` moves a waiting job's `scheduled_at`
to ten seconds from now only when it was due later, so many presses close together
cost one pass and presses that keep coming never put the pass off. (Oban's `replace:`
would set every press's time, later as well as sooner, so it is not used here.) A press that lands while a pass is running is seen by that pass if it read the
head after the press, or else at the next turn. Open the cursor at the contract's
deployment block with `Chain.open_cursor/2`, which leaves an existing one alone. Never
start the reading from the site's supervisor: Oban runs it on whichever machine takes
the job, once.

## The page

```elixir
defmodule MyAppWeb.HoldingsLive do
  use Phoenix.LiveView

  @impl true
  def mount(_params, _session, socket) do
    holder = socket.assigns.current_wallet
    if connected?(socket), do: Phoenix.PubSub.subscribe(MyApp.PubSub, "transfers:#{holder}")
    {:ok, socket |> assign(holder: holder, reread?: false) |> load()}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <ul id="transfers" phx-update="stream">
      <li :for={{id, transfer} <- @streams.transfers} id={id}>{transfer.amount}</li>
    </ul>
    """
  end

  # A notice is only a hint to read again; many in one second make one read.
  @impl true
  def handle_info({:transfers_changed, _holder}, %{assigns: %{reread?: true}} = socket), do: {:noreply, socket}

  def handle_info({:transfers_changed, _holder}, socket) do
    Process.send_after(self(), :reread, 1_000)
    {:noreply, assign(socket, reread?: true)}
  end

  def handle_info(:reread, socket), do: {:noreply, socket |> assign(reread?: false) |> load()}

  defp load(socket) do
    transfers = MyApp.Chain.transfers_for!(socket.assigns.holder, actor: socket.assigns.current_scope)
    stream(socket, :transfers, transfers, reset: true)
  end
end
```

- Subscribe only when connected; the first render already read the rows.
- A notice starts one read a second later, and more notices in that second join it.
- Every read goes through the code interface with the viewer's actor; the notice
  carries no row data to show.
- For the "catching up" notice, read the cursor through a `fresh?` calculation
  (`observed_at` within 420 seconds and `head_block - next_block` within ten minutes of
  blocks, 3,000 on Base, as Patchbay's `Patchbay.Offers.Cursor` has) and show plain
  words: "Catching up with the chain. Recent activity may take a moment to appear."

## Tests

- **Stub client** holding the chain in the test process (`Process.put`), as
  `test/support/chain_stub_client.ex` in Keyfleet does: a head, raw logs with their
  block hashes, and the requests it was asked, so a test can check the ranges asked for.
- **A pass** against the stub: rows appear once; the same pass twice changes nothing; a
  refused range is asked for in halves; a log from a transaction not saved yet, in the
  blocks read again, is saved.
- **A saved transaction that no longer matches**, once for each case: a log read again
  with other values; a block whose hash changed, the log now read from the new block or
  from another one; a log gone. In each the pass returns `:ok`, the saved rows are as
  first saved, the cursor reaches the head, and the pass that reads the block for the
  last time gives one warning naming the contract and the transaction. Passes before
  and after it give none, and nothing of that transaction is saved again wherever the
  chain puts it. Capture the log with `ExUnit.CaptureLog`; count the warnings and check
  that each names the contract and the transaction, never the rest of its words.
- **Nothing passed over**: a log that does not read as a `Transfer`, and one block the
  node keeps refusing, each end the pass with `{:error, _}`, nothing of that stretch
  saved and the cursor where it stood.
- **The page**: a notice leads to one re-read showing the new row. Send the notice with
  `Ash.Notifier.notify/1` or by running the pass in the test.
- **At Base's pace**: a pass five blocks a second behind. A day missed (432,000 blocks)
  is caught up in capped stretches, each search starting 300 blocks before the cursor
  and none above the head (the stub records the ranges asked); rows from blocks sharing
  one timestamp come back in chain order; a saved transaction changed anywhere in the
  300 blocks read again is named once.
- Capture expected warnings with `ExUnit.CaptureLog` so the output stays clean.
- **Against a real chain**: anvil tests tagged `:external`, left out of the default run.
