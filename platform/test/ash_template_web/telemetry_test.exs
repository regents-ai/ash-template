defmodule AshTemplateWeb.TelemetryTest do
  # The gauge of each running queue's oldest unfinished job counts from when the
  # job was due to run, not from when it was made: a job made an hour ago to run a
  # minute ago has waited a minute, and one between attempts has not waited at all.
  use ExUnit.Case, async: false

  alias AshTemplate.Repo

  @queues [:gauge_due, :gauge_retrying]

  setup do
    owner = Ecto.Adapters.SQL.Sandbox.start_owner!(Repo, shared: true)
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(owner) end)

    # Tests run Oban with no queues (config/test.exs), so the two the gauge reads
    # are started here and stopped after.
    for queue <- @queues, do: :ok = Oban.start_queue(queue: queue, limit: 1, local_only: true)
    on_exit(fn -> for queue <- @queues, do: Oban.stop_queue(queue: queue, local_only: true) end)
    wait_for_queues()
  end

  test "a queue's oldest job is aged from when it was due, not from when it was made" do
    now = DateTime.utc_now()

    for {queue, state, due_at} <- [
          {:gauge_due, "executing", DateTime.add(now, -60)},
          {:gauge_retrying, "retryable", DateTime.add(now, 600)}
        ] do
      %{}
      |> Oban.Job.new(worker: "Gauge", queue: queue, scheduled_at: due_at)
      |> Ecto.Changeset.change(state: state, inserted_at: DateTime.add(now, -3_600))
      |> Oban.insert!()
    end

    test = self()
    handler = {__MODULE__, make_ref()}

    :telemetry.attach(
      handler,
      [:ash_template, :jobs, :oldest_unfinished],
      fn _event, %{age_ms: age_ms}, %{queue: queue}, _config ->
        send(test, {:age, queue, age_ms})
      end,
      nil
    )

    on_exit(fn -> :telemetry.detach(handler) end)

    AshTemplateWeb.Telemetry.oldest_unfinished_jobs()

    assert_received {:age, "gauge_due", age_ms}
    assert age_ms in 60_000..120_000
    assert_received {:age, "gauge_retrying", 0}
  end

  defp wait_for_queues(tries \\ 50) do
    running = for %{queue: queue, paused: false} <- Oban.check_all_queues(), do: queue

    cond do
      Enum.all?(@queues, &(Atom.to_string(&1) in running)) ->
        :ok

      tries == 0 ->
        flunk("queues did not start: #{inspect(running)}")

      true ->
        Process.sleep(20)
        wait_for_queues(tries - 1)
    end
  end
end
