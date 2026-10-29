defmodule AshTemplate.MixProject do
  use Mix.Project

  # Shared Regent libraries, each pinned to one published commit. To move a pin,
  # change its ref and run `mix deps.update <name>`.
  @elixir_utils "https://github.com/regents-ai/elixir-utils.git"
  @elixir_utils_ref "b375f122bda54f7e7c9d29653e47c208fd4b675d"
  @design_system "https://github.com/regents-ai/design-system.git"
  @design_system_ref "7a853f854168f208975815286eace8a502ec9aea"

  def project do
    [
      app: :ash_template,
      version: "0.1.0",
      elixir: "~> 1.20",
      elixirc_paths: elixirc_paths(Mix.env()),
      # The browser walk's files under test/browser are run by Playwright, not ExUnit.
      test_ignore_filters: [&String.starts_with?(&1, "test/browser/")],
      start_permanent: false,
      aliases: aliases(),
      deps: deps(),
      compilers: [:ash_signals, :phoenix_live_view] ++ Mix.compilers(),
      listeners: [Phoenix.CodeReloader],
      usage_rules: usage_rules()
    ]
  end

  # The browser walk's server runs in development, with its guard against the
  # outside world (`AshTemplate.WalkOffline`).
  defp elixirc_paths(:dev), do: ["lib", "test/browser/support/server"]
  defp elixirc_paths(_env), do: ["lib"]

  def application do
    [
      mod: {AshTemplate.Application, []},
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  defp deps do
    [
      # regent_mcp_agents names regent_oauth, regent_agents and regent_agent_access
      # by sibling paths; these pins replace them.
      {:regent_oauth,
       git: @elixir_utils, ref: @elixir_utils_ref, sparse: "oauth", override: true},
      # The Claude connector's identity tools at /mcp (AshTemplate.Agents.Connection).
      {:regent_mcp_agents, git: @elixir_utils, ref: @elixir_utils_ref, sparse: "mcp_agents"},
      {:lumis, "~> 0.1"},
      {:req_llm, "~> 1.18"},
      {:castore, "~> 1.0"},
      {:phoenix, "~> 1.8.9"},
      {:phoenix_live_reload, "~> 1.2", only: :dev},
      {:phoenix_live_view, "~> 1.2.6", override: true},
      # Reads whole pages in LiveView tests.
      {:lazy_html, "~> 0.1", only: :test},
      {:ash, "~> 3.37"},
      # ash_postgres main with #910 until a Hex release carries it: upserts use the
      # repo's prefix, which picks each site's schema on the shared database. It
      # stands in for the Hex release that ash_money and ash_double_entry ask for.
      {:ash_postgres,
       git: "https://github.com/ash-project/ash_postgres.git",
       ref: "55db7d449aad351d200c5f300fca2a83e0a8734c",
       override: true},
      {:ash_phoenix, "~> 2.3.26"},
      {:oban, "~> 2.24"},
      {:nebulex, "~> 3.0"},
      {:nebulex_local, "~> 3.0"},
      {:ash_oban, "~> 0.10.3"},
      {:ash_ai, "~> 1.4.1"},
      {:igniter, "== 0.8.4", only: :dev, runtime: false},
      {:usage_rules, "~> 1.2.8", only: :dev, runtime: false},
      {:mdex, "== 0.14.2"},
      # regent_identity pins its own elixir-utils commit; this pin replaces it.
      {:regent_privy,
       git: @elixir_utils, ref: @elixir_utils_ref, sparse: "privy", override: true},
      {:regent_identity,
       git: @elixir_utils, ref: @elixir_utils_ref, sparse: "ash_components/identity"},
      {:regent_agents,
       git: @elixir_utils, ref: @elixir_utils_ref, sparse: "ash_components/agents", override: true},
      {:regent_ui, git: @design_system, ref: @design_system_ref, sparse: "regent_ui"},
      {:regent_agent_access,
       git: @elixir_utils, ref: @elixir_utils_ref, sparse: "agent_access", override: true},
      # regent_identity and regent_agents name regent_format by path; this pin replaces it.
      {:regent_format,
       git: @elixir_utils, ref: @elixir_utils_ref, sparse: "format", override: true},
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
      # The site's unexpected-failure lines (RegentHttp.UnexpectedFailure). regent_jev
      # names regent_http by a sibling path; this pin replaces it.
      {:regent_http, git: @elixir_utils, ref: @elixir_utils_ref, sparse: "http", override: true},
      {:simple_sat, "~> 0.1"},
      # Cachex 4.1.1 on consuming sites requires 6.x; Nebulex accepts 6.x or 7.x.
      {:ex_hash_ring, "== 6.0.4"},
      {:sourceror, "~> 1.12", only: :dev, runtime: false},
      {:esbuild, "~> 0.10", runtime: Mix.env() == :dev},
      {:logger_json, "~> 7.0"},
      {:telemetry_metrics, "~> 1.0"},
      {:peep, "~> 5.0"},
      {:telemetry_poller, "~> 1.3"},
      {:error_tracker, "~> 0.9"},
      # 3.1.1 has the EEF-CVE-2026-97853 advisory in Decimal.round/3.
      {:decimal, "== 3.2.0"},
      {:jason, "~> 1.2"},
      {:req, "== 0.7.5"},
      {:bandit, "~> 1.14"},
      {:credo, "~> 1.7", only: :dev, runtime: false},
      {:ex_slop, "~> 0.4", only: :dev, runtime: false},
      {:credo_ash,
       git: @elixir_utils, ref: @elixir_utils_ref, sparse: "credo_ash", only: :dev, runtime: false},
      {:sobelow, "~> 0.16", only: :dev, runtime: false},
      # Property tests. Ash already ships it in every environment, so it cannot be test-only.
      {:stream_data, "~> 1.4"}
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
          regent_oauth: "oauth",
          regent_mcp_agents: "mcp_agents",
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
      test: ["ecto.create --quiet", "ash_template.setup_local_auth", "test"],
      "assets.setup": ["esbuild.install --if-missing"],
      "assets.build": [
        "compile",
        "regent_ui.assets",
        "regent_identity.assets",
        "regent_agent_access.assets",
        "esbuild ash_template"
      ],
      "assets.deploy": [
        "regent_ui.assets",
        "regent_identity.assets",
        "regent_agent_access.assets",
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
        # ErrorTracker's dashboard route adds one link: the router reads its on_mount at compile time.
        # Each Ash domain adds one for each of its resources (it reads them at compile time), and
        # each signed-agent controller adds one (it reads AgentWallet's refusals into its error table).
        # A generic action adds one for the module it runs (Ash checks `run` at compile time).
        # The capability check adds one: it names the chat domain, whose tools are never hosted.
        # The hosted MCP forward adds two: the router reads its tools from the capability list,
        # and its input check from ToolErrors (AshAi takes it only as a function), at compile time.
        # The identity tools' policy check adds one (`Agents.Connection.Caller`: Ash reads an
        # `authorize_if` check module at compile time).
        "xref graph --label compile-connected --fail-above 43",
        "ash.codegen --check",
        "usage_rules.sync --check",
        "ash_template.route_handoff --check",
        "ash_template.sync_api_contract --check",
        "regent_ui.assets",
        "regent_identity.assets",
        "regent_agent_access.assets",
        "cmd npm run typecheck",
        "cmd npm test",
        # The browser walk (test/browser): every page at phone and desktop width,
        # and the paths a person takes, on its own server and database.
        "cmd npm run test:browser"
      ]
    ]
  end
end
