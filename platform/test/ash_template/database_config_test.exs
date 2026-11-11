defmodule AshTemplate.DatabaseConfigTest do
  use ExUnit.Case, async: true

  alias AshTemplate.DatabaseConfig

  @serving "postgres://serving:secret@direct.dzx6qo6xqzvojpv5.flympg.net/regents_prod"
  @env %{"ASH_TEMPLATE_DEPLOYMENT_ROLE" => "production", "DATABASE_POOLED_URL" => @serving}

  defp getenv(name), do: Map.get(@env, name)

  test "production serves and listens on the direct address with the same login" do
    serving = DatabaseConfig.runtime_config!(:prod, &getenv/1)
    listening = DatabaseConfig.notifications_config!(:prod, &getenv/1)

    assert serving[:url] == @serving
    assert serving[:pool_size] == 5
    assert serving[:max_lifetime] == 540_000..600_000
    assert serving[:ssl][:verify] == :verify_peer
    assert serving[:ssl][:server_name_indication] == ~c"direct.dzx6qo6xqzvojpv5.flympg.net"

    assert serving[:parameters] == [
             application_name: "ash-template-web",
             statement_timeout: "15000",
             lock_timeout: "5000",
             idle_in_transaction_session_timeout: "15000"
           ]

    # Postgrex.Notifications reads connection keys, never a URL.
    refute Keyword.has_key?(listening, :url)
    assert listening[:hostname] == "direct.dzx6qo6xqzvojpv5.flympg.net"
    assert listening[:database] == "regents_prod"
    assert listening[:username] == "serving"
    assert listening[:password] == "secret"
    assert listening[:port] == 5432
    assert listening[:ssl][:verify] == :verify_peer
    assert listening[:ssl][:server_name_indication] == ~c"direct.dzx6qo6xqzvojpv5.flympg.net"
    assert listening[:auto_reconnect]
    assert listening[:parameters] == [application_name: "ash-template-listen"]

    for pool_only <- [:pool_size, :max_lifetime],
        do: refute(Keyword.has_key?(listening, pool_only))
  end
end
