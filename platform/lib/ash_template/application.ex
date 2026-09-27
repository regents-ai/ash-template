defmodule AshTemplate.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children =
      [
        AshTemplateWeb.Telemetry,
        {AshTemplate.Accounts.RequestRateLimiter, []},
        database_child(),
        {Phoenix.PubSub, name: AshTemplate.PubSub},
        # Start a worker by calling: AshTemplate.Worker.start_link(arg)
        # {AshTemplate.Worker, arg},
        # Start to serve requests, typically the last entry
        AshTemplateWeb.Endpoint,
        metrics_child()
      ]
      |> Enum.reject(&is_nil/1)

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: AshTemplate.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp database_child do
    if Application.get_env(:ash_template, :database_startup_enabled, false),
      do: AshTemplate.Repo
  end

  # Metrics are served beside the site, never by a process that only runs a task.
  defp metrics_child do
    if Phoenix.Endpoint.server?(:ash_template, AshTemplateWeb.Endpoint),
      do: AshTemplateWeb.Metrics
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    AshTemplateWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
