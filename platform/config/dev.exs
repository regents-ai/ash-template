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
  31_337 => "http://127.0.0.1:58600"
}

# Several sites run side by side locally, each on the port named by PORT.
port = String.to_integer(System.get_env("PORT", "4000"))

config :ash_template, AshTemplateWeb.Endpoint,
  url: [host: "localhost", port: port],
  http: [ip: {127, 0, 0, 1}, port: port],
  check_origin: ["http://localhost:#{port}", "http://127.0.0.1:#{port}"],
  code_reloader: true,
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
