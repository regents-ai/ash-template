defmodule AshTemplateWeb.Telemetry do
  @moduledoc """
  The site's measurements, as `:telemetry` events, and their Prometheus export on
  the private metrics listener (`AshTemplateWeb.Metrics`). Fly Sentinel's site
  watch reads the three `health.*` series from every site: Ecto's
  `[:ash_template, :repo, :query]` (`queue_time` is the wait for a connection),
  `[:ash_template, :chain, :failure]` for each chain request that got no answer
  (`AshTemplate.ChainClient`), and `[:ash_template, :wallet, :failure]` for each
  press the browser reported as not sent or not confirmed (`wallet_failed/2`).
  Background jobs report each run's outcome and time from Oban's own events, and
  `[:ash_template, :jobs, :oldest_unfinished]` carries `age_ms` of the oldest
  available, running or retrying job in each running `queue`, 0 when there is
  none, every ten seconds. A paused queue keeps its jobs waiting on purpose, so it
  is not measured.
  The engine's memory, run queues and process counts come from telemetry_poller's
  default poller, every 10 seconds (`config/config.exs`).
  Each question asked of Jev (`RegentJev`, `[:regent_jev, :decide]`) is counted
  by outcome, with its tokens, what OpenRouter charged and how long it took.
  The figures every visitor sees alike (`AshTemplate.SharedReading`) report, for
  each kind, how many keys are held, how many have never been read, how long ago
  the oldest was read, each reading that could not be taken and each one refused.
  """

  import Ecto.Query, only: [from: 2]
  import Telemetry.Metrics

  require Logger

  # The reasons the wallet hook reports (`Failure` in send_step.ts). Only these
  # are counted, so a label never holds whatever a browser chose to send.
  @wallet_failures ~w(step_unknown wallet_unavailable network_mismatch wallet_declined insufficient_funds send_unconfirmed)

  def child_spec(_arg) do
    TelemetryMetricsPrometheus.Core.child_spec(
      metrics: metrics(),
      name: prometheus_reporter(),
      start_async: false
    )
  end

  def prometheus_reporter, do: :ash_template_prometheus

  @doc """
  Counts one press the browser reported as not sent or not confirmed, for the
  wallet-button component `flow`. A reason the hook never sends is not counted.
  """
  def wallet_failed(flow, reason) when reason in @wallet_failures do
    :telemetry.execute([:ash_template, :wallet, :failure], %{count: 1}, %{
      flow: flow,
      reason: reason
    })
  end

  def wallet_failed(_flow, _reason), do: :ok

  @doc "The poller for the measurements the site takes itself, started after Oban."
  def site_poller,
    do:
      {:telemetry_poller,
       measurements: [
         {AshTemplate.SharedReading, :measure, []},
         {__MODULE__, :oldest_unfinished_jobs, []}
       ],
       period: 10_000,
       name: :ash_template_site_poller}

  # The poller drops for good a measurement that raises or exits, and the row
  # would then keep its last number. So whatever stops this tick (a database
  # that cannot answer, a queue too busy to say whether it runs, Oban or the
  # repo restarting) is logged and skipped; the next tick measures again.
  @doc false
  def oldest_unfinished_jobs do
    measure_oldest_unfinished_jobs()
  rescue
    error -> not_measured(Exception.message(error))
  catch
    :exit, reason -> not_measured(Exception.format_exit(reason))
  end

  defp not_measured(why), do: Logger.warning("background job age not measured: #{why}")

  # Only running queues are measured: a paused queue holds its jobs on purpose,
  # and its age would only grow. Where no queue runs (tests), nothing is read.
  defp measure_oldest_unfinished_jobs do
    case for %{queue: queue, paused: false} <- Oban.check_all_queues(), do: queue do
      [] -> :ok
      running -> report_oldest(running)
    end
  end

  defp report_oldest(running) do
    %{prefix: prefix} = Oban.config()

    oldest =
      from(j in Oban.Job,
        where: j.state in ["available", "executing", "retryable"],
        group_by: j.queue,
        select: {j.queue, min(j.inserted_at)}
      )
      # Oban's job table has no Ash resource; this only reads it.
      |> AshTemplate.Repo.all(prefix: prefix)
      |> Map.new()

    now = DateTime.utc_now()

    for queue <- running do
      age_ms =
        case oldest[queue] do
          nil -> 0
          inserted_at -> DateTime.diff(now, inserted_at, :millisecond)
        end

      :telemetry.execute([:ash_template, :jobs, :oldest_unfinished], %{age_ms: age_ms}, %{
        queue: queue
      })
    end
  end

  defp metrics do
    [
      counter("ash_template.privy.browser_failure.total", tags: [:reason]),
      counter("ash_template.privy.session_refused.total", tags: [:stage, :reason]),
      counter("ash_template.session_bootstrap.rate_limited.total", tags: [:source]),
      counter("ash_template.session_authority.absent_row.total"),
      distribution("health.db_queue.seconds",
        event_name: [:ash_template, :repo, :query],
        measurement: :queue_time,
        unit: {:native, :second},
        description: "Seconds a query waited for a database connection",
        reporter_options: [buckets: [0.001, 0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5]]
      ),
      counter("health.chain_request_failures.total",
        event_name: [:ash_template, :chain, :failure],
        tags: [:method, :class, :chain_id, :scope],
        description: "Chain requests that got no answer"
      ),
      last_value("health.job.oldest_age.seconds",
        event_name: [:ash_template, :jobs, :oldest_unfinished],
        measurement: :age_ms,
        unit: {:millisecond, :second},
        tags: [:queue],
        description:
          "Age of the oldest unfinished background job in the queue, counted from when it was added"
      ),
      counter("ash_template.jobs.finished.total",
        event_name: [:oban, :job, :stop],
        tags: [:queue, :worker, :state],
        description: "Job runs that ended done, cancelled or snoozed"
      ),
      counter("ash_template.jobs.failed.total",
        event_name: [:oban, :job, :exception],
        tags: [:queue, :worker, :state],
        description: "Job runs that failed; state says whether the job will retry"
      ),
      distribution("ash_template.jobs.duration.seconds",
        event_name: [:oban, :job, :stop],
        measurement: :duration,
        unit: {:native, :second},
        tags: [:queue, :worker],
        reporter_options: [buckets: [0.01, 0.05, 0.1, 0.5, 1, 5, 15, 60]]
      ),
      counter("ash_template.jev.questions.total",
        event_name: [:regent_jev, :decide],
        tags: [:outcome],
        description: "Questions asked of Jev, by outcome"
      ),
      sum("ash_template.jev.input_tokens.total",
        event_name: [:regent_jev, :decide],
        measurement: :input_tokens,
        description: "Input tokens Jev was billed for"
      ),
      sum("ash_template.jev.output_tokens.total",
        event_name: [:regent_jev, :decide],
        measurement: :output_tokens,
        description: "Output tokens Jev was billed for"
      ),
      # A Prometheus sum adds whole numbers only, so the dollars are a histogram;
      # its `_sum` series is the running total.
      distribution("ash_template.jev.cost.usd",
        event_name: [:regent_jev, :decide],
        measurement: :cost_usd,
        description: "US dollars OpenRouter charged per Jev question",
        reporter_options: [buckets: [0.00001, 0.0001, 0.001, 0.01, 0.1]]
      ),
      distribution("ash_template.jev.duration.seconds",
        event_name: [:regent_jev, :decide],
        measurement: :duration,
        unit: {:native, :second},
        tags: [:outcome],
        reporter_options: [buckets: [0.1, 0.25, 0.5, 1, 2.5, 5, 10, 30]]
      ),
      last_value("health.shared_reading.oldest.seconds",
        event_name: [:ash_template, :shared_reading, :kind],
        measurement: :oldest_seconds,
        tags: [:kind],
        description: "Seconds since the oldest shared reading of each kind was read"
      ),
      last_value("health.shared_reading.never_read.keys",
        event_name: [:ash_template, :shared_reading, :kind],
        measurement: :never_read,
        tags: [:kind],
        description: "Keys of the kind that have had no reading since the site started"
      ),
      counter("health.shared_reading.degraded.total",
        event_name: [:ash_template, :shared_reading, :degraded],
        tags: [:kind],
        description: "Shared readings that could not be taken"
      ),
      last_value("ash_template.shared_reading.keys",
        event_name: [:ash_template, :shared_reading, :kind],
        measurement: :keys,
        tags: [:kind]
      ),
      last_value("ash_template.shared_reading.table.bytes",
        event_name: [:ash_template, :shared_reading, :table],
        measurement: :bytes
      ),
      counter("ash_template.shared_reading.refused.total",
        event_name: [:ash_template, :shared_reading, :refused],
        tags: [:kind, :reason]
      ),
      counter("ash_template.shared_reading.woken.total",
        event_name: [:ash_template, :shared_reading, :woken],
        tags: [:kind]
      ),
      last_value("vm.memory.total.bytes", event_name: [:vm, :memory], measurement: :total),
      last_value("vm.memory.processes.bytes",
        event_name: [:vm, :memory],
        measurement: :processes
      ),
      last_value("vm.memory.binary.bytes", event_name: [:vm, :memory], measurement: :binary),
      last_value("vm.memory.ets.bytes", event_name: [:vm, :memory], measurement: :ets),
      last_value("vm.memory.code.bytes", event_name: [:vm, :memory], measurement: :code),
      last_value("vm.memory.atom.bytes", event_name: [:vm, :memory], measurement: :atom),
      last_value("vm.total_run_queue_lengths.total"),
      last_value("vm.total_run_queue_lengths.cpu"),
      last_value("vm.system_counts.process_count"),
      last_value("vm.system_counts.atom_count"),
      last_value("vm.system_counts.port_count"),
      counter("health.wallet_send_failures.total",
        event_name: [:ash_template, :wallet, :failure],
        tags: [:flow, :reason],
        description: "Wallet presses the browser reported as not sent or not confirmed"
      )
    ]
  end
end
