defmodule AshTemplate.DatabaseConfigTest do
  use ExUnit.Case, async: true

  alias AshTemplate.DatabaseConfig

  @serving "postgres://serving:secret@pgbouncer.dzx6qo6xqzvojpv5.flympg.net/regents_prod"
  @env %{"ASH_TEMPLATE_DEPLOYMENT_ROLE" => "production", "DATABASE_POOLED_URL" => @serving}

  defp getenv(name), do: Map.get(@env, name)

  test "production serves through the pooler and listens on the direct address with the same login" do
    serving = DatabaseConfig.runtime_config!(:prod, &getenv/1)
    listening = DatabaseConfig.notifications_config!(:prod, &getenv/1)

    assert serving[:url] == @serving
    assert serving[:prepare] == :unnamed
    assert serving[:pool_size] == 5
    assert serving[:max_lifetime] == 540_000..600_000
    assert serving[:ssl][:server_name_indication] == ~c"pgbouncer.dzx6qo6xqzvojpv5.flympg.net"

    # Postgrex.Notifications reads connection keys, never a URL.
    refute Keyword.has_key?(listening, :url)
    assert listening[:hostname] == "direct.dzx6qo6xqzvojpv5.flympg.net"
    assert listening[:database] == "regents_prod"
    assert listening[:username] == "serving"
    assert listening[:password] == "secret"
    assert listening[:port] == 5432
    assert listening[:ssl][:server_name_indication] == ~c"direct.dzx6qo6xqzvojpv5.flympg.net"
    assert listening[:auto_reconnect]
    assert listening[:parameters] == [application_name: "ash-template-listen"]

    for pooled_only <- [:prepare, :pool_size, :max_lifetime],
        do: refute(Keyword.has_key?(listening, pooled_only))
  end

  test "the pooler is trusted through the cluster's own authority under its internal name only" do
    ssl = DatabaseConfig.runtime_config!(:prod, &getenv/1)[:ssl]
    accepts = ssl[:customize_hostname_check][:match_fun]

    assert ssl[:verify] == :verify_peer
    assert [{:Certificate, authority, :not_encrypted}] =
             ssl[:cacertfile] |> File.read!() |> :public_key.pem_decode()

    assert :public_key.pkix_is_self_signed(authority)

    reference = {:dns_id, ~c"pgbouncer.dzx6qo6xqzvojpv5.flympg.net"}
    assert accepts.(reference, {:dNSName, ~c"pgdb-dzx6qo6xqzvojpv5-pgbouncer.pgdb-dzx6qo6xqzvojpv5.svc"})
    refute accepts.(reference, {:dNSName, ~c"pgbouncer.dzx6qo6xqzvojpv5.flympg.net"})
    refute accepts.(reference, {:dNSName, ~c"pgdb-other-pgbouncer.pgdb-other.svc"})
  end
end
