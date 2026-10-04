defmodule AshTemplateWeb.Telemetry do
  @moduledoc """
  The site's measurements, as `:telemetry` events, and their Prometheus export on
  the private metrics listener (`AshTemplateWeb.Metrics`). Fly Sentinel's site
  watch reads the three `health.*` series from every site: Ecto's
  `[:ash_template, :repo, :query]` (`queue_time` is the wait for a connection),
  `[:ash_template, :chain, :failure]` for each chain request that got no answer
  (`AshTemplate.ChainClient`), and `[:ash_template, :wallet, :failure]` for each
  press the browser reported as not sent or not confirmed (`wallet_failed/2`).
  Background jobs report each run's outcome and time from Oban's own events.
  Each question asked of Jev (`RegentJev`, `[:regent_jev, :decide]`) is counted
  by outcome, with its tokens, what OpenRouter charged and how long it took.
  """

  import Telemetry.Metrics

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
      counter("health.wallet_send_failures.total",
        event_name: [:ash_template, :wallet, :failure],
        tags: [:flow, :reason],
        description: "Wallet presses the browser reported as not sent or not confirmed"
      )
    ]
  end
end
