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
  available, running or retrying job in each running `queue`, counted from when
  the job was due to run (its scheduled time, which a retry moves to the next
  attempt), 0 when there is none or none is due yet, every ten seconds. A paused
  queue keeps its jobs waiting on purpose, so it is not measured.
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
  The figures every reader they admit sees alike (`AshTemplate.SharedReading`) report, for
  each kind, how many keys are held, how many have never been read, how long ago
  the oldest was read, the size of each reading offered as a percent of its kind's
  limit, each reading that could not be taken and each one refused.

  The figures that tell one limit from another sit side by side. Each Repo query
  reports both halves, the wait for a connection (`queue_time`) and the query
  itself (`query_time`), tagged by the table it read, and each checkout the pool
  refused is counted; without both halves a pool that is too small cannot be told
  from queries that hold connections too long. Scheduler use is measured over
  one second, every ten seconds, by a poller of its own, beside the run queues. The
  message queue and memory of each process on a hot path, and the count of open
  live pages and open agent feeds, come from the site's poller. LiveView mount,
  handle_params and handle_event times are tagged by view or component module,
  router dispatch by route pattern, and socket connects by result. Each call to
  another service is timed by `service`, a name the site gives each host in its
  own settings (`services/0`); every other host is `other`. The sign-in reads
  (`AshTemplate.Accounts`) are timed and counted from Ash's own read events, by
  resource and action. Every tag is a value the site chooses, never one a client
  sends: each tag value is a series held for the life of the machine.

  The reporter, Peep, keeps a fixed set of counters for each series and holds
  no observation between scrapes. It adds each observation to a running total
  as a whole number, so times are measured in whole microseconds and Jev's
  charges in billionths of a dollar, and every total stays exact.
  """

  use Supervisor

  import Ecto.Query, only: [from: 2]
  import Telemetry.Metrics

  alias AshTemplateWeb.Telemetry.Buckets

  require Logger

  # The reasons the wallet hook reports (`Failure` in send_step.ts). Only these
  # are counted, so a label never holds whatever a browser chose to send.
  @wallet_failures ~w(step_unknown wallet_unavailable network_mismatch wallet_declined insufficient_funds send_unconfirmed sign_unconfirmed)

  @reporter :ash_template_prometheus

  # Times from a millisecond to five seconds, in microseconds.
  @request_buckets [1_000, 5_000, 10_000, 25_000, 50_000, 100_000, 250_000, 500_000] ++
                     [1_000_000, 2_500_000, 5_000_000]

  # The named processes every page view, room message or shared reading passes
  # through: the shared figures, the one listener for other sites' changes, the
  # tools read from other Regent sites, the room presence shard and the visit
  # log's own handler.
  @hot_processes [
    AshTemplate.SharedReading,
    AshTemplate.Notifications,
    AshTemplate.SiteTools,
    AshTemplateWeb.Presence_shard0,
    :logger_std_h_visits
  ]

  # The unnamed ones, found by their child id under the application's supervisor.
  @hot_children [AshTemplate.Rooms.Activity, AshTemplate.Points.Board]

  def start_link(arg), do: Supervisor.start_link(__MODULE__, arg, name: __MODULE__)

  @impl true
  def init(_arg) do
    children = [
      {Peep, metrics: metrics(), name: @reporter},
      # Reading scheduler use takes a second, so it has a poller of its own and
      # never holds up the others.
      {:telemetry_poller,
       measurements: [{__MODULE__, :scheduler_use, []}],
       period: 10_000,
       name: :ash_template_scheduler_poller}
    ]

    Supervisor.init(children, strategy: :one_for_one)
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

  @doc """
  The poller for the measurements the site takes itself, started after Oban and
  the registries of open pages and feeds it counts.
  """
  def site_poller do
    # Only a site that sends from its own wallet names its query. Without one the
    # age is never published, so Sentinel never reads a steady 0 that only means
    # nothing was asked.
    unconfirmed_sends =
      case Application.get_env(:ash_template, __MODULE__)[:unconfirmed_sends] do
        nil -> []
        query -> [{__MODULE__, :oldest_unconfirmed_sends, [query]}]
      end

    {:telemetry_poller,
     measurements:
       [
         {AshTemplate.SharedReading, :measure, []},
         {__MODULE__, :oldest_unfinished_jobs, []},
         {__MODULE__, :open, []},
         {__MODULE__, :hot_children, []}
       ] ++ hot_processes() ++ unconfirmed_sends,
     period: 10_000,
     name: :ash_template_site_poller}
  end

  # The poller drops for good a measurement that raises or exits, and the row
  # would then keep its last number. So whatever stops this tick (a database
  # that cannot answer, a queue too busy to say whether it runs, Oban or the
  # repo restarting) is logged and skipped; the next tick measures again.
  # Only running queues are measured: a paused queue holds its jobs on purpose,
  # and its age would only grow. Where no queue runs (tests), nothing is read.
  @doc false
  def oldest_unfinished_jobs do
    case for %{queue: queue, paused: false} <- Oban.check_all_queues(), do: queue do
      [] -> :ok
      running -> report_oldest(running)
    end
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

  @doc false
  def scheduler_use do
    [{:total, use, _percent} | _each_scheduler] = :scheduler.utilization(1)
    :telemetry.execute([:ash_template, :vm, :scheduler_use], %{percent: round(use * 100)})
  end

  @doc false
  def open do
    :telemetry.execute([:ash_template, :open], %{
      pages: Registry.count(AshTemplateWeb.Live.OpenPages),
      feeds: Registry.count(AshTemplateWeb.OpenFeeds)
    })
  end

  # A process that has just stopped answers nil and is skipped this tick.
  @doc false
  def hot_children do
    for {id, pid, _type, _modules} <- Supervisor.which_children(AshTemplate.Supervisor),
        id in @hot_children,
        info = is_pid(pid) && Process.info(pid, [:message_queue_len, :memory]) do
      :telemetry.execute([:ash_template, :process], Map.new(info), %{name: id})
    end

    :ok
  end

  defp hot_processes do
    for name <- @hot_processes do
      {:process_info,
       name: name, event: [:ash_template, :process], keys: [:message_queue_len, :memory]}
    end
  end

  # A statement no table is named for (a transaction's begin and commit, the
  # health check, Oban's notices) is `none`.
  defp table(%{source: source}), do: %{source: source || "none"}

  # The services the site calls, by host, from its own settings. Any other host,
  # such as the address of an OAuth client's document or an ENS picture, which a
  # visitor names, is `other`.
  defp services do
    [
      chain:
        Map.values(Application.fetch_env!(:ash_template, :chain_nodes)) ++
          List.wrap(Application.get_env(:ash_template, :ethereum_read_rpc_url)),
      sign_in: [Application.fetch_env!(:regent_agents, :siwa)[:url]],
      model: ["https://openrouter.ai" | List.wrap(Application.get_env(:regent_jev, :endpoint))],
      payments: [Application.fetch_env!(:regent_payments, RegentPayments.Facilitator)[:url]],
      webhook: List.wrap(Application.get_env(:ash_template, :notes_webhook_url))
    ]
    |> Enum.flat_map(fn {service, urls} ->
      for url <- urls, do: {URI.parse(url).host, Atom.to_string(service)}
    end)
    |> Map.new()
  end

  defp report_oldest(running) do
    %{prefix: prefix} = Oban.config()

    oldest =
      from(j in Oban.Job,
        where: j.state in ["available", "executing", "retryable"],
        group_by: j.queue,
        select: {j.queue, min(j.scheduled_at)}
      )
      # Oban's job table has no Ash resource; this only reads it.
      |> AshTemplate.Repo.all(prefix: prefix)
      |> Map.new()

    now = DateTime.utc_now()

    for queue <- running do
      age_ms =
        case oldest[queue] do
          nil -> 0
          # A job waiting for its next attempt is due later than now.
          due_at -> max(DateTime.diff(now, due_at, :millisecond), 0)
        end

      :telemetry.execute([:ash_template, :jobs, :oldest_unfinished], %{age_ms: age_ms}, %{
        queue: queue
      })
    end
  end

  defp metrics do
    services = services()

    [
      counter("ash_template.privy.browser_failure.total", tags: [:reason]),
      counter("ash_template.privy.session_refused.total", tags: [:stage, :reason]),
      counter("ash_template.session_bootstrap.rate_limited.total", tags: [:source]),
      counter("ash_template.session_authority.absent_row.total"),
      counter("ash_template.mcp.auth.total", tags: [:mode, :outcome]),
      distribution("health.db_queue.microseconds",
        event_name: [:ash_template, :repo, :query],
        measurement: :queue_time,
        unit: {:native, :microsecond},
        tags: [:source],
        tag_values: &table/1,
        description: "Microseconds a query waited for a database connection",
        reporter_options: [peep_bucket_calculator: Buckets, buckets: @request_buckets]
      ),
      distribution("ash_template.db_query.microseconds",
        event_name: [:ash_template, :repo, :query],
        measurement: :query_time,
        unit: {:native, :microsecond},
        tags: [:source],
        tag_values: &table/1,
        description: "Microseconds a query held its connection in the database",
        reporter_options: [
          peep_bucket_calculator: Buckets,
          buckets: [100, 500 | @request_buckets]
        ]
      ),
      counter("health.db_checkout_refused.total",
        event_name: [:ash_template, :repo, :query],
        keep: &match?({:error, %DBConnection.ConnectionError{reason: :queue_timeout}}, &1.result),
        description: "Queries the pool gave no connection in time"
      ),
      distribution("ash_template.live_view.mount.microseconds",
        event_name: [:phoenix, :live_view, :mount, :stop],
        measurement: :duration,
        unit: {:native, :microsecond},
        tags: [:view],
        tag_values: &%{view: inspect(&1.socket.view)},
        reporter_options: [peep_bucket_calculator: Buckets, buckets: @request_buckets]
      ),
      distribution("ash_template.live_view.handle_params.microseconds",
        event_name: [:phoenix, :live_view, :handle_params, :stop],
        measurement: :duration,
        unit: {:native, :microsecond},
        tags: [:view],
        tag_values: &%{view: inspect(&1.socket.view)},
        reporter_options: [peep_bucket_calculator: Buckets, buckets: @request_buckets]
      ),
      distribution("ash_template.live_view.handle_event.microseconds",
        event_name: [:phoenix, :live_view, :handle_event, :stop],
        measurement: :duration,
        unit: {:native, :microsecond},
        tags: [:view],
        tag_values: &%{view: inspect(&1.socket.view)},
        reporter_options: [peep_bucket_calculator: Buckets, buckets: @request_buckets]
      ),
      distribution("ash_template.live_component.handle_event.microseconds",
        event_name: [:phoenix, :live_component, :handle_event, :stop],
        measurement: :duration,
        unit: {:native, :microsecond},
        tags: [:component],
        tag_values: &%{component: inspect(&1.component)},
        reporter_options: [peep_bucket_calculator: Buckets, buckets: @request_buckets]
      ),
      distribution("ash_template.router_dispatch.microseconds",
        event_name: [:phoenix, :router_dispatch, :stop],
        measurement: :duration,
        unit: {:native, :microsecond},
        tags: [:route],
        reporter_options: [peep_bucket_calculator: Buckets, buckets: @request_buckets]
      ),
      counter("ash_template.socket_connected.total",
        event_name: [:phoenix, :socket_connected],
        tags: [:result],
        description: "Live socket connects, by whether the socket accepted them"
      ),
      distribution("ash_template.outside_call.microseconds",
        event_name: [:finch, :request, :stop],
        measurement: :duration,
        unit: {:native, :microsecond},
        tags: [:service, :outcome],
        tag_values:
          &%{
            service: Map.get(services, &1.request.host, "other"),
            outcome: elem(&1.result, 0)
          },
        description: "Microseconds each call to another service took",
        reporter_options: [
          peep_bucket_calculator: Buckets,
          buckets: @request_buckets ++ [10_000_000, 30_000_000]
        ]
      ),
      distribution("ash_template.accounts.read.microseconds",
        event_name: [:ash, :accounts, :read, :stop],
        measurement: :duration,
        unit: {:native, :microsecond},
        tags: [:resource, :action],
        tag_values: &%{resource: &1.resource_short_name, action: &1.action},
        description: "Sign-in and account reads, including each check of a signed-in page",
        reporter_options: [peep_bucket_calculator: Buckets, buckets: @request_buckets]
      ),
      last_value("vm.scheduler_use.percent",
        event_name: [:ash_template, :vm, :scheduler_use],
        measurement: :percent,
        description: "Percent of the schedulers' time spent working, over one second"
      ),
      last_value("ash_template.process.message_queue.length",
        event_name: [:ash_template, :process],
        measurement: :message_queue_len,
        tags: [:name],
        tag_values: &%{name: inspect(&1.name)},
        description: "Messages waiting in each process on a hot path"
      ),
      last_value("ash_template.process.memory.bytes",
        event_name: [:ash_template, :process],
        measurement: :memory,
        tags: [:name],
        tag_values: &%{name: inspect(&1.name)}
      ),
      last_value("ash_template.open.pages",
        event_name: [:ash_template, :open],
        measurement: :pages,
        description: "Live pages open on this machine"
      ),
      last_value("ash_template.open.feeds",
        event_name: [:ash_template, :open],
        measurement: :feeds,
        description: "Agent feeds open on this machine"
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
          "Age of the oldest unfinished background job in the queue, counted from when it was due"
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
      last_value("health.shared_reading.size.percent",
        event_name: [:ash_template, :shared_reading, :size],
        measurement: &div(&1.bytes * 100, &1.limit),
        tags: [:kind],
        description:
          "Size of the last reading each kind was offered, as a percent of the kind's limit; " <>
            "past 100 it is refused and the last one held stays"
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
