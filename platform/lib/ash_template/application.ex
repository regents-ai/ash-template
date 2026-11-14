defmodule AshTemplate.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    # Every outbound TLS connection trusts castore's list, not the operating
    # system's: castore drops a compromised root as soon as Mozilla does, which a
    # Debian image can lag by weeks. Req, Finch and Mint read this list through
    # `:public_key.cacerts_get/0`, so it is loaded before anything connects.
    :ok = :public_key.cacerts_load(CAStore.file_path())
    # The Claude connector stays off until its one switch turns it on
    # (config/runtime.exs); these only check and store its settings.
    :ok = RegentOAuth.configure(AshTemplate.OAuth)
    :ok = RegentMCPAgents.configure!()
    :ok = RegentHttp.UnexpectedFailure.attach_jobs()
    :ok = RegentHttp.ErrorSaving.attach()
    :ok = AshTemplate.IdleDisconnects.attach()
    :ok = AshTemplateWeb.LiveCrashes.attach()
    :ok = AshTemplateWeb.VisitLog.Events.attach()
    :ok = AshTemplate.Health.attach()
    # Visit lines' own handler (config/runtime.exs), and the default handler leaves them to it.
    :ok = Logger.add_handlers(:ash_template)
    :ok = :logger.add_handler_filter(:default, :visits, AshTemplateWeb.VisitLog.default_filter())

    serving? = Phoenix.Endpoint.server?(:ash_template, AshTemplateWeb.Endpoint)

    children =
      [
        AshTemplateWeb.Telemetry,
        AshTemplate.Accounts.RequestRateLimiter,
        {Task.Supervisor, name: AshTemplate.SiteTools.Reads},
        AshTemplate.SiteTools,
        AshTemplate.Repo,
        # The payment service's connections, after the repository its records use.
        RegentPayments.Supervisor,
        {Phoenix.PubSub, name: AshTemplate.PubSub},
        AshTemplateWeb.Presence,
        # The figures every visitor sees alike, then the readers that keep them.
        # Each reader stores its first reading as it starts, so every key is
        # there before the endpoint below serves a page.
        AshTemplate.SharedReading,
        AshTemplate.Agents.ActivityReading,
        # The wallet of each connected app's own identity, asked for once.
        AshTemplate.Agents.HostedAddress,
        # Each agent's reading for an open account menu, unlinked from the page.
        {Task.Supervisor, name: AshTemplate.Agents.Reads},
        # The chain is read, rooms counted and the Points board read only where
        # pages are served, so a task or a test never calls a node or reads the
        # database before it asks to.
        if(serving?, do: AshTemplate.ChainHead.children()),
        if(serving?, do: AshTemplate.Rooms.Activity),
        if(serving?, do: AshTemplate.Points.Board),
        # After PubSub: a pairing made or ended on any Regent site reaches the
        # pages showing it.
        AshTemplate.SharedChanges,
        {Oban, oban(Application.fetch_env!(:ash_template, Oban))},
        AshTemplateWeb.Live.OpenPages,
        # Counts this machine's open agent feeds.
        AshTemplateWeb.FeedController,
        AshTemplateWeb.Telemetry.site_poller(),
        AshTemplateWeb.Endpoint,
        # Metrics are served beside the site, never by a process that only runs a task.
        if(serving?, do: AshTemplateWeb.Metrics)
      ]
      |> List.flatten()
      |> Enum.reject(&is_nil/1)

    Supervisor.start_link(children, strategy: :one_for_one, name: AshTemplate.Supervisor)
  end

  @doc """
  Oban's settings with AshOban's sweep for every trigger in the site's domains. A
  machine that runs no queue (`queues: false`, config/runtime.exs) runs none of the
  triggers' jobs, so their queues need not be there.
  """
  def oban(settings) do
    AshOban.config(Application.fetch_env!(:ash_template, :ash_domains), settings,
      require?: settings[:queues] != false
    )
  end

  @impl true
  def config_change(changed, _new, removed) do
    AshTemplateWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
