import Config

config :mdex_native, syntax_highlighter: :lumis
# The chat page's free stand-in model (`AshTemplate.Chat.StandIn`).
config :req_llm, custom_providers: [AshTemplate.Chat.StandIn]
config :regent_identity, repo: AshTemplate.Repo, ash_domains: [RegentIdentity]

# Ash 3.33 requires an explicit string length unit. Codepoints match how
# PostgreSQL counts `length()`, so `max_length` bounds stored size; graphemes
# (`:mixed`) do not, because one grapheme can carry unbounded combining marks
# (CVE-2026-82752).
config :ash, default_string_length_count: :codepoints

config :mime, :types, %{"application/yaml" => ["yaml"]}

config :ash_template,
  ash_domains: [
    AshTemplate.Chat,
    AshTemplate.Accounts,
    AshTemplate.Agents,
    AshTemplate.Notes,
    AshTemplate.Rooms
  ],
  ecto_repos: [AshTemplate.Repo],
  generators: [timestamp_type: :utc_datetime]

config :ash_template, AshTemplate.Repo,
  database: "ash_template_disabled",
  hostname: "127.0.0.1",
  port: 1,
  pool_size: 1,
  migration_default_prefix: "ash_template_app"

# Background jobs live in the site's own schema, beside its tables. The serving
# connection goes through a pooler that drops LISTEN/NOTIFY, so queues hear about
# new jobs through Erlang process groups instead. `outside_calls` keeps slow calls
# to other websites from holding up the default queue. AshOban adds each trigger's
# sweep to `cron`.
config :ash_template, Oban,
  repo: AshTemplate.Repo,
  prefix: "ash_template_app",
  notifier: Oban.Notifiers.PG,
  queues: [default: 5, outside_calls: 3, chat_responses: [limit: 10], conversations: [limit: 10]],
  cron: [crontab: []],
  pruner: [max_age: {7, :days}],
  lifeline: [rescue_after: {10, :minutes}]

config :ash_template, :session_bootstrap_rate_limit, limit: 30, window_seconds: 300

# Agents sign in through the shared sign-in service, which checks every signed
# request (AshTemplateWeb.Plugs.AgentWallet).
config :ash_template, :agent_sign_in, broker_url: "https://siwa.regents.sh"

# How many messages one person or agent may post across the rooms each window.
config :ash_template, :room_post_rate_limit, limit: 10, window_seconds: 60

# Rate limits key on the direct peer. Production turns on Fly's client header.
config :ash_template, :behind_fly_proxy, false

# Metrics listen on loopback, on a port the system picks, so this site runs beside the
# other sites' local servers without taking the one port they all name in production.
config :ash_template, :metrics_listener, ip: {127, 0, 0, 1}, port: 0

# The chain the wallet page at /showcase/wallet sends on: Base Sepolia, a test
# network, so nothing it sends moves value.
config :ash_template, :wallet_chain, %{
  chain_id: 84_532,
  name: "Base Sepolia",
  rpc_url: "https://sepolia.base.org"
}

# The node the server reads each chain through, by chain id. A wallet adds a chain
# with its public `rpc_url` above; the server may read through a private node or a
# lab fork instead, and this address never reaches the browser.
config :ash_template, :chain_nodes, %{84_532 => "https://sepolia.base.org"}

# A sign-in lasts 30 days: the cookie expires then, and
# `AshTemplate.Accounts.SessionAuthority` reads this same limit.
config :ash_template, :session_options,
  store: :cookie,
  key: "_ash_template_key",
  signing_salt: "OLoeAaio",
  same_site: "Lax",
  secure: false,
  http_only: true,
  max_age: 30 * 24 * 60 * 60

config :ash_template, AshTemplateWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [
      html: AshTemplateWeb.ErrorHTML,
      json: AshTemplateWeb.ErrorJSON,
      md: AshTemplateWeb.ErrorMD
    ],
    layout: false
  ],
  pubsub_server: AshTemplate.PubSub,
  live_view: [signing_salt: "RH19ZPg2"]

config :esbuild,
  version: "0.25.4",
  ash_template: [
    args:
      ~w(js/app.ts js/privy_bridge.tsx --bundle --splitting --format=esm --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=. --loader:.woff2=file --loader:.woff=file --loader:.ttf=file),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Mix.Project.deps_path(), Mix.Project.build_path()]}
  ]

config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

config :sentry,
  environment_name: config_env(),
  json_library: Jason,
  enable_metrics: false,
  tags: %{app: "ash_template"}

config :phoenix, :json_library, Jason

import_config "#{config_env()}.exs"
