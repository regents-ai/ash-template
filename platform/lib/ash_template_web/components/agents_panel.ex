defmodule AshTemplateWeb.AgentsPanel do
  @moduledoc """
  The agents a person has paired with their account (`RegentAgents`), a code to
  pair another, and Unpair for each.

  Pairing immediately lets an agent read and change the person's notes and
  post and edit in rooms, each marked as its own. World ID is optional. It
  never touches their wallet (`AshTemplateWeb.Plugs.AgentWallet`). Pairing is
  shared by every Regent site, so an agent paired on another one is listed
  here too.

  The parent passes `account` (the signed-in account), its `session_lease` as
  `lease` and `id`, and sends
  `agents_changed: true` when an agent pairs, checks in or is unpaired anywhere.
  """
  use AshTemplateWeb, :live_component

  alias AshTemplateWeb.Live.Session
  alias Regent.Primitives, as: P
  alias RegentAgents.{Harness, PairingCode, Person}

  @impl true
  def mount(socket),
    do:
      {:ok,
       socket
       |> Session.check_component_events(&take_account/2)
       |> assign(pairing: nil, notice: nil)}

  @impl true
  def update(%{agents_changed: true}, socket), do: {:ok, read_agents(socket)}

  def update(%{account: account, id: id, lease: lease}, socket) do
    {:ok,
     socket
     |> assign(id: id, lease: lease)
     |> take_account(account)
     |> read_agents()}
  end

  # The account as the page gave it, or as it reads now before each event
  # (`Session.check_component_events/2`).
  defp take_account(socket, account),
    do: assign(socket, person: %Person{privy_user_id: account.privy_user_id})

  @impl true
  def handle_event("issue_pairing_code", _params, socket),
    do: {:noreply, assign(socket, pairing: issue(socket), notice: nil)}

  def handle_event("unpair_agent", %{"id" => id}, socket) do
    actor = socket.assigns.person

    notice =
      with {:ok, id} <- Ecto.UUID.cast(id),
           {:ok, %{} = agent} <- RegentAgents.get_my_agent(id, actor: actor),
           :ok <- RegentAgents.unpair_agent(agent, actor: actor) do
        "#{agent.name} is unpaired. It needs a new code to pair again."
      else
        {:ok, nil} -> "That agent is no longer paired. Nothing changed."
        _failed -> "Your agents couldn’t be changed just now. Try again."
      end

    {:noreply, socket |> assign(notice: notice) |> read_agents()}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <section id={@id} class="account-panel account-agents" aria-labelledby={"#{@id}-title"}>
      <h2 id={"#{@id}-title"}>
        Agents
        <P.tip id={"#{@id}-about"} label="About paired agents">
          Pairing immediately lets an agent read and change your notes and post in rooms for you.
          Each thing it does is marked as its own. It can never use your wallet.
        </P.tip>
      </h2>

      <p :if={@notice} id={"#{@id}-notice"} role="status">{@notice}</p>

      <p :if={@agents == :unavailable} role="status">
        Your agents couldn’t be read right now. Refresh to try again.
      </p>
      <p :if={@agents == []} class="rg-muted">No agents paired yet.</p>

      <ul :if={is_list(@agents) and @agents != []} class="account-agents__list">
        <li :for={agent <- @agents} id={"#{@id}-agent-#{agent.id}"} class="account-agents__agent">
          <div>
            <strong>{agent.name}</strong>
            <span class="rg-muted">{Harness.label(agent.harness)}</span>
            <span :if={agent.human_id} class="account-agents__human">
              Human-backed
              <P.tip id={"#{@id}-human-#{agent.id}"} label="About Human-backed">
                A person verified with World ID stands behind this agent. This optional
                verification does not change its paired access.
              </P.tip>
            </span>
            <span :if={is_nil(agent.human_id)} class="account-agents__human">
              No World ID backing
              <P.tip id={"#{@id}-human-#{agent.id}"} label="About backing">
                This agent already has paired access. World ID backing is optional. Step 7 of
                <a href="https://siwa.regents.sh/skill.md" target="_blank" rel="noopener">
                  the agent guide
                </a>
                shows how.
              </P.tip>
            </span>
          </div>
          <p class="rg-muted">
            Last contact
            <time datetime={DateTime.to_iso8601(agent.last_contact_at)}>
              {RegentFormat.relative_time(agent.last_contact_at, DateTime.utc_now())}
            </time>
          </p>
          <P.button
            type="button"
            variant="quiet"
            phx-click="unpair_agent"
            phx-value-id={agent.id}
            phx-target={@myself}
            data-confirm={"Unpair #{agent.name}? It needs a new code to pair again."}
          >
            Unpair
          </P.button>
        </li>
      </ul>

      <P.button
        id={"#{@id}-pair"}
        type="button"
        variant="secondary"
        phx-click="issue_pairing_code"
        phx-target={@myself}
        phx-disable-with="Making a code…"
      >
        {if match?(%PairingCode.Issued{}, @pairing), do: "Make a new code", else: "Pair an agent"}
      </P.button>

      <.pairing id={@id} pairing={@pairing} />
    </section>
    """
  end

  attr :id, :string, required: true
  attr :pairing, :any, required: true

  defp pairing(%{pairing: nil} = assigns), do: ~H""

  defp pairing(%{pairing: %PairingCode.Issued{}} = assigns) do
    assigns =
      assign(assigns,
        message: message(assigns.pairing.code),
        expires_iso: DateTime.to_iso8601(assigns.pairing.expires_at),
        expires: Calendar.strftime(assigns.pairing.expires_at, "%H:%M UTC")
      )

    ~H"""
    <div id={"#{@id}-code"} class="account-agents__code" role="status">
      <p>
        Send this to your agent. It works once, until <time datetime={@expires_iso}>{@expires}</time>.
      </p>
      <pre><code>{@message}</code></pre>
      <P.copy_button id={"#{@id}-copy"} text={@message} variant="primary">Copy</P.copy_button>
    </div>
    """
  end

  defp pairing(%{pairing: {:paired, agent}} = assigns) do
    assigns = assign(assigns, :agent, agent)

    ~H"""
    <p id={"#{@id}-code"} role="status">{@agent.name} paired with your account.</p>
    """
  end

  defp pairing(%{pairing: :wait} = assigns) do
    ~H"""
    <p id={"#{@id}-code"} role="status">A new code can be made once a minute. Try again shortly.</p>
    """
  end

  defp pairing(assigns) do
    ~H"""
    <p id={"#{@id}-code"} role="status">A code couldn’t be made right now. Try again.</p>
    """
  end

  defp read_agents(socket) do
    agents =
      case RegentAgents.list_my_agents(actor: socket.assigns.person) do
        {:ok, agents} -> agents
        {:error, _error} -> :unavailable
      end

    assign(socket, agents: agents, pairing: after_pairing(socket.assigns.pairing, agents))
  end

  # A code on screen gives way to the agent that used it, so a spent code is
  # never left there to send again.
  defp after_pairing(%PairingCode.Issued{issued_at: issued_at} = shown, agents)
       when is_list(agents) do
    case Enum.find(agents, &(DateTime.compare(&1.paired_at, issued_at) != :lt)) do
      nil -> shown
      agent -> {:paired, agent}
    end
  end

  defp after_pairing(shown, _agents), do: shown

  # A code already on screen stays there while a new one can't be made yet.
  defp issue(socket) do
    case RegentAgents.issue_pairing_code(actor: socket.assigns.person) do
      {:ok, issued} ->
        issued

      {:error,
       %Ash.Error.Invalid{errors: [%Ash.Error.Invalid.Unavailable{reason: :issued_recently}]}} ->
        if match?(%PairingCode.Issued{}, socket.assigns.pairing),
          do: socket.assigns.pairing,
          else: :wait

      {:error, _error} ->
        :unavailable
    end
  end

  defp message(code) do
    """
    Pair with my Ash Template account.
    Pairing code: #{code}
    Follow "Pair with a person's account" at #{AshTemplateWeb.Endpoint.url()}/llms.txt\
    """
  end
end
