defmodule AshTemplate.MixProject do
  use Mix.Project

  # Shared Regent libraries, each pinned to one published commit. To move a pin,
  # change its ref and run `mix deps.update <name>`.
  @elixir_utils "https://github.com/regents-ai/elixir-utils.git"
  @elixir_utils_ref "28f6ebc80709f5b5e22d4c9b0e900a988afb1dc6"
  @design_system "https://github.com/regents-ai/design-system.git"
  @design_system_ref "4239c53a563461217b25c5c0c1e2228d9e90cf38"
  @regents "https://github.com/regents-ai/regents.git"
  @regents_ref "0d5d18c2f4501a6a5bd00b0bedb005677d8876cc"

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

  # Configuration for the OTP application.
  #
  # Type `mix help compile.app` for more information.
  def application do
    [
      mod: {AshTemplate.Application, []},
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  # Specifies your project dependencies.
  #
  # Type `mix help deps` for examples and options.
  defp deps do
    [
      {:phoenix, "~> 1.8.9"},
      {:phoenix_live_reload, "~> 1.2", only: :dev},
      {:phoenix_live_view, "~> 1.2.6", override: true},
      {:ash, "~> 3.33.0"},
      {:ash_postgres, "~> 2.13.0"},
      {:igniter, "== 0.8.4", only: :dev, runtime: false},
      {:mdex, "== 0.13.3"},
      # regent_identity names regent_privy by a sibling path; this pin replaces it.
      {:regent_privy,
       git: @elixir_utils, ref: @elixir_utils_ref, sparse: "privy", override: true},
      {:regent_identity, git: @regents, ref: @regents_ref, sparse: "identity"},
      {:regent_ui, git: @design_system, ref: @design_system_ref, sparse: "regent_ui"},
      {:regent_agent_access, git: @elixir_utils, ref: @elixir_utils_ref, sparse: "agent_access"},
      {:regent_format, git: @elixir_utils, ref: @elixir_utils_ref, sparse: "format"},
      {:regent_chain, git: @elixir_utils, ref: @elixir_utils_ref, sparse: "chain"},
      {:simple_sat, "~> 0.1"},
      {:sourceror, "~> 1.12", only: :dev, runtime: false},
      {:esbuild, "~> 0.10", runtime: Mix.env() == :dev},
      {:telemetry_metrics, "~> 1.0"},
      {:telemetry_metrics_prometheus_core, "~> 1.2"},
      {:telemetry_poller, "~> 1.0"},
      {:sentry, "~> 13.0"},
      {:jason, "~> 1.2"},
      {:req, "== 0.6.2"},
      {:bandit, "~> 1.12.1"},
      {:credo, "~> 1.7", only: :dev, runtime: false},
      {:ex_slop, "~> 0.4", only: :dev, runtime: false},
      {:credo_ash,
       git: @elixir_utils, ref: @elixir_utils_ref, sparse: "credo_ash", only: :dev, runtime: false},
      {:sobelow, "~> 0.14", only: :dev, runtime: false}
    ]
  end

  # Aliases are shortcuts or tasks specific to the current project.
  # For example, to install project dependencies and perform other setup tasks, run:
  #
  #     $ mix setup
  #
  # See the documentation for `Mix` for more info on aliases.
  defp aliases do
    [
      setup: ["deps.get", "cmd npm ci", "assets.setup", "assets.build"],
      "assets.setup": ["esbuild.install --if-missing"],
      "assets.build": [
        "compile",
        "regent_ui.assets",
        "regent_identity.assets",
        "esbuild ash_template"
      ],
      "assets.deploy": [
        "regent_ui.assets",
        "regent_identity.assets",
        "esbuild ash_template --minify",
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
        "ash_template.route_handoff --check"
      ]
    ]
  end
end
