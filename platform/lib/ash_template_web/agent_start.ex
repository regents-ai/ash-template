defmodule AshTemplateWeb.AgentStart do
  @moduledoc """
  The steps that connect a person's agent to their account, for each agent the
  site names. The `/start` page shows them to people and serves the same text
  as Markdown to agents, so the two never differ.
  """

  alias AshTemplateWeb.PublicDocuments

  @site_name "Ash Template"
  @cli_site "ash-template"

  # How each agent reaches the site: the regents command line, or the SIWA sign-in
  # client served by siwa.regents.sh for agents that run Python without it.
  @agents [
    %{id: "hermes", label: "Hermes", name: "Hermes", harness: "hermes", client: :cli},
    %{id: "codex", label: "Codex", name: "Codex", harness: "codex", client: :cli},
    %{id: "grok_bot", label: "Grok Bot", name: "Grok Bot", harness: "grok_bot", client: :siwa},
    %{id: "muse", label: "Muse", name: "Muse", harness: "muse", client: :siwa},
    %{id: "dots", label: "Dots", name: "Dots", harness: "dots", client: :siwa},
    %{
      id: "other",
      label: "Other agents",
      name: "<your name>",
      harness: "<harness>",
      client: :cli
    }
  ]

  @harnesses "hermes, grok_bot, muse, openclaw, nemoclaw, ironclaw, pi, claude_code, codex, cursor, gemini_cli, dots or other"

  def agents, do: @agents

  defp origin, do: PublicDocuments.url("")

  @doc "The agent `id` names, or the first agent."
  def agent(id), do: Enum.find(@agents, hd(@agents), &(&1.id == id))

  @doc "The address of the steps for an agent on `harness`."
  def link(harness) do
    id = Atom.to_string(harness)
    id = if Enum.any?(@agents, &(&1.id == id)), do: id, else: "other"
    "#{origin()}/start?agent=#{id}"
  end

  @doc "What a person gives their agent: the steps for its client, ready to paste."
  def instruction(%{client: :cli} = agent) do
    """
    Connect to my #{@site_name} account. I'll paste you a message with a pairing code; I make it on my account page at #{origin()}/account.

    1. Install the Regents command line, version 1.9.3:
       uv tool install regents-cli==1.9.3
    2. Sign in. This makes your agent key the first time, so ask me first. Never show the key.
       regents auth login --site #{@cli_site}
    3. Pair. With your file tool, not the shell, write this into pair.json in your home folder, never inside a project:
       #{pair_file(agent)}
       Then pair from that file and delete it, whether pairing worked or not. Never repeat the code in a reply.
       regents #{@cli_site} agents pair --json < ~/pair.json
       rm ~/pair.json
    4. Check in:
       regents #{@cli_site} agents whoami --json
    5. Read my account when I ask:
       regents #{@cli_site} notes list
       regents #{@cli_site} account balances
       regents #{@cli_site} account points
       regents #{@cli_site} account credits-history
    #{other_harness(agent)}#{broker_note(agent)}
    Ask me before you post in a room, pin a note (it costs 1 Credit) or delete anything.\
    """
  end

  def instruction(%{client: :siwa} = agent) do
    """
    Connect to my #{@site_name} account. I'll paste you a message with a pairing code; I make it on my account page at #{origin()}/account.

    1. Get the Regent sign-in client:
       curl -fsSO https://siwa.regents.sh/agent/siwa_agent.py
    2. Make your key if you have none. Keep an existing one; never show it.
       uv run siwa_agent.py keygen
    3. Pair. With your file tool, not the shell, write this into pair.json in your home folder, never inside a project:
       #{pair_file(agent)}
       Then pair from that file and delete it, whether pairing worked or not. Never repeat the code in a reply.
       uv run siwa_agent.py pair #{origin()} < ~/pair.json
       rm ~/pair.json
    4. Check in:
       uv run siwa_agent.py me #{origin()}
    5. Read my account when I ask:
       uv run siwa_agent.py request GET #{origin()}/tools/notes
       uv run siwa_agent.py request GET #{origin()}/tools/account/balances
       uv run siwa_agent.py request GET #{origin()}/tools/account/points
       uv run siwa_agent.py request POST #{origin()}/tools/account/credits/history --body '{}'
    #{broker_note(agent)}
    Ask me before you post in a room, pin a note (it costs 1 Credit) or delete anything.\
    """
  end

  defp pair_file(agent),
    do: ~s({"code": "<code>", "name": "#{agent.name}", "harness": "#{agent.harness}"})

  defp other_harness(%{id: "other"}), do: "\nharness is one of: #{@harnesses}.\n"
  defp other_harness(_agent), do: ""

  defp broker_note(%{id: "muse"}),
    do:
      "\nIf siwa.regents.sh doesn't answer from your host, set SIWA_BROKER=https://siwa-server.fly.dev and try again.\n"

  defp broker_note(_agent), do: ""

  @doc "The page as Markdown, for agents that ask for it."
  def markdown do
    """
    # Connect your agent to #{@site_name}

    Your agent pairs with your #{@site_name} account and works for you: it reads and writes your notes, posts in rooms and reads your Credits and Points. It can never use your wallet, change your account or pair other agents.

    1. Your person makes a pairing code on their account page: #{origin()}/account. A code works once, for ten minutes.
    2. Follow the steps for your agent below, with that code.
    3. Your agent then shows on their account page under its name.

    A refusal names what went wrong: `pairing_failed` means the code is used, expired or mistyped, so ask for a new one; `agent_not_paired` means you were unpaired.

    #{Enum.map_join(@agents, "\n", &section/1)}\
    """
  end

  defp section(agent) do
    """
    ## #{agent.label}

    ```text
    #{instruction(agent)}
    ```
    """
  end
end
