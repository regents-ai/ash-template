defmodule AshTemplateWeb.Telemetry do
  @moduledoc """
  The site's measurements, as `:telemetry` events, and their Prometheus export
  on the private metrics listener (`AshTemplateWeb.Metrics`). The three
  `health.*` series are the ones Fly Sentinel's site watch reads from every site:

    * `[:ash_template, :repo, :query]`: Ecto's own event per query, whose
      `queue_time` is the wait for a database connection.
    * `[:ash_template, :chain, :failure]`: `count` 1 for each chain request
      that got no answer, by `method`, `class`, `chain_id` and `scope`
      (`AshTemplate.ChainClient`).
    * `[:ash_template, :wallet, :failure]`: `count` 1 for each press the
      browser reported as not sent or not confirmed, by `flow` and `reason`
      (`wallet_failed/2`).
  """

  use Supervisor
  import Telemetry.Metrics

  # The reasons the wallet hook reports (`Failure` in send_step.ts). Only these
  # are counted, so a label never holds whatever a browser chose to send.
  @wallet_failures ~w(step_unknown wallet_unavailable network_mismatch wallet_declined insufficient_funds send_unconfirmed)

  def start_link(arg) do
    Supervisor.start_link(__MODULE__, arg, name: __MODULE__)
  end

  @impl true
  def init(_arg) do
    children = [
      {TelemetryMetricsPrometheus.Core,
       metrics: prometheus_metrics(), name: prometheus_reporter(), start_async: false},
      # Telemetry poller will execute the given period measurements
      # every 10_000ms. Learn more here: https://hexdocs.pm/telemetry_metrics
      {:telemetry_poller, measurements: periodic_measurements(), period: 10_000}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  def prometheus_reporter, do: :ash_template_prometheus

  def prometheus_metrics do
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
      counter("health.wallet_send_failures.total",
        event_name: [:ash_template, :wallet, :failure],
        tags: [:flow, :reason],
        description: "Wallet presses the browser reported as not sent or not confirmed"
      )
    ]
  end

  @doc """
  Counts one press the browser reported as not sent or not confirmed, for the
  wallet-button component `flow`. A reason the hook never sends is not counted.
  """
  def wallet_failed(flow, reason) when reason in @wallet_failures,
    do:
      :telemetry.execute([:ash_template, :wallet, :failure], %{count: 1}, %{
        flow: flow,
        reason: reason
      })

  def wallet_failed(_flow, _reason), do: :ok

  defp periodic_measurements do
    [
      # A module, function and arguments to be invoked periodically.
      # This function must call :telemetry.execute/3 and a metric must be added above.
      # {AshTemplateWeb, :count_users, []}
    ]
  end
end
