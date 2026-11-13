import Config

config :mdex_native, syntax_highlighter: :lumis

# The chat page's free stand-in model (`AshTemplate.Chat.StandIn`).
config :req_llm, custom_providers: [AshTemplate.Chat.StandIn]

config :regent_identity, repo: AshTemplate.Repo, ash_domains: [RegentIdentity]

# The Privy accounts that run this site: they see the saved errors at
# /admin/errors and may remove an agent's picture (`RegentAgents.Checks.Admin`).
# Set at runtime (config/runtime.exs).
config :ash_template, :admins, []

# Ash 3.33 requires an explicit string length unit. Codepoints match how
# PostgreSQL counts `length()`, so `max_length` bounds stored size; graphemes
# (`:mixed`) do not, because one grapheme can carry unbounded combining marks
# (CVE-2026-82752).
config :ash, default_string_length_count: :codepoints

# The name this site goes by in the shared Regent libraries. A site copied
# from the template changes it here and nowhere else.
site = "template"

config :ash_template,
  site: site,
  ash_domains: [
    AshTemplate.Activity,
    AshTemplate.Chat,
    AshTemplate.Accounts,
    AshTemplate.Agents,
    AshTemplate.Dms,
    AshTemplate.Messages,
    AshTemplate.Polls,
    AshTemplate.Notes,
    AshTemplate.Points,
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

# Each paired agent's reading from the sign-in service, kept five minutes. Older
# readings leave with the generation the collector drops every ten minutes.
config :ash_template, AshTemplate.Agents.ActivityReading,
  gc_interval: :timer.minutes(10),
  max_size: 10_000

# The hosted identity wallet of each account and connected app, which never changes
# once the sign-in service has given it. One that leaves with a collected generation is asked for again.
config :ash_template, AshTemplate.Agents.HostedAddress,
  gc_interval: :timer.hours(12),
  max_size: 100_000

# Background jobs live in the site's own schema, beside its tables. Queues hear
# about new jobs through Erlang process groups. Each queue holds one class of work
# (skills/elixir-stack/references/oban.md, "Queues"), so a slow or failing service
# holds up only the jobs that wait on it: `default` and `points` work on the
# database alone; `ens` and `points_chain` read a chain; `chat_responses`,
# `conversations` and `labels` ask a model; `outside_calls` makes every other call
# to another website (the notes webhook, IndexNow). `ens` keeps a crowd signing in
# at once (one lookup each, seconds long for a name with a picture) from holding up
# the Points chain reads. AshOban adds each trigger's sweep to `cron`.
config :ash_template, Oban,
  repo: AshTemplate.Repo,
  prefix: "ash_template_app",
  notifier: Oban.Notifiers.PG,
  # A database job holds a connection while it runs, so `default` and `points`
  # together take 3 of the pool's 5 (AshTemplate.DatabaseConfig) and leave 2 for
  # page requests.
  queues: [
    default: 1,
    points: 2,
    points_chain: 2,
    ens: 3,
    chat_responses: [limit: 10],
    conversations: [limit: 10],
    labels: 3,
    outside_calls: 3
  ],
  # Regents alone runs RegentPoints.TallyPeriods, the shared NFT bonus tally at each period end.
  cron: [
    crontab: [
      {"17 4 * * *", AshTemplate.ErrorPruner},
      # Sign-in session rows no browser can still hold.
      {"43 4 * * *", AshTemplate.Accounts.SessionPruner},
      # This release's public pages, sent to IndexNow once per release. The hourly
      # job only queues the sending, which runs in `outside_calls`, so it is
      # database work.
      {"@hourly", AshTemplate.IndexNow, queue: :default},
      # From the Points start, the one-time points for what accounts already had.
      {"@hourly", RegentPoints.StartAwards},
      # One line for each kind of shared reading a producer rereads on notice.
      {"* * * * *", AshTemplate.SharedReading.Heal, args: %{kind: "room_activity"}},
      {"* * * * *", AshTemplate.SharedReading.Heal, args: %{kind: "points_board"}}
    ]
  ],
  pruner: [max_age: {7, :days}],
  lifeline: [rescue_after: {10, :minutes}]

config :ash_template, :session_bootstrap_rate_limit, limit: 30, window_seconds: 300

# Agents sign in through the shared sign-in service, which checks every signed
# request (AshTemplateWeb.Plugs.AgentWallet), and pair with a person's account
# through the agent pairing every Regent site shares (RegentAgents). `allowed` is
# what an agent may do here in each status, as GET /api/agents/v1/whoami tells it
# and the agent guides list it: true to the routes and policies, so change it with them.
config :regent_agents,
  repo: AshTemplate.Repo,
  pubsub: AshTemplate.PubSub,
  notifications: AshTemplate.Notifications,
  account: {AshTemplate.Agents.PairedAccount, :account},
  allowed: %{
    "not_paired" => [
      "Read this site's public pages, docs and chat rooms, also with the about, docs, rooms_list, rooms_messages and rooms_message tools.",
      "Check your status here at any time.",
      "Post one message in a room as yourself.",
      "Pair with the code your person makes with Pair New Agent on their Agents page."
    ],
    "person_not_here" => [
      "Read this site's public pages, docs and chat rooms, also with the about, docs, rooms_list, rooms_messages and rooms_message tools.",
      "Check your status here at any time.",
      "Post one message in a room as yourself."
    ],
    "paired" => [
      "Read this site's public pages, docs and chat rooms, also with the about, docs, rooms_list, rooms_messages and rooms_message tools.",
      "Check your status here at any time, and check in for your person.",
      "Read, add, search, change and delete your person's notes.",
      "Post in rooms for your person, and change or delete their room messages.",
      "Search the chat rooms.",
      "Read your person's latest activity.",
      "Read your person's Points.",
      "Pin your person's notes, each pin paid with 1 USDC from your own wallet."
    ]
  },
  ash_domains: [RegentAgents],
  siwa: [url: "https://siwa.regents.sh", audience: "ash-template"]

# Paid actions, through the Regents payments library shared by every Regent
# site: an agent's note pin (AshTemplate.Payments.NotePin), paid in USDC from
# its wallet on Base. The records live in the shared
# `regent_payments` schema; this site reads and writes only its own rows.
config :regent_payments,
  repo: AshTemplate.Repo,
  site: site,
  ash_domains: [RegentPayments],
  offers: [AshTemplate.Payments.NotePin]

# Jev picks a label for each saved note while the server has an OpenRouter key
# (AshTemplate.Notes.Labels); the whole site asks at most daily_questions a day,
# and one person at most person_daily_questions of them.
config :ash_template, :note_labels,
  model: "~typesafe/jev-latest",
  daily_questions: 500,
  person_daily_questions: 50

# How often one person or agent may save each kind of writing, and how often one
# client address may post, like or search, each window (AshTemplate.Limits). A
# guest post is one no person stands behind: an unpaired agent's one post. A like
# and a like taken back share `like`: two a second for a whole minute is more than
# anyone liking their way through a room, and every open page of the room hears
# each one, so a script toggling a like many times a second is stopped.
config :ash_template, :limits,
  room: [limit: 3, window_seconds: 86_400],
  poll: [limit: 3, window_seconds: 86_400],
  room_post: [limit: 10, window_seconds: 60],
  room_post_address: [limit: 30, window_seconds: 60],
  like: [limit: 120, window_seconds: 60],
  like_address: [limit: 300, window_seconds: 60],
  guest_post_address: [limit: 10, window_seconds: 3600],
  note: [limit: 30, window_seconds: 60],
  chat_message: [limit: 10, window_seconds: 60],
  dm: [limit: 300, window_seconds: 3600],
  report: [limit: 10, window_seconds: 3600],
  message: [limit: 10, window_seconds: 3600],
  message_address: [limit: 30, window_seconds: 3600],
  search_address: [limit: 300, window_seconds: 60],
  wallet_read: [limit: 30, window_seconds: 60]

# The build /capabilities.json names. Only a deployed image has one (config/runtime.exs).
config :ash_template, :build, %{commit: nil, release: nil}

# Which name a signed-in person is shown by when they have both: `:chosen`, the
# display name they chose, or `:ens`, their wallet's ENS name. Each site picks one.
config :ash_template, :name_first, :chosen

# Rate limits key on the direct peer. Production turns on Fly's client header.
config :ash_template, :behind_fly_proxy, false

# Metrics listen on loopback, on a port the system picks, so this site runs beside the
# other sites' local servers without taking the one port they all name in production.
config :ash_template, :metrics_listener, ip: {127, 0, 0, 1}, port: 0

# The engine's own measurements (memory, run queues, process counts), taken every
# 10 seconds by telemetry_poller's default poller and exported as `vm.*` metrics.
config :telemetry_poller, :default, period: 10_000

# The chains whose newest block the site's pages show, each with how often it is
# read, in milliseconds: Base, once an hour, for /showcase/figures, and again
# after a confirmed on-chain press or a press of the page's read-again icon. The
# readers run only where the site serves pages (`AshTemplate.ChainHead`).
config :ash_template, :chain_heads, %{8453 => 3_600_000}

# Who reads a chain again when a person's action may have changed it
# (`AshTemplate.ChainRefresh`).
config :ash_template, AshTemplate.ChainRefresh, readers: [AshTemplate.ChainHead]

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
config :ash_template, :chain_nodes, %{
  84_532 => "https://sepolia.base.org",
  8453 => "https://mainnet.base.org"
}

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

# A signed agent's live feed (`GET /api/v1/feed`): how many one machine holds open
# at once, how many of those may be agents not paired with a person, and how often a
# quiet feed sends a keep-alive line. Fly's proxy closes a connection that sends
# nothing for 60 seconds.
config :ash_template, AshTemplateWeb.FeedController,
  max_open: 200,
  max_unpaired: 20,
  keep_alive_ms: 25_000

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
  version: "0.28.2",
  ash_template: [
    args:
      ~w(js/app.ts js/privy_bridge.tsx --bundle --splitting --format=esm --target=es2022 --outdir=../priv/static/assets/js --chunk-names=chunks/[name]-[hash] --asset-names=chunks/[name]-[hash] --external:/fonts/* --external:/images/* --alias:@=. --loader:.woff2=file --loader:.woff=file --loader:.ttf=file),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Mix.Project.deps_path(), Mix.Project.build_path()]}
  ]

config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id, :visit, :actor, :surface, :event]

# Failed requests, pages and jobs are saved in the site's own schema and shown
# to the site's admins at /admin/errors. Only server faults are saved, with only
# where each one happened (AshTemplate.SavedErrors), and AshTemplate.ErrorPruner
# clears each one a week after it was last seen.
config :error_tracker,
  repo: AshTemplate.Repo,
  otp_app: :ash_template,
  prefix: "ash_template_app",
  ignorer: AshTemplate.SavedErrors,
  filter: AshTemplate.SavedErrors

config :phoenix, :json_library, Jason

# Points launch is explicit: nothing earns until Sean sets the start time. The five
# start actions are approved (Sean, 13 November), so the Points page lists them.
# Every site reads the one shared regent_points schema; Regents owns its migrations.
config :regent_points,
  repo: AshTemplate.Repo,
  pubsub: AshTemplate.PubSub,
  accounts: AshTemplate.Points.Accounts,
  chain_client: AshTemplate.ChainClient,
  ash_domains: [RegentPoints],
  program_id: "regents-points-v1",
  starts_at: nil,
  approved_rules: ~w(account.activated social.x social.github social.farcaster agent.activated),
  adapters: %{
    "account.activated" => AshTemplate.Points.AccountActivated,
    "agent.activated" => AshTemplate.Points.PairedAgent,
    "social.farcaster" => AshTemplate.Points.LinkedSocial,
    "social.github" => AshTemplate.Points.LinkedSocial,
    "social.x" => AshTemplate.Points.LinkedSocial,
    "template.first_agent_note" => AshTemplate.Points.AgentNote
  }

# Points runs in this many seasons, one after the other from the start: the
# library's 30-day periods (RegentPoints.Rules.period/1), which it counts without
# end. The Points page and the agent's Points answer list this many
# (AshTemplate.Points.Seasons).
config :ash_template, :points_seasons, 3

# The Claude connector's sign-in, through the person's verified account
# (AshTemplate.OAuth). Its one permission lets the app pair with the account and
# check in; nothing else. config/runtime.exs switches it on and sets its issuer
# and resource from the site's own address. Lifetimes are the library's, not set
# here: a Bearer token lives at most an hour and a refresh token 30 days
# (RegentOAuth.configure/1). A refresh token used again within 30 seconds of its
# rotation is only refused, as the app's own retry; later, it disconnects the app
# (`@refresh_grace_seconds` in RegentOAuth.Protocol).
config :ash_template, AshTemplate.OAuth,
  brand: "platform",
  scope: "regent.identity.manage",
  permission_description:
    "pair with your account using a code you give it, and check in so you see it is active",
  # Once paired, the app works here as that agent (AshTemplate.OAuth.agent_scope/0).
  additional_scopes: %{
    "ash-template.agent" =>
      "work here as the agent you paired, with the same rights as any agent you pair"
  },
  consent_note:
    "This connection works here only as the agent you pair it with, with that agent's rights. Each app you connect here pairs on its own, with its own code from Pair New Agent. It cannot make payments or change your wallets."

# The connector's identity tools (RegentMCPAgents): which site's signers they use
# at the sign-in service, and the words a refused tool call ends with.
# config/runtime.exs switches them on with the connector and gives the key.
config :regent_mcp_agents, :config,
  audience: "ash-template",
  refusal:
    "Call get_identity to see where this connection stands. Not paired: ask your person for a new code from Pair New Agent on their Agents page. Asked to connect: your person connects this app to Ash Template again."

config :phoenix, :filter_parameters, [
  "password",
  "payment_signature",
  "code",
  "code_verifier",
  "access_token",
  "refresh_token",
  "client_secret",
  "id_token",
  "_csrf_token"
]

import_config "#{config_env()}.exs"
