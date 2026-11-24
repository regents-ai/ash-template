defmodule AshTemplate.DatabaseConfig do
  @moduledoc false

  @deployment_role_error ~s(ASH_TEMPLATE_DEPLOYMENT_ROLE must be set to "production" or "staging")
  # Serving and development each hold 5 connections by default: background queues
  # share this pool with LiveView pages.
  @pool_size 5

  def runtime_config!(:prod) do
    _role = deployment_role!()
    first_env!(["DATABASE_POOLED_URL", "DATABASE_URL"]) |> database_url!() |> serving()
  end

  def runtime_config!(:dev) do
    case remote_target() do
      :local ->
        local_dev_config()

      :remote ->
        first_env!(["DATABASE_POOLED_URL", "DATABASE_URL"])
        |> database_url!()
        |> Keyword.put(:pool_size, @pool_size)
    end
  end

  defp local_dev_config do
    case System.get_env("DATABASE_URL") do
      value when is_binary(value) and value != "" ->
        {"DATABASE_URL", value} |> database_url!() |> Keyword.put(:pool_size, @pool_size)

      _unset ->
        partition = System.get_env("ASH_TEMPLATE_DEV_PARTITION") || ""

        unless Regex.match?(~r/\A[a-z0-9_]*\z/, partition),
          do: raise("invalid development partition")

        [
          username: System.get_env("USER"),
          password: nil,
          hostname: "127.0.0.1",
          port: 5432,
          database: "ash_template#{partition}_dev",
          pool_size: @pool_size
        ]
    end
  end

  @doc "Whether a developer's machine is set to use a remote database instead of local Postgres."
  def remote?, do: remote_target() == :remote

  @doc """
  The one connection the site's listeners share (`AshTemplate.SharedChanges`): the
  serving login and address, outside the pool.
  """
  def notifications_config!(environment) do
    environment
    |> runtime_config!()
    |> Keyword.drop([:pool_size, :max_lifetime, :parameters])
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

  def release_config! do
    _role = deployment_role!()
    first_env!(["DATABASE_DIRECT_URL", "DATABASE_URL"]) |> database_url!()
  end

  defp serving(options) do
    Keyword.merge(options,
      pool_size: pool_size(),
      max_lifetime: 540_000..600_000,
      show_sensitive_data_on_connection_error: false,
      parameters: [
        application_name: "ash-template-web",
        statement_timeout: "15000",
        lock_timeout: "5000",
        idle_in_transaction_session_timeout: "15000"
      ]
    )
  end

  defp pool_size do
    case System.get_env("POOL_SIZE") do
      value when is_binary(value) and value != "" ->
        case Integer.parse(value) do
          {n, ""} when n > 0 -> n
          _invalid -> raise "POOL_SIZE must be a positive integer"
        end

      _unset ->
        @pool_size
    end
  end

  defp deployment_role! do
    case System.get_env("ASH_TEMPLATE_DEPLOYMENT_ROLE") do
      "production" -> :production
      "staging" -> :staging
      _unset_or_unknown -> raise @deployment_role_error
    end
  end

  defp first_env!(variables) do
    Enum.find_value(variables, fn name ->
      case System.get_env(name) do
        value when is_binary(value) and value != "" -> {name, value}
        _unset -> nil
      end
    end) || raise("#{Enum.join(variables, " or ")} is required")
  end

  defp database_url!({variable, value}) do
    admitted_hosts = allowed_hosts()

    with {:ok, %URI{scheme: scheme, host: host, path: "/" <> database, userinfo: userinfo} = uri}
         when scheme in ["postgres", "postgresql"] <- URI.new(value),
         true <- present?(host) and present?(database) and valid_userinfo?(userinfo),
         {:ok, normalized_uri, admitted_host} <- admit(normalize_uri(uri), admitted_hosts),
         url = URI.to_string(normalized_uri),
         true <- valid_ecto_url?(url) do
      connection_options(url, admitted_host)
    else
      _ -> raise "#{variable} must be a valid PostgreSQL URL"
    end
  end

  # Fly Managed Postgres's PgBouncer endpoint rejects startup parameters
  # (`statement_timeout`, `lock_timeout`, `idle_in_transaction_session_timeout`)
  # and does not support LISTEN/NOTIFY. Rewrite `pgbouncer.<id>.flympg.net` to
  # `direct.<id>.flympg.net` and strip URL query params so explicit verify_peer
  # TLS options govern cleanly.
  defp normalize_uri(%URI{host: host} = uri) do
    lower_host = String.downcase(host)

    upgraded_host =
      if fly_mpg_host?(lower_host) and String.starts_with?(lower_host, "pgbouncer."),
        do: String.replace_prefix(lower_host, "pgbouncer.", "direct."),
        else: lower_host

    query = if fly_mpg_host?(upgraded_host), do: nil, else: uri.query
    %{uri | host: upgraded_host, query: query}
  end

  defp allowed_hosts do
    case System.get_env("ASH_TEMPLATE_ALLOWED_DB_HOSTS") do
      value when is_binary(value) and value != "" ->
        value
        |> String.split(",", trim: true)
        |> Enum.map(&(&1 |> String.trim() |> String.downcase()))
        |> Enum.reject(&(&1 == ""))

      _unset ->
        nil
    end
  end

  defp admit(%URI{host: host} = uri, nil), do: {:ok, uri, host}

  defp admit(%URI{host: host} = uri, admitted_hosts) do
    if host in admitted_hosts, do: {:ok, uri, host}, else: :error
  end

  defp valid_ecto_url?(value) do
    Ecto.Repo.Supervisor.parse_url(value)
    true
  rescue
    _error -> false
  end

  defp connection_options(url, host) do
    socket_options = if ipv6?(host), do: [:inet6], else: []
    options = [url: url, port: URI.parse(url).port || 5432, socket_options: socket_options]

    if fly_mpg_host?(host) or System.get_env("DATABASE_SSL") in ~w(true 1),
      do: tls_options(host) ++ options,
      else: options
  end

  defp ipv6?(host) do
    case System.get_env("ECTO_IPV6") do
      value when value in ~w(false 0) -> false
      value when value in ~w(true 1) -> true
      _unset -> fly_mpg_host?(host)
    end
  end

  defp tls_options(host) do
    [
      ssl: [
        verify: :verify_peer,
        cacertfile: CAStore.file_path(),
        server_name_indication: String.to_charlist(host),
        customize_hostname_check: [match_fun: :public_key.pkix_verify_hostname_match_fun(:https)]
      ]
    ]
  end

  defp fly_mpg_host?(host) do
    host = String.downcase(host)
    host != "flympg.net" and String.ends_with?(host, ".flympg.net")
  end

  defp remote_target do
    if System.get_env("ASH_TEMPLATE_REMOTE_DB") in ~w(true 1), do: :remote, else: :local
  end

  defp valid_userinfo?(userinfo) when is_binary(userinfo),
    do: userinfo |> String.split(":", parts: 2) |> Enum.map(&present?/1) == [true, true]

  defp valid_userinfo?(_userinfo), do: false

  defp present?(value), do: is_binary(value) and String.trim(value) != ""
end
