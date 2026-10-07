defmodule AshTemplate.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    AshTemplate.JobsRunning.attach()

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

  # AshOban adds a queue and a sweep for every trigger in the site's domains and
  # in Regent Credits, whose purchase checks run on this site's Oban.
  defp oban_config do
    AshOban.config(
      Application.fetch_env!(:ash_template, :ash_domains) ++ [RegentCredits],
      Application.fetch_env!(:ash_template, Oban)
    )
  end

  # Metrics are served beside the site, never by a process that only runs a task.
  defp metrics_child do
    if Phoenix.Endpoint.server?(:ash_template, AshTemplateWeb.Endpoint),
      do: AshTemplateWeb.Metrics
  end
end
