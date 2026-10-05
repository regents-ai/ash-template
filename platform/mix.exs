defmodule AshTemplate.MixProject do
  use Mix.Project

  # Shared Regent libraries, each pinned to one published commit. To move a pin,
  # change its ref and run `mix deps.update <name>`.
  @elixir_utils "https://github.com/regents-ai/elixir-utils.git"
  @elixir_utils_ref "55080723b20d57297855a23ee6e3e50ded77da9a"
  # Agent sign-in hands the sign-in service's own refusal words on, which is newer
  # than the commit the other packages are pinned to.
  @siwa_ref "f30b2f283ba03f0d0aa0adbcba5cee6c5a7de1cc"
  # The Jev client is newer than the commit regent_identity pins regent_privy to.
  @jev_ref "f9bc17c1d5b86b354bde6245cafcd7a9bbea8e76"
  @design_system "https://github.com/regents-ai/design-system.git"
  @design_system_ref "6bc26409835f76f99f91cf6e48bdebd18f1fe8eb"
  @regents "https://github.com/regents-ai/regents.git"
  @regents_ref "c927cdd0031a76ccdd7a49280fc93c455df32b60"

  def project do
    [
      app: :ash_template,
      version: "0.1.0",
      elixir: "~> 1.15",
      elixirc_paths: ["lib"],
      start_permanent: false,
      aliases: aliases(),
      deps: deps(),
      compilers: [:phoenix_live_view] ++ Mix.compilers(),
      listeners: [Phoenix.CodeReloader]
    ]
  end

  def application do
    [
      mod: {AshTemplate.Application, []},
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  defp deps do
    [
      {:lumis, "~> 0.1"},
      {:req_llm, "~> 1.18"},
      {:phoenix, "~> 1.8.9"},
      {:phoenix_live_reload, "~> 1.2", only: :dev},
      {:phoenix_live_view, "~> 1.2.6", override: true},
      {:ash, "~> 3.33.0"},
      {:ash_postgres, "~> 2.13.0"},
      {:ash_phoenix, "~> 2.3.25"},
      {:oban, "~> 2.24"},
      {:ash_oban, "~> 0.9.0"},
      {:ash_ai, "~> 1.1.1"},
      {:igniter, "== 0.8.4", only: :dev, runtime: false},
      {:mdex, "== 0.13.3"},
      {:regent_privy, git: @elixir_utils, ref: @elixir_utils_ref, sparse: "privy"},
      {:regent_identity, git: @regents, ref: @regents_ref, sparse: "identity"},
      {:regent_ui, git: @design_system, ref: @design_system_ref, sparse: "regent_ui"},
      {:regent_agent_access, git: @elixir_utils, ref: @elixir_utils_ref, sparse: "agent_access"},
      {:regent_format, git: @elixir_utils, ref: @elixir_utils_ref, sparse: "format"},
      {:regent_chain, git: @elixir_utils, ref: @elixir_utils_ref, sparse: "chain"},
      {:ens_elixir, git: @elixir_utils, ref: @elixir_utils_ref, sparse: "ens"},
      # ens_elixir names siwa by a sibling path; this pin replaces it.
      {:siwa,
       git: @elixir_utils, ref: @siwa_ref, sparse: "siwa/siwa-elixir/apps/siwa", override: true},
      {:regent_jev, git: @elixir_utils, ref: @jev_ref, sparse: "jev"},
      {:regent_http, git: @elixir_utils, ref: @jev_ref, sparse: "http", override: true},
      {:simple_sat, "~> 0.1"},
      {:sourceror, "~> 1.12", only: :dev, runtime: false},
      {:esbuild, "~> 0.10", runtime: Mix.env() == :dev},
      {:telemetry_metrics, "~> 1.0"},
      {:telemetry_metrics_prometheus_core, "~> 1.2"},
      {:sentry, "~> 13.0"},
      {:jason, "~> 1.2"},
      {:req, "== 0.7.4"},
      {:bandit, "~> 1.12.1"},
      {:credo, "~> 1.7", only: :dev, runtime: false},
      {:ex_slop, "~> 0.4", only: :dev, runtime: false},
      {:credo_ash,
       git: @elixir_utils, ref: @elixir_utils_ref, sparse: "credo_ash", only: :dev, runtime: false},
      {:sobelow, "~> 0.14", only: :dev, runtime: false}
    ]
  end

  # The stylesheet of the one page in Ash AI's own look (`assets/ash_ai_chat/`).
  @ash_ai_chat_css "node_modules/.bin/tailwindcss -i assets/ash_ai_chat/ash_ai_chat.css -o priv/static/assets/css/ash_ai_chat.css"

  defp aliases do
    [
      setup: ["deps.get", "cmd npm ci", "assets.setup", "assets.build"],
      "assets.setup": ["esbuild.install --if-missing"],
      "assets.build": [
        "compile",
        "regent_ui.assets",
        "regent_identity.assets",
        "esbuild ash_template",
        "cmd #{@ash_ai_chat_css}"
      ],
      "assets.deploy": [
        "regent_ui.assets",
        "regent_identity.assets",
        "esbuild ash_template --minify",
        "cmd #{@ash_ai_chat_css} --minify",
        "phx.digest"
      ],
      precommit: [
        "compile --warnings-as-errors",
        "deps.unlock --check-unused",
        "cmd mix hex.audit",
        "format --check-formatted",
        "credo --strict",
        "cmd env SOBELOW_HOME=_build/sobelow mix sobelow --exit",
        # Ash 3.32.1's retained policy-check compile dependencies (ash #2886) set the floor.
        "xref graph --label compile-connected --fail-above 28",
        "ash.codegen --check",
        "ash_template.route_handoff --check",
        "ash_template.sync_api_contract --check"
      ]
    ]
  end
end
