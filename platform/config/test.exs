import Config

# `mix test` runs no server. Each test owns a transaction on the local test
# database that always rolls back (AshTemplate.DatabaseConfig).
config :ash_template, AshTemplateWeb.Endpoint,
  url: [host: "127.0.0.1", port: 4002],
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base:
    "test-only-key-0d5c8f1a7b3e4f6a9c2d8e1b5a7f3c9d0e4b6a8c2f1d7e3b9a5c0f8d6e2a4b1c",
  server: false

# Tests read no chain: with no nodes, a chain read fails in the test instead of
# reaching a public node. A test that needs a chain names its own lab node.
config :ash_template, :chain_nodes, %{}

# Every test signs in to this one Privy app, so shared profiles and sessions a
# test writes match the app the site reads them for.
config :ash_template, :privy, app_id: "test-app"

# Paid pins are paid into this wallet.
config :ash_template, :payments_wallet_address, "0x00000000000000000000000000000000000000a1"

# Jobs are only recorded, never run, while a test holds its transaction.
config :ash_template, Oban, testing: :manual

# A feed's keep-alive comes quickly enough for a test to wait for it.
config :ash_template, AshTemplateWeb.FeedController,
  max_open: 1000,
  max_unpaired: 1000,
  keep_alive_ms: 300

# IndexNow is answered by the test itself (AshTemplate.IndexNow).
config :ash_template, :indexnow_req, plug: {Req.Test, AshTemplate.IndexNow}

# The sign-in service's control API is answered by the test itself (AshTemplate.SiwaControl).
config :ash_template, :siwa_control_req, plug: {Req.Test, AshTemplate.SiwaControl}

config :logger, level: :warning

config :phoenix, :plug_init_mode, :runtime

# Every write inside a transaction runs in one Ash started (`Ash.transact/2`), so
# a notification left unsent fails the test instead of warning in production.
config :ash, :missed_notifications, :raise

# Each test holds a transaction, so every hook meant to run before one
# (`AshTemplate.Limits.LimitWrites`) runs inside it.
config :ash, :warn_on_transaction_hooks?, false
