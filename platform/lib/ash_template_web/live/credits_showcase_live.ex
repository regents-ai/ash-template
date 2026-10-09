defmodule AshTemplateWeb.CreditsShowcaseLive do
  @moduledoc """
  Local workshop for the Buy Credits panel against a copy of Base on this
  machine. `AshTemplateWeb.CreditsPanel` runs here as in the site header; a
  lab account (linking wallets A and B) and the `OnchainLab` stand-in wallet app
  replace the real ones. The stand-in wallet sends only while the site's Base node
  is on this machine (`ASH_TEMPLATE_BASE_NODE_URL`), so nothing reaches a real
  network.

  It also shows the parts regents.sh hosts, signed in by stand-ins: the agent
  spending settings (as the lab account on regents.sh), an agent placing a hold
  here, the admin page (as the lab admin, when `REGENT_CREDITS_ADMINS` names
  it) and the refund rules. Every part here acts for a stand-in, not for
  whoever is signed in, so none gets the session lease.
  """
  use AshTemplateWeb, :live_view

  alias AshTemplate.ChainClient
  alias Regent.Primitives, as: P
  alias RegentCredits.{Actor, Amount, Chains}
  alias RegentCredits.Errors.{NotEnoughCredits, Refused}

  # The local copies' first three accounts (anvil's defaults).
  @wallets [
    {"A", "0xf39fd6e51aad88f6f4ce6ab8827279cfffb92266"},
    {"B", "0x70997970c51812dc3a010c7d01b50e0d17dc79c8"},
    {"C", "0x3c44cdddb6a900fa2b585dd299e03d12fa4293bc"}
  ]
  @addresses Enum.map(@wallets, &elem(&1, 1))
  # The id keys the lab account's read and report allowances, as a real account's does.
  @account %{
    id: "credits-lab",
    privy_user_id: "did:privy:credits-lab",
    wallet_addresses: Enum.take(@addresses, 2)
  }
  @chains [:base]
  # The lab account's agents (the local copies' fourth and fifth accounts).
  @agents [
    "0x90f79bf6eb2c4f870365e785982e1f101e93b906",
    "0x15d34aaf54267db7d7c367839aaf71a00a2c6a65"
  ]
  @agent_sites [{"patchbay", "patchbay.help"}, {"template", "Ash Template"}]
  @admin "did:privy:credits-lab-admin"
  # The stand-in wallet sets its own gas, so a step the chain turns down is still sent.
  @gas "0x30d40"
  # 1,000 USDC in the token's six decimals.
  @lab_usdc "0x3b9aca00"
  @local_hosts ["127.0.0.1", "localhost"]
  @switches [
    {"lab-refuse-switch", "Refuse to switch network"},
    {"lab-decline", "Decline in the wallet"},
    {"lab-slow", "Answer slowly (1.5 s a request)"}
  ]

  @impl true
  def mount(_params, _session, socket) do
    chains = Enum.map(@chains, &Chains.chain/1)

    {:ok,
     socket
     |> assign(AshTemplateWeb.PublicDocuments.page("/showcase/credits"))
     |> follow_credits()
     |> assign(
       chains: chains,
       local: Enum.filter(chains, &local?/1),
       account: @account,
       wallets: @wallets,
       switches: @switches,
       topped_up: nil,
       agents: @agents,
       agent_sites: @agent_sites,
       admin_account: %{privy_user_id: @admin},
       admin?: @admin in Application.fetch_env!(:regent_credits, :admins),
       agent_hold: nil
     ), layout: false}
  end

  @impl true
  def handle_event(
        "lab_rpc",
        %{"chain_id" => chain_id, "method" => method, "params" => params},
        socket
      ) do
    case Enum.find(socket.assigns.local, &(&1.chain_id == chain_id)) do
      nil ->
        {:reply,
         %{error: %{code: -32_603, message: "This network's node is not on this machine."}},
         socket}

      chain ->
        {:reply, lab_reply(chain, method, params), socket}
    end
  end

  # Gives every lab wallet 1,000 USDC on the local copy.
  def handle_event("top_up", _params, socket) do
    results =
      for chain <- socket.assigns.local,
          {_name, address} <- @wallets,
          do:
            ChainClient.rpc(chain, "anvil_dealERC20", [
              address,
              Chains.usdc(chain_name(chain)),
              @lab_usdc
            ])

    topped_up =
      if Enum.all?(results, &match?({:ok, _}, &1)),
        do: "Every lab wallet now holds 1,000 USDC on the local copy.",
        else: "The local copy did not answer. Start it and try again."

    {:noreply, assign(socket, topped_up: topped_up)}
  end

  # The first lab agent holds 3 Credits on this site, as it would for a bid.
  def handle_event("agent_hold", _params, socket) do
    pairing_id =
      case RegentAgents.Authority.resolve(AshTemplate.Repo, hd(@agents)) do
        {:ok, pairing} -> pairing.id
        _ -> nil
      end

    agent =
      Actor.agent(@account.privy_user_id, hd(@agents), AshTemplate.Credits.site(), pairing_id)

    result =
      RegentCredits.hold(Ecto.UUID.generate(), @account.privy_user_id, 3, "lab bid", actor: agent)

    {:noreply, assign(socket, agent_hold: hold_words(result))}
  end

  @impl true
  def handle_info(:credits_changed, socket), do: {:noreply, read_balance(socket)}

  # The lab account's balance follows every change, as the site header's does.
  defp follow_credits(socket) do
    if connected?(socket),
      do:
        Phoenix.PubSub.subscribe(AshTemplate.PubSub, RegentCredits.topic(@account.privy_user_id))

    read_balance(socket)
  end

  defp read_balance(socket),
    do: assign(socket, :balance, RegentCredits.balance(@account.privy_user_id))

  defp hold_words({:ok, hold}), do: "The agent now holds #{Amount.format(hold.amount)}."

  defp hold_words({:error, %Ash.Error.Invalid{errors: [error | _]}}),
    do: hold_words({:error, error})

  defp hold_words({:error, %Refused{reason: :agent_off}}),
    do: "Refused: this agent's spending is off."

  defp hold_words({:error, %Refused{reason: :agent_site}}),
    do: "Refused: this agent may not spend on Ash Template."

  defp hold_words({:error, %Refused{reason: :agent_max_per_spend}}),
    do: "Refused: 3 Credits is over this agent's most per spend."

  defp hold_words({:error, %Refused{reason: :agent_daily_limit}}),
    do: "Refused: this would go over the agent's daily limit."

  defp hold_words({:error, %NotEnoughCredits{}}), do: "Refused: not enough Credits."
  defp hold_words({:error, error}), do: "Refused: #{Exception.message(error)}"

  defp lab_reply(chain, "eth_sendTransaction" = method, [%{"from" => from} = tx | rest]),
    do: lab_reply(chain, method, from, [Map.put(tx, "gas", @gas) | rest])

  defp lab_reply(chain, "eth_signTypedData_v4" = method, [from | _] = params),
    do: lab_reply(chain, method, from, params)

  defp lab_reply(chain, method, from, params) do
    if is_binary(from) and String.downcase(from) in @addresses,
      do: rpc(chain, method, params),
      else: %{error: %{code: 4100, message: "Not a lab wallet."}}
  end

  defp rpc(chain, method, params) do
    case ChainClient.rpc(chain, method, params) do
      {:ok, result} ->
        %{result: result}

      {:error, {:rpc, error}} ->
        %{error: error}

      {:error, _unreachable} ->
        %{error: %{code: -32_603, message: "The local copy is not running."}}
    end
  end

  defp local?(%{chain_id: chain_id}) do
    node = :ash_template |> Application.fetch_env!(:chain_nodes) |> Map.fetch!(chain_id)
    URI.parse(node).host in @local_hosts
  end

  defp chain_name(%{chain_id: chain_id}),
    do: Enum.find(@chains, &(Chains.chain(&1).chain_id == chain_id))

  @impl true
  def render(assigns) do
    ~H"""
    <link rel="stylesheet" href="/showcase/style.css" />
    <main id="credits-workshop" class="sc onchain-workshop">
      <header class="sc-header">
        <a class="sc-wordmark" href="/showcase">Ash <span>Workshop</span></a>
        <span class="sc-local">Local only · a copy of Base on this machine</span>
      </header>

      <section class="onchain-workshop-intro">
        <p class="sc-eyebrow">Working reference</p>
        <h1>Credits lab</h1>
        <p>
          The Buy Credits panel as it opens from the site header. Each Buy is reported as a
          purchase and checked on the chain; the site's Oban keeps checking once a minute.
        </p>
        <p :if={@local != @chains}>
          Start a local copy and point the site at it: <code>anvil --fork-url https://mainnet.base.org --port 58610</code>, then
          run the site with <code>ASH_TEMPLATE_BASE_NODE_URL=http://127.0.0.1:58610</code>.
        </p>
      </section>

      <div class="onchain-workshop-grid">
        <section class="rg-panel rg-panel--surface" aria-labelledby="lab-account-heading">
          <h2 id="lab-account-heading">Account</h2>
          <p>Signed in. The account links wallets A and B.</p>
          <p :if={@local != []}>
            <P.button variant="secondary" phx-click="top_up">Give lab wallets USDC</P.button>
          </p>
          <p :if={@topped_up} id="credits-lab-topped-up" aria-live="polite">{@topped_up}</p>
        </section>

        <section
          id="credits-lab-wallet"
          class="rg-panel rg-panel--surface"
          phx-hook="OnchainLab"
          phx-update="ignore"
          aria-labelledby="lab-wallet-heading"
          data-lab-chain-ids={Enum.map_join(@local, ",", & &1.chain_id)}
        >
          <h2 id="lab-wallet-heading">Wallet app</h2>
          <fieldset>
            <legend>Open wallet</legend>
            <label :for={{name, address} <- @wallets}>
              <input type="radio" name="lab-wallet" value={address} data-lab-wallet={name} />
              {name} <code>{RegentFormat.short_address(address)}</code>
              {if address in @account.wallet_addresses,
                do: "(on the account)",
                else: "(not on the account)"}
            </label>
            <label>
              <input type="radio" name="lab-wallet" value="" checked /> None
            </label>
          </fieldset>
          <fieldset>
            <legend>Wallet network</legend>
            <label :for={{chain, index} <- Enum.with_index(@chains)}>
              <input type="radio" name="lab-network" value={chain.chain_id} checked={index == 0} />
              {chain.name}
            </label>
          </fieldset>
          <label :for={{name, label} <- @switches}>
            <input type="checkbox" name={name} /> {label}
          </label>
          <p class="onchain-workshop-log" data-lab-log aria-live="polite"></p>
        </section>

        <section class="rg-panel rg-panel--surface" aria-labelledby="lab-panel-heading">
          <h2 id="lab-panel-heading">The panel</h2>
          <.live_component
            module={AshTemplateWeb.CreditsPanel}
            id="credits-panel"
            lease={nil}
            account={@account}
            balance={@balance}
          />
        </section>

        <section class="rg-panel rg-panel--surface" aria-labelledby="lab-agents-heading">
          <h2 id="lab-agents-heading">Agent spending, as on regents.sh/account</h2>
          <.live_component
            module={AshTemplateWeb.CreditsAgentSpending}
            id="credits-agents"
            lease={nil}
            account={@account}
            agents={@agents}
            sites={@agent_sites}
          />
          <h3>Try it</h3>
          <P.button variant="secondary" phx-click="agent_hold">
            First agent holds 3 Credits here
          </P.button>
          <p :if={@agent_hold} id="credits-lab-agent-hold" aria-live="polite">{@agent_hold}</p>
        </section>

        <section class="rg-panel rg-panel--surface" aria-labelledby="lab-admin-heading">
          <h2 id="lab-admin-heading">Admin, as on regents.sh/admin/credits</h2>
          <p :if={!@admin?}>
            Run the site with <code>REGENT_CREDITS_ADMINS=did:privy:credits-lab-admin</code>
            to act as the lab admin; until then every action here is refused.
          </p>
          <.live_component
            module={AshTemplateWeb.CreditsAdmin}
            id="credits-admin"
            lease={nil}
            account={@admin_account}
          />
        </section>

        <section class="rg-panel rg-panel--surface">
          <AshTemplateWeb.CreditsRefundRules.rules />
        </section>
      </div>
    </main>
    """
  end
end
