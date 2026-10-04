import Config

require Logger

config :sentry,
  dsn: System.get_env("SENTRY_DSN"),
  release: System.get_env("SENTRY_RELEASE"),
  environment_name: System.get_env("SENTRY_ENVIRONMENT", to_string(config_env()))

config :ash_template, :privy,
  app_id: System.get_env("PRIVY_APP_ID"),
  verification_key: System.get_env("PRIVY_VERIFICATION_KEY")

# The server reads the wallet chain through this node when it is set, such as a
# private node whose address carries a key; wallets still add the public address.
if node_url = System.get_env("ASH_TEMPLATE_CHAIN_NODE_URL") do
  %{chain_id: chain_id} = Application.fetch_env!(:ash_template, :wallet_chain)
  nodes = Application.fetch_env!(:ash_template, :chain_nodes)
  config :ash_template, :chain_nodes, Map.put(nodes, chain_id, node_url)
end

# Agents' signed requests are checked by this sign-in service instead, such as one
# running on this machine.
if broker_url = System.get_env("ASH_TEMPLATE_SIWA_BROKER_URL") do
  config :ash_template, :agent_sign_in, broker_url: broker_url
end

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
