import Config

require Logger

config :sentry,
  dsn: System.get_env("SENTRY_DSN"),
  release: System.get_env("SENTRY_RELEASE"),
  environment_name: System.get_env("SENTRY_ENVIRONMENT", to_string(config_env()))

config :ash_template, :privy,
  app_id: System.get_env("PRIVY_APP_ID"),
  verification_key: System.get_env("PRIVY_VERIFICATION_KEY")

# Without its Privy settings a local server answers every page while nobody can
# sign in, so it refuses to start. A worktree holds no settings files of its own.
# Other mix tasks, such as migrations and code generation, run without them.
if config_env() == :dev and Phoenix.Endpoint.server?(:ash_template, AshTemplateWeb.Endpoint) do
  for name <- ~w(PRIVY_APP_ID PRIVY_VERIFICATION_KEY), System.get_env(name, "") == "" do
    raise """
    #{name} is not set, so nobody could sign in. Start the site with its settings loaded:
    direnv exec <main checkout>/platform mix phx.server
    """
  end
end

# The server reads a chain through its own node when one is set, such as a
# private node whose address carries a key, or a local copy of the chain for a
# lab run; wallets still add the public address. The wallet chain's node is
# ASH_TEMPLATE_CHAIN_NODE_URL; Credits purchases are checked through the Base
# and Ethereum ones.
%{chain_id: wallet_chain_id} = Application.fetch_env!(:ash_template, :wallet_chain)

node_overrides =
  for {chain_id, setting} <- [
        {wallet_chain_id, "ASH_TEMPLATE_CHAIN_NODE_URL"},
        {8453, "ASH_TEMPLATE_BASE_NODE_URL"},
        {1, "ASH_TEMPLATE_ETHEREUM_NODE_URL"}
      ],
      node_url = System.get_env(setting),
      into: %{} do
    case URI.new(node_url) do
      {:ok, %URI{scheme: scheme, host: host}}
      when scheme in ["http", "https"] and host not in [nil, ""] ->
        {chain_id, node_url}

      _invalid ->
        raise "#{setting} must be an http or https address"
    end
  end

config :ash_template,
       :chain_nodes,
       Map.merge(Application.fetch_env!(:ash_template, :chain_nodes), node_overrides)

# The Privy accounts that may give Credits and handle refunds, comma separated.
if admins = System.get_env("REGENT_CREDITS_ADMINS") do
  config :regent_credits,
    admins: admins |> String.split(",", trim: true) |> Enum.map(&String.trim/1)
end

# Agents' signed requests are checked by this sign-in service instead, such as one
# running on this machine.
if broker_url = System.get_env("ASH_TEMPLATE_SIWA_BROKER_URL") do
  config :regent_agents, :siwa, url: broker_url, audience: "ash-template"
end

# The running version the bottom bar shows: the release, and on Fly the short
# commit `scripts/deploy.sh` labels the image with; "dev" anywhere else.
config :ash_template, :running_version,
  commit:
    (case System.get_env("FLY_IMAGE_REF") do
       nil -> "dev"
       image -> image |> String.split(":") |> List.last()
     end)

# Each saved note is posted to this address when it is set (AshTemplate.Notes.Webhook).
if webhook_url = System.get_env("ASH_TEMPLATE_NOTES_WEBHOOK_URL") do
  case URI.new(webhook_url) do
    {:ok, %URI{scheme: scheme, host: host}}
    when scheme in ["http", "https"] and host not in [nil, ""] ->
      config :ash_template, :notes_webhook_url, webhook_url

    _invalid ->
      raise "ASH_TEMPLATE_NOTES_WEBHOOK_URL must be an http or https address"
  end
end

# Each sign-in reads the wallet's ENS name from Ethereum mainnet while this
# endpoint is set (AshTemplate.Accounts.EnsIdentity).
if ethereum_read_rpc_url = System.get_env("ETHEREUM_READ_RPC_URL") do
  case URI.new(ethereum_read_rpc_url) do
    {:ok, %URI{scheme: "https", host: host}} when host not in [nil, ""] ->
      config :ash_template, :ethereum_read_rpc_url, ethereum_read_rpc_url

    _invalid ->
      raise "ETHEREUM_READ_RPC_URL must be an https address"
  end
end

# Jev labels saved notes while this key is set (AshTemplate.Notes.Labels).
if openrouter_key = System.get_env("OPENROUTER_API_KEY") do
  config :regent_jev, api_key: openrouter_key
end

# A local stand-in for OpenRouter's decisions endpoint, so development makes no paid call.
if jev_endpoint = System.get_env("OPENROUTER_DECISIONS_URL") do
  case URI.new(jev_endpoint) do
    {:ok, %URI{scheme: scheme, host: host}}
    when scheme in ["http", "https"] and host not in [nil, ""] ->
      config :regent_jev, endpoint: jev_endpoint

    _invalid ->
      raise "OPENROUTER_DECISIONS_URL must be an http or https address"
  end
end

# Production must say out loud whether the product surfaces are open, and any
# value but "on" or "off" stops the boot.
app_surfaces? =
  case {config_env(), System.get_env("ASH_TEMPLATE_APP_SURFACES")} do
    {:prod, nil} -> raise ~s(ASH_TEMPLATE_APP_SURFACES must be set to "on" or "off")
    {_env, setting} when setting in [nil, "on"] -> true
    {_env, "off"} -> false
    {_env, other} -> raise ~s(ASH_TEMPLATE_APP_SURFACES must be "on" or "off", got "#{other}")
  end

config :ash_template, :app_surfaces, app_surfaces?

Logger.info("App surfaces #{if app_surfaces?, do: "enabled", else: "disabled"}")

# The showcase pages, the motion lab and the build skills (AshTemplateWeb.Showcase).
# Production must choose "public" (the hosted demo) or "off" (a new site), and any
# other value stops the boot. Development is "local" unless told otherwise.
showcase =
  case {config_env(), System.get_env("ASH_TEMPLATE_SHOWCASE")} do
    {:prod, "public"} -> :public
    {:prod, "off"} -> :off
    {:prod, _setting} -> raise ~s(ASH_TEMPLATE_SHOWCASE must be set to "public" or "off")
    {_env, setting} when setting in [nil, "local"] -> :local
    {_env, "public"} -> :public
    {_env, "off"} -> :off
    {_env, _setting} -> raise ~s(ASH_TEMPLATE_SHOWCASE must be "local", "public" or "off")
  end

config :ash_template, :showcase, showcase

Logger.info("Showcase #{showcase}")

migrating? = System.get_env("ASH_TEMPLATE_RELEASE_COMMAND") == "migrate"

database_config =
  if config_env() == :prod and migrating?,
    do: AshTemplate.DatabaseConfig.release_config!(),
    else: AshTemplate.DatabaseConfig.runtime_config!(config_env())

config :ash_template, AshTemplate.Repo, database_config

if config_env() == :prod do
  config :ash_template, :session_options, secure: true, http_only: true

  unless migrating? do
    host = String.trim(System.fetch_env!("PHX_HOST"))
    secret_key_base = System.fetch_env!("SECRET_KEY_BASE")

    if host == "", do: raise("PHX_HOST must not be empty")
    if byte_size(secret_key_base) < 64, do: raise("SECRET_KEY_BASE must be at least 64 bytes")

    config :ash_template, AshTemplateWeb.Endpoint,
      server: true,
      url: [host: host, port: 443, scheme: "https"],
      http: [
        ip: {0, 0, 0, 0, 0, 0, 0, 0},
        port: String.to_integer(System.get_env("PORT", "4000"))
      ],
      secret_key_base: secret_key_base
  end
end
