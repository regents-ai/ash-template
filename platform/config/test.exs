import Config

# `mix test` runs no server. Each test owns a transaction on the local test
# database that always rolls back (AshTemplate.DatabaseConfig).
config :ash_template, AshTemplateWeb.Endpoint,
  url: [host: "127.0.0.1", port: 4002],
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base:
    "test-only-key-0d5c8f1a7b3e4f6a9c2d8e1b5a7f3c9d0e4b6a8c2f1d7e3b9a5c0f8d6e2a4b1c",
  server: false

# Jobs are only recorded, never run, while a test holds its transaction.
config :ash_template, Oban, testing: :manual

config :logger, level: :warning

config :phoenix, :plug_init_mode, :runtime
