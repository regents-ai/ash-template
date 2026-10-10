defmodule AshTemplate.MixProject do
  use Mix.Project

  # Shared Regent libraries, each pinned to one published commit. To move a pin,
  # change its ref and run `mix deps.update <name>`.
  @elixir_utils "https://github.com/regents-ai/elixir-utils.git"
  @elixir_utils_ref "96fe9d3f386742ce93b04c6dfca183d99cc00787"
  @design_system "https://github.com/regents-ai/design-system.git"
  @design_system_ref "11b61865e3d3c7b5e64599cca187c434498425a6"

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
      listeners: [Phoenix.CodeReloader],
      usage_rules: usage_rules()
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
      {:ash, "~> 3.34 and >= 3.34.6"},
      {:ash_postgres, "== 2.13.0"},
      {:ash_phoenix, "~> 2.3.25"},
      {:oban, "~> 2.24"},
      {:ash_oban, "~> 0.9.0"},
      {:ash_ai, "~> 1.1.1"},
      {:igniter, "== 0.8.4", only: :dev, runtime: false},
      {:usage_rules, "~> 1.2.8", only: :dev, runtime: false},
      {:mdex, "== 0.13.3"},
      # regent_identity pins its own elixir-utils commit; this pin replaces it.
      {:regent_privy,
       git: @elixir_utils, ref: @elixir_utils_ref, sparse: "privy", override: true},
      {:regent_identity,
       git: @elixir_utils, ref: @elixir_utils_ref, sparse: "ash_components/identity"},
      {:regent_agents,
       git: @elixir_utils, ref: @elixir_utils_ref, sparse: "ash_components/agents", override: true},
      {:regent_ui, git: @design_system, ref: @design_system_ref, sparse: "regent_ui"},
      {:regent_agent_access, git: @elixir_utils, ref: @elixir_utils_ref, sparse: "agent_access"},
      {:regent_format, git: @elixir_utils, ref: @elixir_utils_ref, sparse: "format"},
      # regent_credits names regent_chain by a sibling path; this pin replaces it.
      {:regent_chain,
       git: @elixir_utils, ref: @elixir_utils_ref, sparse: "chain", override: true},
      {:regent_points, git: @elixir_utils, ref: @elixir_utils_ref, sparse: "points"},
      {:regent_credits, git: @elixir_utils, ref: @elixir_utils_ref, sparse: "credits"},
      {:ens_elixir, git: @elixir_utils, ref: @elixir_utils_ref, sparse: "ens"},
      # ens_elixir names siwa by a sibling path; this pin replaces it.
      {:siwa,
       git: @elixir_utils,
       ref: @elixir_utils_ref,
       sparse: "siwa/siwa-elixir/apps/siwa",
       override: true},
      {:regent_jev, git: @elixir_utils, ref: @elixir_utils_ref, sparse: "jev"},
      # regent_jev names regent_http by a sibling path; this pin replaces it.
      {:regent_http, git: @elixir_utils, ref: @elixir_utils_ref, sparse: "http", override: true},
      {:simple_sat, "~> 0.1"},
      {:sourceror, "~> 1.12", only: :dev, runtime: false},
      {:esbuild, "~> 0.10", runtime: Mix.env() == :dev},
      {:telemetry_metrics, "~> 1.0"},
      {:telemetry_metrics_prometheus_core, "~> 1.2"},
      {:telemetry_poller, "~> 1.3"},
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
    |> local_shared_dependencies()
  end

  # Local verification of an unreleased shared change. Production always uses
  # reviewed published pins; this override cannot enter a release build.
  defp local_shared_dependencies(deps) do
    case {Mix.env(), System.get_env("REGENT_ELIXIR_UTILS_PATH")} do
      {:prod, nil} ->
        deps

      {:prod, _} ->
        raise "local shared libraries are forbidden in production"

      {_, nil} ->
        deps

      {_, root} ->
        paths = %{
          regent_agents: "ash_components/agents",
          regent_identity: "ash_components/identity",
          regent_points: "points",
          regent_privy: "privy",
          regent_credits: "credits",
          regent_chain: "chain",
          regent_agent_access: "agent_access",
          siwa: "siwa/siwa-elixir/apps/siwa"
        }

        Enum.map(deps, &local_dependency(&1, paths, root))
    end
  end

  defp local_dependency({name, _opts} = dep, paths, root) do
    case paths[name] do
      nil -> dep
      path -> {name, path: Path.join(root, path), override: true}
    end
  end

  defp local_dependency(dep, _paths, _root), do: dep

  # The stylesheet of the one page in Ash AI's own look (`assets/ash_ai_chat/`).
  @ash_ai_chat_css "node_modules/.bin/tailwindcss -i assets/ash_ai_chat/ash_ai_chat.css -o priv/static/assets/css/ash_ai_chat.css"

  # `mix usage_rules.sync` writes the marked block at the end of AGENTS.md: how to
  # read the installed version's docs, and links to each package's own rules in deps/.
  defp usage_rules do
    [
      file: "AGENTS.md",
      usage_rules: [
        {:usage_rules, sub_rules: []},
        {:usage_rules, sub_rules: :all, main: false, link: :markdown},
        {:ash, link: :markdown},
        {~r/^ash_/, link: :markdown},
        {:phoenix, sub_rules: ["phoenix", "liveview", "html"], link: :markdown},
        {:req_llm, link: :markdown}
      ]
    ]
  end

  defp aliases do
    [
      setup: ["deps.get", "cmd npm ci", "assets.setup", "assets.build"],
      test: ["ash_template.setup_local_auth", "test"],
      "assets.setup": ["esbuild.install --if-missing"],
      "assets.build": [
        "compile",
        "regent_ui.assets",
        "regent_identity.assets",
        "regent_agent_access.assets",
        "esbuild ash_template",
        "cmd #{@ash_ai_chat_css}"
      ],
      "assets.deploy": [
        "regent_ui.assets",
        "regent_identity.assets",
        "regent_agent_access.assets",
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
        "usage_rules.sync --check",
        "ash_template.route_handoff --check",
        "ash_template.sync_api_contract --check"
      ]
    ]
  end
end
