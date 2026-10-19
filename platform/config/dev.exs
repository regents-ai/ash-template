import Config

# The wallet-button workshop at /showcase/onchain sends to a lab chain on this
# machine: `anvil --port 58600`.
config :ash_template, :lab_chain, %{
  chain_id: 31_337,
  name: "Lab chain",
  rpc_url: "http://127.0.0.1:58600"
}

config :ash_template, :chain_nodes, %{
  84_532 => "https://sepolia.base.org",
  8453 => "https://mainnet.base.org",
  1 => "https://ethereum-rpc.publicnode.com",
  31_337 => "http://127.0.0.1:58600"
}

# The browser walk's server (playwright.config.ts) never leaves the machine. Its
# chain nodes and sign-in service are a closed port on this machine, so their reads
# fail at once, and any other request outside it is refused and fails the walk
# (AshTemplate.WalkOffline).
if System.get_env("ASH_TEMPLATE_WALK") == "true" do
  closed = "http://127.0.0.1:9"

  config :ash_template, :chain_nodes, %{
    84_532 => closed,
    8453 => closed,
    1 => closed,
    31_337 => closed
  }

  config :regent_agents, :siwa, url: closed, audience: "ash-template"
  config :req, default_options: [adapter: AshTemplate.WalkOffline]
  config :ash_template, :walk_outside_file, Path.expand("../tmp/walk-outside.txt", __DIR__)
end

# Several sites run side by side locally, each on the port named by PORT.
port = String.to_integer(System.get_env("PORT", "4000"))

config :ash_template, AshTemplateWeb.Endpoint,
  url: [host: "localhost", port: port],
  http: [ip: {127, 0, 0, 1}, port: port],
  check_origin: ["http://localhost:#{port}", "http://127.0.0.1:#{port}"],
  code_reloader: true,
  # Signal listeners added while the server runs are picked up on reload.
  reloadable_compilers: [:ash_signals, :phoenix_live_view, :elixir, :app],
  # `make readiness` sets this to off, so error pages answer as they do in a release.
  debug_errors: System.get_env("ASH_TEMPLATE_DEBUG_ERRORS", "on") == "on",
  secret_key_base: "6ihHqnWB0px5FXmoddiKg3V2NLeiM0k0UsFs5DwmIADSX35FFdeSs5VNICCc3iU5",
  watchers: [
    esbuild: {Esbuild, :install_and_run, [:ash_template, ~w(--sourcemap=inline --watch)]}
  ],
  live_reload: [
    web_console_logger: true,
    patterns: [
      ~r"priv/static/(?!uploads/).*\.(js|css|png|jpeg|jpg|gif|svg)$"E,
      ~r"lib/ash_template_web/router\.ex$"E,
      ~r"lib/ash_template_web/(controllers|live|components)/.*\.(ex|heex)$"E
    ]
  ]

config :logger, :default_formatter, format: "[$level] $message\n"

config :phoenix, :stacktrace_depth, 20

config :phoenix, :plug_init_mode, :runtime

config :phoenix_live_view,
  debug_heex_annotations: true,
  debug_attributes: true,
  enable_expensive_runtime_checks: true
