defmodule AshTemplate.DatabaseConfig do
  @moduledoc false

  @cluster_id "dzx6qo6xqzvojpv5"
  @cluster_name "regents-platform-prod"
  @production_database_host "direct.dzx6qo6xqzvojpv5.flympg.net"
  @production_pooler_host "pgbouncer.dzx6qo6xqzvojpv5.flympg.net"
  # The pooler presents a certificate from the cluster's own authority
  # (postgres-operator-ca, valid to July 2036), issued to the cluster's internal
  # name rather than the public one, so pooler connections trust that authority
  # alone and accept only that name.
  @pooler_authority "priv/certs/regents-platform-prod-pooler-ca.pem"
  @pooler_certificate_name ~c"pgdb-dzx6qo6xqzvojpv5-pgbouncer.pgdb-dzx6qo6xqzvojpv5.svc"
  # Superseded identities refused in production configuration: the legacy
  # platform application and the retired rehearsal cluster.
  @production_identities ["platform-phx", "regents-pg-test", "nvwq9ozp9ye03kl1"]
  @staging_hosts ["regents-staging-db.flycast", "regents-staging-db.internal"]
  # Staging can never reach production, so it refuses production's cluster, database
  # host and web application anywhere in a URL (host, database or credentials). These
  # terms are staging's alone: production runs as the Fly application regents-sh-web,
  # so refusing that name on the production role would refuse its own release commands.
  @staging_refusals [
    @cluster_id,
    @production_database_host,
    @production_pooler_host,
    "regents-sh-web" | @production_identities
  ]
  @deployment_role_error ~s(ASH_TEMPLATE_DEPLOYMENT_ROLE must be set to "production" or "staging")
  @remote_target_error "remote database access requires cluster dzx6qo6xqzvojpv5 named regents-platform-prod"

  def runtime_config!(environment, getenv \\ &System.get_env/1)

  def runtime_config!(:prod, getenv) do
    role = deployment_role!(getenv)
    getenv |> database_url!("DATABASE_POOLED_URL", role) |> serving()
  end

  def runtime_config!(:dev, getenv) do
    case remote_target(getenv) do
      :local ->
        partition = getenv.("ASH_TEMPLATE_DEV_PARTITION") || ""

        unless Regex.match?(~r/\A[a-z0-9_]*\z/, partition),
          do: raise("invalid development partition")

        [
          username: getenv.("USER"),
          password: nil,
          hostname: "127.0.0.1",
          port: 5432,
          database: "ash_template#{partition}_dev",
          pool_size: 2
        ]

      :remote ->
        database_url!(getenv, "DATABASE_POOLED_URL", :remote)
    end
  end

  def runtime_config!(:test, getenv) do
    partition = getenv.("MIX_TEST_PARTITION") || ""
    unless Regex.match?(~r/\A[a-z0-9_]*\z/, partition), do: raise("invalid test partition")

    [
      username: getenv.("USER"),
      password: nil,
      hostname: "127.0.0.1",
      port: 5432,
      database: "ash_template#{partition}_test",
      pool: Ecto.Adapters.SQL.Sandbox,
      pool_size: 5
    ]
  end

  @doc """
  The connection the site's listeners share (`AshTemplate.SharedChanges`): the
  serving login on the database's direct address, since the pooler hands out
  connections per transaction and drops `LISTEN`.
  """
  def notifications_config!(environment, getenv \\ &System.get_env/1) do
    environment
    |> runtime_config!(getenv)
    |> Keyword.drop([:pool, :pool_size, :prepare, :max_lifetime, :parameters])
    |> direct_address()
    |> connection_keys()
    |> Keyword.merge(auto_reconnect: true, parameters: [application_name: "ash-template-listen"])
  end

  # Postgrex.Notifications takes connection keys, not the repository's URL.
  defp connection_keys(options) do
    case Keyword.pop(options, :url) do
      {nil, options} -> options
      {url, options} -> Keyword.merge(Ecto.Repo.Supervisor.parse_url(url), options)
    end
  end

  def release_config!(getenv \\ &System.get_env/1) do
    role = deployment_role!(getenv)
    if role == :production, do: require_production_target!(getenv)
    database_url!(getenv, "DATABASE_DIRECT_URL", role)
  end

  # The serving connection shares one database with every other site, so it holds
  # five connections, names itself in pg_stat_activity and keeps connection details
  # out of its errors. Each connection is replaced after nine to ten minutes, spread
  # so the pool never reconnects at once: when Fly's proxy in front of the database
  # restarts, it closes any connection still open ten minutes later, and Fly's guide
  # for Ecto recycles on this schedule to stay ahead of it. The pooler closes a
  # connection idle for a minute; the pool's idle pings keep every connection busier
  # than that. The pooler refuses every startup setting but the name, so the limits
  # that stop a statement, a lock wait or an idle open transaction before it stalls
  # anyone else live on the serving login itself (ash-data, "Connections to the shared
  # production database"). Release commands connect with their own login and none of
  # these limits.
  defp serving(options) do
    Keyword.merge(options,
      pool_size: 5,
      max_lifetime: 540_000..600_000,
      show_sensitive_data_on_connection_error: false,
      parameters: [application_name: "ash-template-web"]
    )
  end

  # No default and no fallback between roles: an unset or unrecognized role stops
  # the boot before any database URL is read.
  defp deployment_role!(getenv) do
    case getenv.("ASH_TEMPLATE_DEPLOYMENT_ROLE") do
      "production" -> :production
      "staging" -> :staging
      _unset_or_unknown -> raise @deployment_role_error
    end
  end

  # The hosts a venue admits (any, for a developer's remote target) and the terms
  # its URL may not name anywhere. Production serves through the pooler and runs
  # its release commands on the direct address.
  defp venue(:production, "DATABASE_POOLED_URL"),
    do: {[@production_pooler_host], @production_identities}

  defp venue(:production, "DATABASE_DIRECT_URL"),
    do: {[@production_database_host], @production_identities}

  defp venue(:staging, _variable), do: {@staging_hosts, @staging_refusals}
  defp venue(:remote, _variable), do: {nil, @production_identities}

  defp database_url!(getenv, variable, venue) do
    {admitted_hosts, refused_terms} = venue(venue, variable)

    with value when is_binary(value) and value != "" <- getenv.(variable),
         {:ok, %URI{scheme: scheme, host: host, path: "/" <> database, userinfo: userinfo} = uri}
         when scheme in ["postgres", "postgresql"] <- URI.new(value),
         true <- present?(host) and present?(database) and valid_userinfo?(userinfo),
         false <- refused_identity?(uri, refused_terms),
         {:ok, url, admitted_host} <- admit(value, uri, admitted_hosts),
         true <- fixed_endpoint?(uri) and valid_ecto_url?(value) do
      connection_options(url, admitted_host)
    else
      value when value in [nil, ""] -> raise "#{variable} is required"
      _ -> raise "#{variable} must be a valid PostgreSQL URL for the approved target"
    end
  end

  defp admit(value, %URI{host: host}, nil), do: {:ok, value, host}

  defp admit(_value, %URI{host: host} = uri, admitted_hosts) do
    admitted_host = String.downcase(host)

    if admitted_host in admitted_hosts,
      do: {:ok, URI.to_string(%{uri | host: admitted_host}), admitted_host},
      else: :error
  end

  defp valid_ecto_url?(value) do
    Ecto.Repo.Supervisor.parse_url(value)
    true
  rescue
    _error -> false
  end

  # Every host an allowlist admits is fixed by its hostname alone, so none may carry
  # a port other than PostgreSQL's or any query option: Ecto turns every URL query key
  # into an atom and merges parsed URL options after the explicit Repo configuration,
  # so even encoded or future aliases could otherwise weaken TLS, replace the endpoint,
  # or restore named prepares after this module's checks.
  defp fixed_endpoint?(%URI{host: host, port: port, query: query}) do
    not (fly_mpg_host?(host) or String.downcase(host) in @staging_hosts) or
      (port in [nil, 5432] and query in [nil, ""])
  end

  # A URL without a port connects to PostgreSQL's, not the disabled placeholder
  # port in config.exs, which an explicit option would otherwise keep.
  defp connection_options(url, host) do
    options = [url: url, port: URI.parse(url).port || 5432, socket_options: [:inet6]]
    if fly_mpg_host?(host), do: fly_mpg_options(host) ++ options, else: options
  end

  defp fly_mpg_options(@production_pooler_host = host) do
    [
      prepare: :unnamed,
      ssl: [
        verify: :verify_peer,
        cacertfile: Application.app_dir(:ash_template, @pooler_authority),
        server_name_indication: String.to_charlist(host),
        customize_hostname_check: [match_fun: &pooler_certificate_name?/2]
      ]
    ]
  end

  # The direct address presents a public certificate for its own name.
  defp fly_mpg_options(host) do
    [
      ssl: [
        verify: :verify_peer,
        # Read before the application loads castore into `cacerts_get/0`.
        cacertfile: CAStore.file_path(),
        server_name_indication: String.to_charlist(host),
        customize_hostname_check: [match_fun: :public_key.pkix_verify_hostname_match_fun(:https)]
      ]
    ]
  end

  defp pooler_certificate_name?(_reference, {:dNSName, name}),
    do: name == @pooler_certificate_name

  defp pooler_certificate_name?(_reference, _presented), do: false

  # A Fly Managed Postgres cluster answers on `pgbouncer.<cluster>` through its
  # pooler and on `direct.<cluster>` without it, for the same logins.
  defp direct_address(options) do
    case options[:url] && URI.parse(options[:url]) do
      %URI{host: "pgbouncer." <> cluster} = uri ->
        host = "direct." <> cluster
        Keyword.merge(options, connection_options(URI.to_string(%{uri | host: host}), host))

      _not_pooled ->
        options
    end
  end

  defp fly_mpg_host?(host) do
    host = String.downcase(host)
    host != "flympg.net" and String.ends_with?(host, ".flympg.net")
  end

  defp remote_target(getenv) do
    cluster_id = getenv.("ASH_TEMPLATE_DATABASE_CLUSTER_ID")
    cluster_name = getenv.("ASH_TEMPLATE_DATABASE_CLUSTER_NAME")

    cond do
      production_identity?(getenv.("FLY_APP_NAME")) -> raise @remote_target_error
      is_nil(cluster_id) and is_nil(cluster_name) -> :local
      cluster_id == @cluster_id and cluster_name == @cluster_name -> :remote
      true -> raise @remote_target_error
    end
  end

  defp require_production_target!(getenv) do
    if getenv.("ASH_TEMPLATE_DATABASE_TARGET_MODE") == "production" and
         getenv.("ASH_TEMPLATE_DATABASE_CLUSTER_ID") == @cluster_id and
         getenv.("ASH_TEMPLATE_DATABASE_CLUSTER_NAME") == @cluster_name and
         not production_identity?(getenv.("FLY_APP_NAME")) do
      :ok
    else
      raise "database migration requires production mode for cluster dzx6qo6xqzvojpv5 named regents-platform-prod"
    end
  end

  defp valid_userinfo?(userinfo) when is_binary(userinfo),
    do: userinfo |> String.split(":", parts: 2) |> Enum.map(&present?/1) == [true, true]

  defp valid_userinfo?(_userinfo), do: false

  defp refused_identity?(%URI{} = uri, refused_terms) do
    Enum.any?([uri.host, uri.path, uri.userinfo], &names_any?(&1, refused_terms))
  end

  defp production_identity?(value), do: names_any?(value, @production_identities)

  defp names_any?(value, terms) when is_binary(value) do
    decoded = value |> decode() |> String.downcase()
    Enum.any?(terms, &String.contains?(decoded, &1))
  end

  defp names_any?(_value, _terms), do: false

  defp decode(value) do
    URI.decode(value)
  rescue
    _error -> value
  end

  defp present?(value), do: is_binary(value) and String.trim(value) != ""
end
