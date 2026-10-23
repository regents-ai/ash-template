defmodule AshTemplate.ChainRefreshTest do
  # The block reader reads on its slow clock, at once when asked after a quiet
  # spell, and only once for many asks close together. The node here refuses
  # every connection, so each read is counted by the client's failure event.
  use ExUnit.Case, async: false

  alias AshTemplate.{ChainHead, ChainRefresh, SharedReading}

  @chain 900_101
  @hour 3_600_000

  setup do
    nodes = Application.fetch_env!(:ash_template, :chain_nodes)
    Application.put_env(:ash_template, :chain_nodes, Map.put(nodes, @chain, "http://127.0.0.1:1"))
    test = self()

    :telemetry.attach(
      {__MODULE__, test},
      [:ash_template, :chain, :failure],
      fn _event, _measure, %{chain_id: chain_id, scope: scope}, _config ->
        if chain_id == @chain and scope == "chain_head", do: send(test, :read)
      end,
      nil
    )

    on_exit(fn ->
      :telemetry.detach({__MODULE__, test})
      Application.put_env(:ash_template, :chain_nodes, nodes)
      SharedReading.delete(ChainHead.key(@chain))
    end)

    reader = start_supervised!({ChainHead, {@chain, @hour}})
    assert_receive :read
    %{reader: reader}
  end

  test "an ask after a quiet spell reads at once", %{reader: reader} do
    :sys.replace_state(reader, &%{&1 | read_at: &1.read_at - ChainRefresh.gap_s() * 1_000})

    :ok = ChainHead.refresh(@chain)

    assert_receive :read
  end

  test "asks close together wait for the gap and cost one read", %{reader: reader} do
    for _ask <- 1..20, do: :ok = ChainHead.refresh(@chain)

    refute_receive :read, 200
    state = :sys.get_state(reader)
    assert Process.read_timer(state.timer) <= ChainRefresh.gap_s() * 1_000
  end

  test "an ask for another chain leaves this reader alone" do
    :ok = ChainHead.refresh(@chain + 1)

    refute_receive :read, 200
  end
end
