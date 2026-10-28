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
    :ok = RegentOAuth.configure(AshTemplate.OAuth)
    :ok = AshTemplateWeb.UnexpectedFailure.attach_jobs()
    :ok = AshTemplate.IdleDisconnects.attach()
    :ok = AshTemplateWeb.VisitLog.Events.attach()

    children =
      [
        AshTemplateWeb.Telemetry,
        AshTemplate.Accounts.RequestRateLimiter,
        {Task.Supervisor, name: AshTemplate.SiteTools.Reads},
        AshTemplate.SiteTools,
        AshTemplate.Repo,
        if(RegentOAuth.enabled?(), do: RegentOAuth.Repo),
        # The payment service's connections, after the repository its records use.
        RegentPayments.Supervisor,
        {Phoenix.PubSub, name: AshTemplate.PubSub},
        AshTemplateWeb.Presence,
        # The figures every visitor sees alike, then the readers that keep them.
        # Each reader stores its first reading as it starts, so every key is
        # there before the endpoint below serves a page.
        AshTemplate.SharedReading,
        AshTemplate.Agents.ActivityReading,
        # Each agent's reading for an open side panel, unlinked from the page.
        {Task.Supervisor, name: AshTemplate.Agents.Reads},
        chain_head_children(),
        room_activity_child(),
        # After PubSub: a Credits balance changed or a pairing made or ended on
        # any Regent site reaches the pages showing it.
        AshTemplate.SharedChanges,
        {Oban, oban_config()},
        AshTemplateWeb.Telemetry.site_poller(),
        AshTemplateWeb.Live.OpenPages,
        AshTemplateWeb.Endpoint,
        metrics_child()
      ]
      |> List.flatten()
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
    if serving?(), do: AshTemplateWeb.Metrics
  end

  # The chain is read only where pages are served, so a task or a test never
  # calls a node.
  defp chain_head_children do
    if serving?(), do: AshTemplate.ChainHead.children(), else: []
  end

  # Rooms are counted only where pages are served, so a task or a test never
  # reads the database before it asks to.
  defp room_activity_child do
    if serving?(), do: AshTemplate.Rooms.Activity
  end

  defp serving?, do: Phoenix.Endpoint.server?(:ash_template, AshTemplateWeb.Endpoint)
end
