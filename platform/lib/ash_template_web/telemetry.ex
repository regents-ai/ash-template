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
  A site's chain event reader reports each pass with `[:ash_template, :indexer, :lag]`:
  `blocks` between the head it follows and the last block it has read, for its
  fixed `indexer` name and `chain_id` (the chain-events skill). A site that sends
  from its own wallet names, as `unconfirmed_sends` in
  `config :ash_template, AshTemplateWeb.Telemetry`, the function that answers each
  of its fixed sending flows with when its oldest signed, unconfirmed transaction
  was signed, or nil; every ten seconds `[:ash_template, :wallet, :unconfirmed_oldest]`
  carries that `age_ms` for each `flow`, 0 when none waits. The template reads no
  chain events and sends from no wallet of its own, so neither is reported here.
  The engine's memory, run queues and process counts come from telemetry_poller's
  default poller, every 10 seconds (`config/config.exs`).
  Each question asked of Jev (`RegentJev`, `[:regent_jev, :decide]`) is counted
  by outcome, with its tokens, what OpenRouter charged and how long it took.
  The figures every visitor sees alike (`AshTemplate.SharedReading`) report, for
  each kind, how many keys are held, how many have never been read, how long ago
  the oldest was read, each reading that could not be taken and each one refused.

  The reporter, Peep, keeps a fixed set of counters for each series and holds
  no observation between scrapes. It adds each observation to a running total
  as a whole number, so times are measured in whole microseconds and Jev's
  charges in billionths of a dollar, and every total stays exact.
  """

  import Ecto.Query, only: [from: 2]
  import Telemetry.Metrics

  alias AshTemplateWeb.Telemetry.Buckets

  require Logger

  # The reasons the wallet hook reports (`Failure` in send_step.ts). Only these
  # are counted, so a label never holds whatever a browser chose to send.
  @wallet_failures ~w(step_unknown wallet_unavailable network_mismatch wallet_declined insufficient_funds send_unconfirmed)

  @reporter :ash_template_prometheus

  def child_spec(_arg) do
    Peep.child_spec(metrics: metrics(), name: @reporter)
  end

  @doc "Every measurement as Prometheus text, as the metrics listener answers it."
  def scrape,
    do: @reporter |> Peep.get_all_metrics() |> Peep.Prometheus.export() |> IO.iodata_to_binary()

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
       measurements:
         [
           {AshTemplate.SharedReading, :measure, []},
           {__MODULE__, :oldest_unfinished_jobs, []}
         ] ++ unconfirmed_sends_step(),
       period: 10_000,
       name: :ash_template_site_poller}

  # Only a site that sends from its own wallet names its query. Without one the
  # age is never published, so Sentinel never reads a steady 0 that only means
  # nothing was asked.
  defp unconfirmed_sends_step do
    case Application.get_env(:ash_template, __MODULE__)[:unconfirmed_sends] do
      nil -> []
      query -> [{__MODULE__, :oldest_unconfirmed_sends, [query]}]
    end
  end

  # The poller drops for good a measurement that raises or exits, and the row
  # would then keep its last number. So whatever stops this tick (a database
  # that cannot answer, a queue too busy to say whether it runs, Oban or the
  # repo restarting) is logged and skipped; the next tick measures again.
  @doc false
  def oldest_unfinished_jobs do
    measure_oldest_unfinished_jobs()
  rescue
    error -> not_measured("background job age", Exception.message(error))
  catch
    :exit, reason -> not_measured("background job age", Exception.format_exit(reason))
  end

  # The site's query, `{module, function, args}`, answers `{flow, signed_at}`
  # for each of its sending flows, `signed_at` nil when nothing waits. Logged
  # and skipped like the job age.
  @doc false
  def oldest_unconfirmed_sends({module, function, args}) do
    now = DateTime.utc_now()

    for {flow, signed_at} <- apply(module, function, args) do
      age_ms =
        case signed_at do
          nil -> 0
          signed_at -> DateTime.diff(now, signed_at, :millisecond)
        end

      :telemetry.execute([:ash_template, :wallet, :unconfirmed_oldest], %{age_ms: age_ms}, %{
        flow: flow
      })
    end

    :ok
  rescue
    error -> not_measured("unconfirmed send age", Exception.message(error))
  catch
    :exit, reason -> not_measured("unconfirmed send age", Exception.format_exit(reason))
  end

  defp not_measured(what, why), do: Logger.warning("#{what} not measured: #{why}")

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
      distribution("health.db_queue.microseconds",
        event_name: [:ash_template, :repo, :query],
        measurement: :queue_time,
        unit: {:native, :microsecond},
        description: "Microseconds a query waited for a database connection",
        reporter_options: [
          peep_bucket_calculator: Buckets,
          buckets:
            [1_000, 5_000, 10_000, 25_000, 50_000, 100_000, 250_000, 500_000] ++
              [1_000_000, 2_500_000, 5_000_000]
        ]
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
      last_value("health.indexer.lag.blocks",
        event_name: [:ash_template, :indexer, :lag],
        measurement: :blocks,
        tags: [:indexer, :chain_id],
        description:
          "Blocks between the chain head a reader follows and the last block it has read"
      ),
      counter("health.indexer.passes.total",
        event_name: [:ash_template, :indexer, :lag],
        tags: [:indexer, :chain_id],
        description: "Passes each chain reader made"
      ),
      last_value("health.wallet_unconfirmed_oldest.seconds",
        event_name: [:ash_template, :wallet, :unconfirmed_oldest],
        measurement: :age_ms,
        unit: {:millisecond, :second},
        tags: [:flow],
        description:
          "Age of the oldest transaction the site's own wallet signed that is not yet confirmed"
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
      distribution("ash_template.jobs.duration.microseconds",
        event_name: [:oban, :job, :stop],
        measurement: :duration,
        unit: {:native, :microsecond},
        tags: [:queue, :worker],
        reporter_options: [
          peep_bucket_calculator: Buckets,
          buckets: [
            10_000,
            50_000,
            100_000,
            500_000,
            1_000_000,
            5_000_000,
            15_000_000,
            60_000_000
          ]
        ]
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
      # The dollars are a histogram, so its `_sum` series is the running total.
      # Jev reports a float of dollars; billionths keep that total exact.
      distribution("ash_template.jev.cost.nanodollars",
        event_name: [:regent_jev, :decide],
        measurement: &round(&1.cost_usd * 1_000_000_000),
        description: "Billionths of a US dollar OpenRouter charged per Jev question",
        reporter_options: [
          peep_bucket_calculator: Buckets,
          buckets: [10_000, 100_000, 1_000_000, 10_000_000, 100_000_000]
        ]
      ),
      distribution("ash_template.jev.duration.microseconds",
        event_name: [:regent_jev, :decide],
        measurement: :duration,
        unit: {:native, :microsecond},
        tags: [:outcome],
        reporter_options: [
          peep_bucket_calculator: Buckets,
          buckets:
            [100_000, 250_000, 500_000, 1_000_000, 2_500_000, 5_000_000, 10_000_000] ++
              [30_000_000]
        ]
      ),
      last_value("health.shared_reading.oldest.seconds",
        event_name: [:ash_template, :shared_reading, :kind],
        measurement: :oldest_seconds,
        tags: [:kind],
        description: "Seconds since the oldest shared reading of each kind was read"
      ),
      last_value("health.shared_reading.late.keys",
        event_name: [:ash_template, :shared_reading, :kind],
        measurement: :late,
        tags: [:kind],
        description: "Keys of the kind last read longer ago than the kind's producer should allow"
      ),
      last_value("health.shared_reading.never_read.keys",
        event_name: [:ash_template, :shared_reading, :kind],
        measurement: :never_read,
        tags: [:kind],
        description: "Keys of the kind that have had no reading since the site started"
      ),
      counter("health.open_pages.refused.total",
        event_name: [:ash_template, :open_pages, :refused],
        description: "Live pages refused because their address already held the limit open"
      ),
      counter("health.agent_activity_unread.total",
        event_name: [:ash_template, :agents, :activity_unread],
        tags: [:reason],
        description: "Agents' activity reads from the sign-in service that gave no reading"
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
