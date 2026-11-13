defmodule AshTemplate.DatabaseConfigTest do
  use ExUnit.Case, async: true

  alias AshTemplate.DatabaseConfig

  @serving "postgres://serving:secret@direct.standin0cluster.flympg.net/regents_prod"
  @env %{
    "ASH_TEMPLATE_DEPLOYMENT_ROLE" => "production",
    "ASH_TEMPLATE_DATABASE_CLUSTER_ID" => "standin0cluster",
    "DATABASE_POOLED_URL" => @serving
  }

  defp getenv(name), do: Map.get(@env, name)

  test "production serves and listens on the direct address with the same login" do
    serving = DatabaseConfig.runtime_config!(:prod, &getenv/1)
    listening = DatabaseConfig.notifications_config!(:prod, &getenv/1)

    assert serving[:url] == @serving
    assert serving[:pool_size] == 5
    assert serving[:max_lifetime] == 540_000..600_000
    assert serving[:ssl][:verify] == :verify_peer
    assert serving[:ssl][:server_name_indication] == ~c"direct.standin0cluster.flympg.net"

    assert serving[:parameters] == [
             application_name: "ash-template-web",
             statement_timeout: "15000",
             lock_timeout: "5000",
             idle_in_transaction_session_timeout: "15000"
           ]

    # Postgrex.Notifications reads connection keys, never a URL.
    refute Keyword.has_key?(listening, :url)
    assert listening[:hostname] == "direct.standin0cluster.flympg.net"
    assert listening[:database] == "regents_prod"
    assert listening[:username] == "serving"
    assert listening[:password] == "secret"
    assert listening[:port] == 5432
    assert listening[:ssl][:verify] == :verify_peer
    assert listening[:ssl][:server_name_indication] == ~c"direct.standin0cluster.flympg.net"
    assert listening[:auto_reconnect]
    assert listening[:parameters] == [application_name: "ash-template-listen"]

    for pool_only <- [:pool_size, :max_lifetime],
        do: refute(Keyword.has_key?(listening, pool_only))
  end

  test "production admits the direct address of the cluster it names alone, for serving and for release commands" do
    release_target = %{
      "ASH_TEMPLATE_DEPLOYMENT_ROLE" => "production",
      "ASH_TEMPLATE_DATABASE_TARGET_MODE" => "production",
      "ASH_TEMPLATE_DATABASE_CLUSTER_ID" => "standin0cluster"
    }

    migrating = Map.put(release_target, "DATABASE_DIRECT_URL", @serving)
    assert DatabaseConfig.release_config!(&Map.get(migrating, &1))[:url] == @serving

    for url <- [
          "postgres://serving:secret@other.flympg.net/regents_prod",
          "postgres://serving:secret@direct.othercluster.flympg.net/regents_prod",
          "postgres://serving:secret@direct.standin0cluster.flympg.net:6543/regents_prod",
          "postgres://serving:secret@direct.standin0cluster.flympg.net/regents_prod?ssl=false",
          "postgres://serving:secret@direct.standin0cluster.flympg.net./regents_prod"
        ] do
      serving = Map.put(release_target, "DATABASE_POOLED_URL", url)
      release = Map.put(release_target, "DATABASE_DIRECT_URL", url)

      assert_raise RuntimeError, ~r/approved target/, fn ->
        DatabaseConfig.runtime_config!(:prod, &Map.get(serving, &1))
      end

      assert_raise RuntimeError, ~r/approved target/, fn ->
        DatabaseConfig.release_config!(&Map.get(release, &1))
      end
    end

    # With no cluster named, production neither serves nor migrates.
    unnamed = Map.delete(@env, "ASH_TEMPLATE_DATABASE_CLUSTER_ID")
    assert_raise RuntimeError, fn -> DatabaseConfig.runtime_config!(:prod, &Map.get(unnamed, &1)) end
  end
end
