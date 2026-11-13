defmodule AshTemplate.RemoteDatabaseTest do
  # A developer's machine on the remote database runs none of the site's jobs and
  # answers only itself: the development settings, read as the development server
  # reads them, with and without the remote database.
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  @remote %{
    "ASH_TEMPLATE_DATABASE_CLUSTER_ID" => "dzx6qo6xqzvojpv5",
    "ASH_TEMPLATE_DATABASE_CLUSTER_NAME" => "regents-platform-prod",
    "DATABASE_POOLED_URL" => "postgres://developer:stand-in@db.example.test/ash_template"
  }
  @local %{"ASH_TEMPLATE_DATABASE_CLUSTER_ID" => nil, "ASH_TEMPLATE_DATABASE_CLUSTER_NAME" => nil}

  test "on the remote database the server starts no queue and no Oban plugin and leads nothing" do
    remote = jobs(@remote)
    assert remote.queues == []
    assert remote.plugins == []
    assert remote.peer == {Oban.Peers.Isolated, [leader?: false]}

    local = jobs(@local)
    assert Keyword.has_key?(local.queues, :default)
    assert Enum.any?(local.plugins, &match?({Oban.Cron, _options}, &1))
    assert local.peer == {Oban.Peers.Database, []}
  end

  test "on the remote database the server refuses to listen beyond this machine" do
    endpoint = Application.fetch_env!(:ash_template, AshTemplateWeb.Endpoint)
    on_exit(fn -> Application.put_env(:ash_template, AshTemplateWeb.Endpoint, endpoint) end)
    open = Keyword.put(endpoint, :http, ip: {0, 0, 0, 0}, port: 4002)
    Application.put_env(:ash_template, AshTemplateWeb.Endpoint, open)

    assert_raise RuntimeError, fn -> development(@remote) end
    assert development(@local)[AshTemplate.Repo][:hostname] == "127.0.0.1"
  end

  # The Oban the application starts with these settings.
  defp jobs(environment),
    do:
      environment
      |> development()
      |> Keyword.fetch!(Oban)
      |> AshTemplate.Application.oban()
      |> Oban.Config.new()

  # The site's development settings with these in the environment (nil for one that is
  # not set), the environment as it was afterwards.
  defp development(environment) do
    before = Map.new(environment, fn {name, _value} -> {name, System.get_env(name)} end)
    put_env(environment)

    try do
      compiled = Config.Reader.read!(config("config.exs"), env: :dev, target: :host)

      {runtime, _log} =
        with_log(fn -> Config.Reader.read!(config("runtime.exs"), env: :dev, target: :host) end)

      Config.Reader.merge(compiled, runtime)[:ash_template]
    after
      put_env(before)
    end
  end

  defp config(file), do: Path.expand("../../config/#{file}", __DIR__)

  defp put_env(environment) do
    for {name, value} <- environment,
        do: if(value, do: System.put_env(name, value), else: System.delete_env(name))
  end
end
