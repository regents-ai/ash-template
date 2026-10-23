defmodule AshTemplate.ChainHead do
  @moduledoc """
  The newest block of one chain, read once for every open page and held in
  `AshTemplate.SharedReading` under `key/1`. One runs for each chain in
  `:chain_heads`, on each machine.

  This is a supervised reader of an outside clock, one of the two shapes the
  `elixir-stack` skill lets reread on their own. It is allowed because nothing
  here is work that could be lost. It holds no queue and no copy of database
  rows, never writes the database, and stores only through `SharedReading`; a
  read that fails is not tried again, because the next one replaces it.
  Recorded chain events stay with the site's chain watcher (`chain-events`).

  The first read happens as the reader starts, so the key holds a reading or
  its degraded mark before the site serves a page. Each later read is scheduled
  only when the last has finished, and a read gives up within ten seconds, so
  reads never pile up behind a slow node.

  Between its slow turns a reader reads again when asked (`refresh/1`, through
  `AshTemplate.ChainRefresh`): at once, or ten seconds after its last read, so
  many asks close together cost one read.
  """

  use GenServer

  @behaviour AshTemplate.ChainRefresh

  alias AshTemplate.{ChainClient, ChainRefresh, SharedReading}

  # Connecting and the answer each get this long.
  @wait_ms 5_000

  @doc "One reader for each chain in `:chain_heads`."
  def children do
    for {chain_id, every_ms} <- Application.fetch_env!(:ash_template, :chain_heads) do
      Supervisor.child_spec({__MODULE__, {chain_id, every_ms}}, id: {__MODULE__, chain_id})
    end
  end

  @doc "Where the newest block of chain `chain_id` is held."
  def key(chain_id), do: {:chain_head, chain_id}

  @doc "Wakes the reader of chain `chain_id` on every machine."
  @impl ChainRefresh
  def refresh(chain_id),
    do: Phoenix.PubSub.broadcast(AshTemplate.PubSub, topic(chain_id), {:chain_refresh, chain_id})

  def start_link({chain_id, every_ms})
      when is_integer(chain_id) and every_ms > 2 * @wait_ms,
      do: GenServer.start_link(__MODULE__, {chain_id, every_ms})

  @impl true
  def init({chain_id, every_ms}) do
    :ok = Phoenix.PubSub.subscribe(AshTemplate.PubSub, topic(chain_id))
    {:ok, read(%{chain_id: chain_id, every_ms: every_ms, read_at: nil, next: nil, timer: nil})}
  end

  # Only the read scheduled last is made; one it replaced is dropped.
  @impl true
  def handle_info({:read, next}, %{next: next} = state), do: {:noreply, read(state)}
  def handle_info({:read, _replaced}, state), do: {:noreply, state}

  def handle_info({:chain_refresh, _chain_id}, state) do
    case state.read_at + ChainRefresh.gap_s() * 1_000 - now() do
      wait when wait <= 0 -> {:noreply, read(state)}
      wait -> {:noreply, sooner(state, wait)}
    end
  end

  # A read already due sooner than `wait` stays as it is.
  defp sooner(state, wait) do
    case Process.read_timer(state.timer) do
      left when is_integer(left) and left > wait -> schedule(state, wait)
      _sooner_already -> state
    end
  end

  defp read(state) do
    case newest(state.chain_id) do
      {:ok, block} -> SharedReading.put(key(state.chain_id), block)
      :error -> SharedReading.degraded(key(state.chain_id))
    end

    schedule(%{state | read_at: now()}, state.every_ms)
  end

  defp schedule(state, wait) do
    if state.timer, do: Process.cancel_timer(state.timer)
    next = make_ref()
    %{state | next: next, timer: Process.send_after(self(), {:read, next}, wait)}
  end

  defp now, do: System.monotonic_time(:millisecond)

  defp topic(chain_id), do: "chain_head:#{chain_id}"

  # These connect options give the reads a connection pool of their own, so
  # they never wait behind another caller. A failed request is counted by the
  # client under the reader's own name, apart from the wallet's.
  defp newest(chain_id) do
    timeouts = [connect_options: [timeout: @wait_ms], receive_timeout: @wait_ms]

    with {:ok, "0x" <> hex} <-
           ChainClient.rpc(%{chain_id: chain_id}, "eth_blockNumber", [], "chain_head", timeouts),
         {block, ""} <- Integer.parse(hex, 16) do
      {:ok, block}
    else
      _no_block -> :error
    end
  end
end
