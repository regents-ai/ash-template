defmodule AshTemplateWeb.AgentsPanel do
  @moduledoc """
  The agents a person has paired with their account (`RegentAgents`), in the
  shared agents list (`Regent.Account.agents`), a way to pair another by
  choosing it and pasting it a message, and a larger view of one agent with
  what it has done across the Regent sites (`AshTemplate.AgentActivity`) and
  Unpair.

  Pairing immediately lets an agent read and change the person's notes and
  post, edit and delete their room messages, each marked as its own. World ID
  is optional. It never touches their wallet (`AshTemplateWeb.Plugs.AgentWallet`).
  Pairing is shared by every Regent site, so an agent paired on another one is
  listed here too.

  The parent passes `account` (the signed-in account), its `session_lease` as
  `lease` and `id`, and sends `agents_changed: true` when an agent pairs, checks
  in or is unpaired anywhere.
  """
  use AshTemplateWeb, :live_component

  alias AshTemplate.AgentActivity
  alias AshTemplateWeb.Live.Session
  alias Regent.Primitives, as: P
  alias RegentAgents.{Harness, HumanBacking, PairedAgent, PairingCode, Person}

  # Stands in for a code before one is made, so the message keeps its size.
  @no_code String.duplicate("X", 24)

  @logos %{
    hermes: "/images/agents/hermes.png",
    grok_bot: "/images/agents/grok-bot.png",
    muse: "/images/agents/muse.png",
    openclaw: "/images/agents/openclaw.png",
    nemoclaw: "/images/agents/nemoclaw.png",
    ironclaw: "/images/agents/ironclaw.png",
    pi: "/images/agents/pi.svg",
    claude_code: "/images/agents/claude-code.png",
    codex: "/images/agents/codex.png",
    cursor: "/images/agents/cursor.png",
    gemini_cli: "/images/agents/gemini-cli.png",
    dots: "/images/agents/dots.png",
    other: "/images/agents/other.svg"
  }

  @impl true
  def mount(socket),
    do:
      {:ok,
       socket
       |> Session.check_component_lease(&take_account/2)
       |> assign(pairing: nil, detail: nil, notice: nil)}

  @impl true
  def update(%{agents_changed: true}, socket), do: {:ok, read_agents(socket)}

  def update(%{account: account, id: id, lease: lease}, socket) do
    {:ok,
     socket
     |> assign(id: id, lease: lease)
     |> take_account(account)
     |> read_agents()}
  end

  # The account as the page gave it, or as it reads now before each event and
  # each background result (`Session.check_component_lease/2`).
  defp take_account(socket, account),
    do: assign(socket, person: %Person{privy_user_id: account.privy_user_id})

  # Choosing an agent, or asking again for the chosen one, makes a code with that
  # agent's message; codes made before keep working until they expire.
  @impl true
  def handle_event("issue_pairing_code", %{"harness" => harness}, socket) do
    case Harness.match(harness) do
      {:ok, harness} -> {:noreply, issue(socket, harness)}
      :error -> {:noreply, socket}
    end
  end

  def handle_event("open_agent", %{"id" => id}, socket),
    do: {:noreply, socket |> assign(notice: nil) |> show_agent(id)}

  def handle_event("close_agent", _params, socket),
    do: {:noreply, assign(socket, detail: nil, notice: nil)}

  def handle_event("load_more_activity", %{"id" => id}, socket),
    do: {:noreply, load_more_activity(socket, id)}

  def handle_event("unpair_agent", %{"id" => id}, socket) do
    actor = socket.assigns.person

    notice =
      with {:ok, id} <- Ecto.UUID.cast(id),
           {:ok, %PairedAgent{} = agent} <- RegentAgents.get_my_agent(id, actor: actor),
           :ok <- RegentAgents.unpair_agent(agent, actor: actor) do
        {:status, "#{agent.name} is unpaired. It will need a new code to pair again."}
      else
        {:ok, nil} ->
          {:alert, "This agent is no longer paired with your account. Nothing changed."}

        _failed ->
          {:alert, "Your agents couldn’t be updated just now. Nothing changed. Try again."}
      end

    {:noreply, socket |> read_agents() |> assign(notice: notice)}
  end

  # The newest page of what the open agent has done and its registry listing,
  # landing only while that agent is still open and its older activity has not
  # been asked for.
  @impl true
  def handle_async({:agent_activity, id}, result, socket) do
    case socket.assigns.detail do
      %{agent: %{id: ^id}, paged: false} = detail ->
        {:noreply, assign(socket, detail: first_page(detail, result))}

      _moved_on ->
        {:noreply, socket}
    end
  end

  # The next page of the open agent's activity, added below what is shown.
  def handle_async({:more_agent_activity, id}, result, socket) do
    case socket.assigns.detail do
      %{agent: %{id: ^id}, more: :loading} = detail ->
        {:noreply, assign(socket, detail: next_page(detail, result))}

      _moved_on ->
        {:noreply, socket}
    end
  end

  defp first_page(detail, {:ok, {:ok, page}}),
    do: %{detail | activity: page.entries, next: page.next, listing: page.listing}

  defp first_page(detail, _failed), do: %{detail | activity: :unavailable}

  defp next_page(detail, {:ok, {:ok, page}}),
    do: %{detail | activity: detail.activity ++ page.entries, next: page.next, more: :idle}

  defp next_page(detail, _failed), do: %{detail | more: :unavailable}

  @impl true
  def render(assigns) do
    ~H"""
    <div class="account-agents">
      <Regent.Account.agents
        id={@id}
        agents={rows(@agents, @now)}
        notice={if is_nil(@detail), do: notice_text(@notice)}
      >
        <:actions :let={agent}>
          <P.button
            type="button"
            variant="quiet"
            phx-click="open_agent"
            phx-value-id={agent.id}
            phx-target={@myself}
            aria-label={"See what #{agent.name} has done"}
          >
            See what it has done
          </P.button>
        </:actions>
        <:footer>
          <div class="account-agents__pair">
            <h3 id={"#{@id}-pair-title"}>
              Select your personal agent you will pair to your Ash Template account
            </h3>
            <form id={"#{@id}-choose"} phx-change="issue_pairing_code" phx-target={@myself}>
              <fieldset class="account-agents__choices" aria-labelledby={"#{@id}-pair-title"}>
                <label :for={harness <- Harness.values()} class="account-agents__choice">
                  <input
                    type="radio"
                    name="harness"
                    value={harness}
                    checked={match?(%{harness: ^harness}, @pairing)}
                    class="visually-hidden"
                  />
                  <.harness_mark harness={harness} />{Harness.label(harness)}
                </label>
              </fieldset>
            </form>
            <.pairing id={@id} pairing={@pairing} myself={@myself} />
          </div>

          <.agent_dialog
            :if={@detail}
            detail={@detail}
            same_person={same_person(@agents, @detail.agent)}
            notice={@notice}
            now={@now}
            myself={@myself}
          />
        </:footer>
      </Regent.Account.agents>
    </div>
    """
  end

  # Each agent as the shared list shows it, newest first as the account reads them.
  defp rows(:unavailable, _now), do: :unavailable

  defp rows(agents, now) do
    Enum.map(agents, fn agent ->
      %{
        id: agent.id,
        name: agent.name,
        harness: Harness.label(agent.harness),
        backed: HumanBacking.describe(agent).human_backed,
        last_contact_iso: DateTime.to_iso8601(agent.last_contact_at),
        last_contact: RegentFormat.relative_time(agent.last_contact_at, now)
      }
    end)
  end

  defp notice_text({_role, text}), do: text
  defp notice_text(nil), do: nil

  attr :id, :string, required: true
  attr :pairing, :map, default: nil
  attr :myself, :any, required: true

  # One layout for every state, so choosing an agent never changes the panel's
  # height: each agent's message sits in the same place, and what a state lacks
  # keeps its space, unseen.
  defp pairing(assigns) do
    {harness, code} =
      case assigns.pairing do
        %{harness: harness, code: code} -> {harness, code}
        nil -> {nil, nil}
      end

    issued = match?(%PairingCode.Issued{}, code)
    shown_code = if issued, do: code.code, else: @no_code

    assigns =
      assign(assigns,
        harness: harness,
        code: code,
        issued: issued,
        message: if(issued, do: agent_message(shown_code, harness)),
        messages: Harness.values() |> Enum.map(&agent_message(shown_code, &1)) |> Enum.uniq(),
        expires_at: if(issued, do: code.expires_at)
      )

    ~H"""
    <div id={"#{@id}-pairing"} class="account-agents__code">
      <ol class="account-agents__steps">
        <li>Copy this message.</li>
        <li>Paste it to your agent wherever you chat with it.</li>
        <li>Your agent appears here once it pairs. This page updates on its own.</li>
      </ol>
      <div class="account-agents__message" role="status">
        <pre :for={message <- @messages} data-unused={message != @message}><code>{message}</code></pre>
        <.pairing_words code={@code} />
      </div>
      <div class="account-agents__actions">
        <P.copy_button
          id={"#{@id}-copy"}
          text={@message || ""}
          variant="primary"
          data-unused={!@issued}
        >
          Copy message
        </P.copy_button>
        <P.button
          id={"#{@id}-pair"}
          type="button"
          variant="secondary"
          phx-click="issue_pairing_code"
          phx-value-harness={@harness}
          phx-target={@myself}
          phx-disable-with="Making a code…"
          data-unused={is_nil(@harness)}
        >
          Make a new code
        </P.button>
      </div>
      <p class="account-agents__expiry" data-unused={!@issued}>
        The code works once, until <.expiry expires_at={@expires_at} />.
      </p>
    </div>
    """
  end

  attr :code, :any, required: true

  defp pairing_words(%{code: nil} = assigns) do
    ~H"""
    <p class="account-agents__words">Choose your agent to get its message.</p>
    """
  end

  defp pairing_words(%{code: {:paired, agent}} = assigns) do
    assigns = assign(assigns, :agent, agent)

    ~H"""
    <p class="account-agents__words account-agents__paired">
      {@agent.name} paired with your account. It is listed above.
    </p>
    """
  end

  defp pairing_words(%{code: :unavailable} = assigns) do
    ~H"""
    <p class="account-agents__words">
      A pairing code couldn’t be made right now. Try again in a moment.
    </p>
    """
  end

  defp pairing_words(assigns), do: ~H""

  attr :expires_at, :any, required: true, doc: "a `DateTime`, or nil before a code is made"

  defp expiry(%{expires_at: nil} = assigns), do: ~H"<time>00:00 UTC</time>"

  defp expiry(assigns) do
    ~H"""
    <time datetime={DateTime.to_iso8601(@expires_at)}>{Calendar.strftime(@expires_at, "%H:%M UTC")}</time>
    """
  end

  attr :id, :string, required: true
  attr :notice, :any, required: true

  defp agent_notice(%{notice: {role, text}} = assigns) do
    assigns = assign(assigns, role: role, text: text)

    ~H"""
    <p id={@id} class="account-agents__notice" role={to_string(@role)}>{@text}</p>
    """
  end

  defp agent_notice(assigns), do: ~H""

  # The person's other agents paired with this account, grouped by the World ID
  # person saved behind each.
  defp same_person(agents, %{id: id, human_id: human_id})
       when is_list(agents) and is_binary(human_id),
       do: Enum.filter(agents, &(&1.human_id == human_id and &1.id != id))

  defp same_person(_agents, _agent), do: []

  attr :detail, :map, required: true
  attr :same_person, :list, required: true
  attr :notice, :any, required: true
  attr :now, DateTime, required: true
  attr :myself, :any, required: true

  defp agent_dialog(assigns) do
    ~H"""
    <dialog
      id="account-agent-dialog"
      class="account-agent-dialog"
      aria-labelledby="account-agent-dialog-title"
      phx-hook="InfoDialog"
      data-open
      data-close-event="close_agent"
    >
      <header class="account-agent-dialog__header">
        <.harness_mark harness={@detail.agent.harness} />
        <div>
          <p class="account-kicker">{Harness.label(@detail.agent.harness)}</p>
          <h2 id="account-agent-dialog-title">{@detail.agent.name}</h2>
        </div>
      </header>

      <dl class="account-agent-dialog__facts">
        <div>
          <dt>First paired</dt>
          <dd>{moment(@detail.agent.paired_at)}</dd>
        </div>
        <div>
          <dt>Last contact</dt>
          <dd>
            {RegentFormat.relative_time(@detail.agent.last_contact_at, @now)}
            <span>{moment(@detail.agent.last_contact_at)}</span>
          </dd>
        </div>
        <div>
          <dt>Agent address</dt>
          <dd><code>{@detail.agent.wallet}</code></dd>
        </div>
        <div :if={@detail.listing}>
          <dt>Registry listing</dt>
          <dd>
            <a
              id="account-agent-registry-listing"
              href={@detail.listing.url}
              target="_blank"
              rel="noopener noreferrer"
            >
              Agent #{@detail.listing.number}
            </a>
          </dd>
        </div>
        <div id="account-agent-human">
          <dt>Person</dt>
          <dd>
            <.human_backing
              backing={HumanBacking.describe(@detail.agent)}
              same_person={@same_person}
              myself={@myself}
            />
          </dd>
        </div>
      </dl>

      <section class="account-agent-dialog__activity" aria-labelledby="account-agent-activity-title">
        <h3 id="account-agent-activity-title">Recent activity</h3>
        <p class="account-agent-dialog__note">
          Every request this agent signed on a Regent site since it paired, newest first. Kept for 30 days.
        </p>
        <.activity activity={@detail.activity} />
        <.more_activity
          :if={is_list(@detail.activity) and is_binary(@detail.next)}
          detail={@detail}
          myself={@myself}
        />
      </section>

      <.agent_notice id="account-agent-dialog-notice" notice={@notice} />

      <div class="account-agent-dialog__actions">
        <P.button
          type="button"
          variant="secondary"
          phx-click="unpair_agent"
          phx-value-id={@detail.agent.id}
          phx-target={@myself}
          data-confirm={"Unpair #{@detail.agent.name}? It will need a new code to pair again."}
        >
          Unpair
        </P.button>
        <form method="dialog">
          <P.button type="submit" value="close">Done</P.button>
        </form>
      </div>
    </dialog>
    """
  end

  attr :backing, :map, required: true
  attr :same_person, :list, required: true
  attr :myself, :any, required: true

  # Two states only: a verified person stands behind the agent, or none does.
  # What each means waits in its tip; the person's World ID number is never shown.
  defp human_backing(%{backing: %{human_backed: true}} = assigns) do
    ~H"""
    <span class="account-agent-human account-agent-human--verified">
      <span class="account-agent-human__mark" aria-hidden="true">✓</span>
      Verified human
      <P.tip id="account-agent-human-tip" label="About Verified human">
        A real person verified with World ID stands behind this agent. Who they are stays private.
      </P.tip>
    </span>
    <span
      :if={@backing.same_person_agent_count >= 2}
      id="account-agent-same-person"
      class="account-agent-human__count"
    >
      1 of {@backing.same_person_agent_count} agents run by the same person
    </span>
    <span :if={@same_person != []} class="account-agent-human__others">
      <button
        :for={other <- @same_person}
        id={"account-agent-same-person-#{other.id}"}
        class="account-agent-human__other"
        type="button"
        phx-click="open_agent"
        phx-value-id={other.id}
        phx-target={@myself}
      >
        {other.name}
      </button>
    </span>
    """
  end

  defp human_backing(assigns) do
    ~H"""
    <span class="account-agent-human">
      No verified human
      <P.tip id="account-agent-human-tip" label="About No verified human">
        The agent's person can vouch for it with World ID.
        <a href="https://siwa.regents.sh/skill.md" target="_blank" rel="noopener noreferrer">
          Step 7
        </a>
      </P.tip>
    </span>
    """
  end

  attr :activity, :any, required: true

  defp activity(%{activity: :loading} = assigns) do
    ~H"""
    <p role="status">Reading this agent’s activity…</p>
    """
  end

  defp activity(%{activity: :unavailable} = assigns) do
    ~H"""
    <p role="status">This agent’s activity couldn’t be read right now. Refresh to try again.</p>
    """
  end

  defp activity(assigns) do
    ~H"""
    <ol class="account-agent-dialog__log">
      <li :for={entry <- @activity}>
        <span>{entry.action}</span>
        <span>{entry.site}</span>
        <time datetime={DateTime.to_iso8601(entry.occurred_at)}>{moment(entry.occurred_at)}</time>
      </li>
    </ol>
    """
  end

  attr :detail, :map, required: true
  attr :myself, :any, required: true

  defp more_activity(assigns) do
    ~H"""
    <div class="account-agent-dialog__more">
      <P.button
        id="account-agent-load-more"
        type="button"
        variant="secondary"
        phx-click="load_more_activity"
        phx-value-id={@detail.agent.id}
        phx-target={@myself}
        disabled={@detail.more == :loading}
      >
        {if @detail.more == :loading, do: "Loading…", else: "Load more"}
      </P.button>
      <p :if={@detail.more == :unavailable} id="account-agent-load-more-notice" role="status">
        Older activity couldn’t be read right now. Try again.
      </p>
    </div>
    """
  end

  attr :harness, :atom, required: true

  defp harness_mark(assigns) do
    assigns = assign(assigns, :logo, Map.fetch!(@logos, assigns.harness))

    ~H"""
    <span class="account-agent__mark" aria-hidden="true">
      <img src={@logo} alt="" width="48" height="48" />
    </span>
    """
  end

  # The open agent is read again with the list, so its dialog closes on its own
  # once the agent is unpaired.
  defp read_agents(socket) do
    agents =
      case RegentAgents.list_my_agents(actor: socket.assigns.person) do
        {:ok, agents} -> agents
        {:error, _error} -> :unavailable
      end

    socket =
      assign(socket,
        agents: agents,
        now: DateTime.utc_now(),
        pairing: after_pairing(socket.assigns.pairing, agents)
      )

    case socket.assigns.detail do
      %{agent: %{id: id}} -> show_agent(socket, id)
      nil -> socket
    end
  end

  # A code on screen gives way to the agent that used it, so a spent code is
  # never left there to send again.
  defp after_pairing(%{code: %PairingCode.Issued{issued_at: issued_at}} = shown, agents)
       when is_list(agents) do
    case Enum.find(agents, &(DateTime.compare(&1.paired_at, issued_at) != :lt)) do
      nil -> shown
      agent -> %{shown | code: {:paired, agent}}
    end
  end

  defp after_pairing(shown, _agents), do: shown

  defp issue(socket, harness) do
    code =
      case RegentAgents.issue_pairing_code(actor: socket.assigns.person) do
        {:ok, issued} -> issued
        {:error, _error} -> :unavailable
      end

    assign(socket, pairing: %{harness: harness, code: code}, notice: nil)
  end

  # What the agent has done and its registry listing are read from the sign-in
  # service in the background. What is already on screen for this agent stays
  # until the new reading lands. Once the person has asked for older activity,
  # the list stays as they are reading it.
  defp show_agent(socket, id) do
    with {:ok, id} <- Ecto.UUID.cast(id),
         {:ok, %PairedAgent{} = agent} <-
           RegentAgents.get_my_agent(id, actor: socket.assigns.person) do
      case socket.assigns.detail do
        %{agent: %{id: ^id}, paged: true} = shown ->
          assign(socket, detail: %{shown | agent: agent})

        %{agent: %{id: ^id}} = shown ->
          socket |> assign(detail: %{shown | agent: agent}) |> read_activity(agent)

        _other ->
          socket
          |> assign(
            detail: %{
              agent: agent,
              activity: :loading,
              next: nil,
              more: :idle,
              paged: false,
              listing: nil
            }
          )
          |> read_activity(agent)
      end
    else
      _missing -> assign(socket, detail: nil)
    end
  end

  defp read_activity(socket, agent),
    do: start_async(socket, {:agent_activity, agent.id}, fn -> AgentActivity.recent(agent) end)

  defp load_more_activity(
         %{assigns: %{detail: %{agent: %{id: id} = agent, next: next, more: more} = detail}} =
           socket,
         id
       )
       when is_binary(next) and more != :loading do
    socket
    |> assign(detail: %{detail | more: :loading, paged: true})
    |> start_async({:more_agent_activity, id}, fn -> AgentActivity.recent(agent, next) end)
  end

  defp load_more_activity(socket, _id), do: socket

  # What the person pastes to their agent. Muse runs where siwa.regents.sh may
  # not answer, so its message names the sign-in service's other address.
  defp agent_message(code, :muse) do
    agent_message(code, nil) <>
      "\nIf siwa.regents.sh doesn't answer from your host, set " <>
      "SIWA_BROKER=https://siwa-server.fly.dev and try again."
  end

  defp agent_message(code, _harness) do
    """
    Pair with my Ash Template account.
    Pairing code: #{code}
    Follow the "Pair with a person's account" steps at #{AshTemplateWeb.Endpoint.url()}/llms.txt\
    """
  end

  defp moment(datetime), do: Calendar.strftime(datetime, "%-d %B %Y, %H:%M UTC")
end
