defmodule AshTemplate.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children =
      [
        AshTemplateWeb.Telemetry,
        AshTemplate.Accounts.RequestRateLimiter,
        AshTemplate.Repo,
        {Phoenix.PubSub, name: AshTemplate.PubSub},
        AshTemplateWeb.Presence,
        # After the repository and PubSub: a Credits balance changed on any
        # Regent site reaches the pages showing it.
        RegentCredits.Listener,
        # A pairing made or ended anywhere reaches the person's account page.
        RegentAgents.Listener,
        {Oban, oban_config()},
        AshTemplateWeb.Endpoint,
        metrics_child()
      ]
      |> Enum.reject(&is_nil/1)

    Supervisor.start_link(children, strategy: :one_for_one, name: AshTemplate.Supervisor)
  end

  @impl true
  def config_change(changed, _new, removed) do
    AshTemplateWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  # AshOban adds a sweep for every trigger in the site's domains. Regents alone
  # runs Regent Credits' purchase checks and Base deposit reads, for every site:
  # they share one ledger, so a second site's sweep would only repeat its reads.
  defp oban_config do
    AshOban.config(
      Application.fetch_env!(:ash_template, :ash_domains),
      Application.fetch_env!(:ash_template, Oban)
    )
  end

  # Metrics are served beside the site, never by a process that only runs a task.
  defp metrics_child do
    if Phoenix.Endpoint.server?(:ash_template, AshTemplateWeb.Endpoint),
      do: AshTemplateWeb.Metrics
  end
end
