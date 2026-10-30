import Config

require Logger

# Tests sign in to their own app id (config/test.exs), whatever the shell sets.
if config_env() != :test do
  config :ash_template, :privy,
    app_id: System.get_env("PRIVY_APP_ID"),
    verification_key: System.get_env("PRIVY_VERIFICATION_KEY")
end

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

# Visit lines (AshTemplateWeb.VisitLog) have a handler of their own, sized for a crowd
# acting at once, which the application adds as it starts. Every other line stays on
# the default handler, whose limit of 500 a second still guards against a flood of
# errors.
config :ash_template, :logger, [
  AshTemplateWeb.VisitLog.handler(%{type: :standard_io}, Logger.default_formatter())
]

# The browser walk's server (test/browser/walk.sh) writes its visit lines in
# production's shape to a file, which test/browser/visits.spec.ts reads to replay a
# visit.
if config_env() == :dev and System.get_env("ASH_TEMPLATE_WALK") == "true" do
  config :ash_template, :logger, [
    AshTemplateWeb.VisitLog.handler(
      %{file: String.to_charlist(Path.expand("../tmp/walk-lines.jsonl", __DIR__))},
      LoggerJSON.Formatters.Basic.new(metadata: AshTemplateWeb.VisitLog.fields())
    )
  ]
end

# The server reads a chain through its own node when one is set, such as a
# private node whose address carries a key, or a local copy of the chain for a
# lab run; wallets still add the public address. The wallet chain's node is
# ASH_TEMPLATE_CHAIN_NODE_URL; Credits purchases are checked through the Base
# and Ethereum ones. Tests read no chain, whatever the shell sets.
if config_env() != :test do
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
end

# The Privy accounts that may give Credits and handle refunds, comma separated.
if admins = System.get_env("REGENT_CREDITS_ADMINS") do
  config :regent_credits,
    admins: admins |> String.split(",", trim: true) |> Enum.map(&String.trim/1)
end

# Credits by card or Link through Stripe while its keys are set (RegentCredits.Stripe).
# Tests answer for Stripe themselves (config/test.exs), whatever the shell sets.
if config_env() != :test do
  if secret_key = System.get_env("STRIPE_SECRET_KEY") do
    config :regent_credits, :stripe,
      secret_key: secret_key,
      webhook_secret: System.fetch_env!("STRIPE_WEBHOOK_SECRET")

    config :ash_template, :stripe_publishable_key, System.fetch_env!("STRIPE_PUBLISHABLE_KEY")
  end
end

# Agents' signed requests are checked by this sign-in service instead, such as one
# running on this machine.
broker_url = System.get_env("ASH_TEMPLATE_SIWA_BROKER_URL")

if broker_url do
  config :regent_agents, :siwa, url: broker_url, audience: "ash-template"
end

# The Claude connector, behind one switch (AshTemplate.OAuth.enabled?/0): its
# sign-in under /oauth and /.well-known/oauth-*, its identity tools at /mcp
# (AshTemplate.Agents.Connection), Claude in the pairing box and the Claude guide at
# /agents/claude, which /agents, the sitemap, /llms.txt and /agents.md then name.
# Anything but "true" leaves all of it off. Switch it on only after the
# migrations have run. The connector's identities are held by the same sign-in
# service, asked with this site's own key there.
claude_connector? = System.get_env("ASH_TEMPLATE_CLAUDE_CONNECTOR_ENABLED") == "true"
hosted_signing_key = System.get_env("SIWA_HOSTED_SIGNING_KEY")

if claude_connector? and
     not (is_binary(hosted_signing_key) and
            Regex.match?(~r/\A[A-Za-z0-9_-]{32,}\z/, hosted_signing_key)) do
  raise "ASH_TEMPLATE_CLAUDE_CONNECTOR_ENABLED is true, so SIWA_HOSTED_SIGNING_KEY must be " <>
          "this site's hosted signing key from the sign-in service: 32 or more letters, " <>
          "digits, - or _"
end

# The connector's sign-in answers at the site's own address and its MCP address
# is under it: https://PHX_HOST in production, the endpoint's own address
# elsewhere. Each code and token has these written on it as it is issued, and one
# whose values differ from the running site's is refused (docs/oauth-reference.md).
site_url =
  if config_env() == :prod do
    case String.trim(System.get_env("PHX_HOST", "")) do
      "" -> nil
      host -> "https://" <> host
    end
  else
    url = Application.fetch_env!(:ash_template, AshTemplateWeb.Endpoint)[:url]
    URI.to_string(%URI{scheme: url[:scheme] || "http", host: url[:host], port: url[:port]})
  end

config :ash_template, AshTemplate.OAuth,
  enabled?: claude_connector?,
  issuer: site_url,
  resource: site_url && site_url <> "/mcp"

config :regent_mcp_agents, :config,
  enabled?: claude_connector?,
  hosted_signer: [
    base_url: broker_url || Application.fetch_env!(:regent_agents, :siwa)[:url],
    key: hosted_signing_key
  ]

# Claude is offered in the pairing box, and accepted by the pair request, only
# while its connector is on.
config :regent_agents, hosted_pairing: if(claude_connector?, do: [:claude], else: [])

# This site's own key for reading what paired agents have done from the sign-in
# service (RegentAgents.Activity).
config :regent_agents, :activity_read_token, System.get_env("SIWA_ACTIVITY_READ_TOKEN")

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

# Search engines that read IndexNow hear about this site's new and changed public
# pages when this key is set (AshTemplate.IndexNow). It is public: the site serves it.
if indexnow_key = System.get_env("ASH_TEMPLATE_INDEXNOW_KEY") do
  unless Regex.match?(~r/\A[a-zA-Z0-9-]{8,128}\z/, indexnow_key),
    do: raise("ASH_TEMPLATE_INDEXNOW_KEY must be 8 to 128 letters, digits or dashes")

  config :ash_template, :indexnow_key, indexnow_key
end

# Each sign-in reads the wallet's ENS name from Ethereum mainnet while this
# endpoint is set (AshTemplate.Accounts.EnsIdentity). Tests never read it.
if config_env() != :test do
  if ethereum_read_rpc_url = System.get_env("ETHEREUM_READ_RPC_URL") do
    case URI.new(ethereum_read_rpc_url) do
      {:ok, %URI{scheme: "https", host: host}} when host not in [nil, ""] ->
        config :ash_template, :ethereum_read_rpc_url, ethereum_read_rpc_url

      _invalid ->
        raise "ETHEREUM_READ_RPC_URL must be an https address"
    end
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

unless migrating? do
  config :ash_template,
         AshTemplate.Notifications,
         AshTemplate.DatabaseConfig.notifications_config!(config_env())
end

if config_env() == :prod do
  config :ash_template, :session_options, secure: true, http_only: true

  # One JSON object a line, which Fly Sentinel reads, carrying only the visit
  # fields (AshTemplateWeb.VisitLog), from both handlers. Release commands write the
  # same shape.
  json = LoggerJSON.Formatters.Basic.new(metadata: AshTemplateWeb.VisitLog.fields())
  config :logger, :default_handler, formatter: json
  config :ash_template, :logger, [AshTemplateWeb.VisitLog.handler(%{type: :standard_io}, json)]

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

    # The commit the image was built from, and the tag of the Fly image this
    # machine runs (the part after the registry path and app name).
    config :ash_template, :build, %{
      commit: System.fetch_env!("SOURCE_COMMIT"),
      release: "FLY_IMAGE_REF" |> System.fetch_env!() |> String.split(":") |> List.last()
    }
  end
end
