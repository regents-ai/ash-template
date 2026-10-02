defmodule AshTemplate.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children =
      [
        AshTemplateWeb.Telemetry,
        AshTemplate.Accounts.RequestRateLimiter,
        database_child(),
        {Phoenix.PubSub, name: AshTemplate.PubSub},
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

  defp database_child do
    if Application.get_env(:ash_template, :database_startup_enabled, false), do: AshTemplate.Repo
  end

  # Metrics are served beside the site, never by a process that only runs a task.
  defp metrics_child do
    if Phoenix.Endpoint.server?(:ash_template, AshTemplateWeb.Endpoint),
      do: AshTemplateWeb.Metrics
  end
end
