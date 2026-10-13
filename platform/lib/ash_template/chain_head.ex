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
  only when the last has finished, and a read gives up within one interval, so
  reads never pile up behind a slow node.
  """

  use GenServer

  alias AshTemplate.{ChainClient, SharedReading}

  @doc "One reader for each chain in `:chain_heads`."
  def children do
    for {chain_id, every_ms} <- Application.fetch_env!(:ash_template, :chain_heads) do
      Supervisor.child_spec({__MODULE__, {chain_id, every_ms}}, id: {__MODULE__, chain_id})
    end
  end

  @doc "Where the newest block of chain `chain_id` is held."
  def key(chain_id), do: {:chain_head, chain_id}

  def start_link({chain_id, every_ms}) when is_integer(chain_id) and every_ms >= 1_000,
    do: GenServer.start_link(__MODULE__, {chain_id, every_ms})

  @impl true
  def init(chain), do: {:ok, read(chain)}

  @impl true
  def handle_info(:read, chain), do: {:noreply, read(chain)}

  defp read({chain_id, every_ms} = chain) do
    case newest(chain_id, div(every_ms, 3)) do
      {:ok, block} -> SharedReading.put(key(chain_id), block)
      :error -> SharedReading.degraded(key(chain_id))
    end

    Process.send_after(self(), :read, every_ms)
    chain
  end

  # Connecting and the answer each get a third of the interval. These connect
  # options give the reads a connection pool of their own, so they never wait
  # behind another caller. A failed request is counted by the client under the
  # reader's own name, apart from the wallet's.
  defp newest(chain_id, wait_ms) do
    timeouts = [connect_options: [timeout: wait_ms], receive_timeout: wait_ms]

    with {:ok, "0x" <> hex} <-
           ChainClient.rpc(%{chain_id: chain_id}, "eth_blockNumber", [], "chain_head", timeouts),
         {block, ""} <- Integer.parse(hex, 16) do
      {:ok, block}
    else
      _no_block -> :error
    end
  end
end
