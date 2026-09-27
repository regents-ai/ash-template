defmodule AshTemplateWeb.OnchainShowcaseLive do
  @moduledoc """
  Local workshop for wallet buttons, on a lab chain on this machine.

  `AshTemplateWeb.OnchainExample` runs here exactly as a product page would run
  it. Two things stand in for the real ones: the account (a lab account that
  links wallets A and B, or signed out) and the wallet app (the `OnchainLab`
  hook, whose wallets A, B and C are the lab chain's first three accounts). The
  stand-in wallet sends through this page to the lab chain only.
  """
  use AshTemplateWeb, :live_view

  alias AshTemplate.ChainClient
  alias Regent.Primitives, as: P

  # The lab chain's first three accounts (anvil's defaults).
  @wallets [
    {"A", "0xf39fd6e51aad88f6f4ce6ab8827279cfffb92266"},
    {"B", "0x70997970c51812dc3a010c7d01b50e0d17dc79c8"},
    {"C", "0x3c44cdddb6a900fa2b585dd299e03d12fa4293bc"}
  ]
  @linked [
    "0xf39fd6e51aad88f6f4ce6ab8827279cfffb92266",
    "0x70997970c51812dc3a010c7d01b50e0d17dc79c8"
  ]
  @sent_by_node ~w(eth_sendTransaction eth_signTypedData_v4)
  # The stand-in wallet sets its own gas, so a step the chain turns down is still sent.
  @gas "0x30d40"

  @impl true
  def mount(_params, session, socket) do
    chain = Application.fetch_env!(:ash_template, :lab_chain)

    {:ok,
     assign(socket,
       page_title: "Wallet buttons",
       theme: session["theme"] || "dark",
       chain: chain,
       wallets: @wallets,
       signed_in: true
     ), layout: false}
  end

  @impl true
  def handle_event("sign_in", _params, socket), do: {:noreply, assign(socket, signed_in: true)}
  def handle_event("sign_out", _params, socket), do: {:noreply, assign(socket, signed_in: false)}

  # The stand-in wallet's requests that need the lab chain. Only its own
  # accounts send, and only there.
  def handle_event("lab_rpc", %{"method" => method, "params" => [first | rest]}, socket)
      when method in @sent_by_node do
    params =
      if method == "eth_sendTransaction",
        do: [Map.put(first, "gas", @gas) | rest],
        else: [first | rest]

    reply =
      if lab_account?(method, first) do
        case ChainClient.rpc(socket.assigns.chain, method, params) do
          {:ok, result} ->
            %{result: result}

          {:error, {:rpc, error}} ->
            %{error: error}

          {:error, _unreachable} ->
            %{error: %{code: -32_603, message: "The lab chain is not running."}}
        end
      else
        %{error: %{code: 4100, message: "Not a lab wallet."}}
      end

    {:reply, reply, socket}
  end

  defp lab_account?("eth_sendTransaction", %{"from" => from}), do: lab_wallet?(from)
  defp lab_account?("eth_signTypedData_v4", from), do: lab_wallet?(from)

  defp lab_wallet?(address) when is_binary(address),
    do: String.downcase(address) in Enum.map(@wallets, &elem(&1, 1))

  defp lab_wallet?(_address), do: false

  @impl true
  def render(assigns) do
    ~H"""
    <link rel="stylesheet" href="/showcase/style.css" />
    <main id="onchain-workshop" class="sc onchain-workshop">
      <header class="sc-header">
        <a class="sc-wordmark" href="/showcase">Ash <span>Workshop</span></a>
        <span class="sc-local">Local only · lab chain on this machine</span>
      </header>

      <section class="onchain-workshop-intro">
        <p class="sc-eyebrow">Working reference</p>
        <h1>Wallet buttons</h1>
        <p>
          The server builds every step before anyone presses; a press goes straight to the wallet,
          and the server reads what happened on the chain.
        </p>
        <p>
          Start the lab chain first: <code>anvil --port {URI.parse(@chain.rpc_url).port}</code>
        </p>
      </section>

      <div class="onchain-workshop-grid">
        <section class="rg-panel rg-panel--surface" aria-labelledby="lab-account-heading">
          <h2 id="lab-account-heading">Account</h2>
          <p id="lab-account-state">
            {if @signed_in,
              do: "Signed in. The account links wallets A and B.",
              else: "Signed out."}
          </p>
          <P.button :if={!@signed_in} phx-click="sign_in">Sign in</P.button>
          <P.button :if={@signed_in} variant="secondary" phx-click="sign_out">Sign out</P.button>
        </section>

        <section
          id="onchain-lab-wallet"
          class="rg-panel rg-panel--surface"
          phx-hook="OnchainLab"
          phx-update="ignore"
          aria-labelledby="lab-wallet-heading"
          data-lab-chain-id={@chain.chain_id}
        >
          <h2 id="lab-wallet-heading">Wallet app</h2>
          <fieldset>
            <legend>Open wallet</legend>
            <label :for={{name, address} <- @wallets}>
              <input type="radio" name="lab-wallet" value={address} data-lab-wallet={name} />
              {name} <code>{RegentFormat.short_address(address)}</code>
              {if address in linked(), do: "(on the account)", else: "(not on the account)"}
            </label>
            <label>
              <input type="radio" name="lab-wallet" value="" checked /> None
            </label>
          </fieldset>
          <fieldset>
            <legend>Wallet network</legend>
            <label><input type="radio" name="lab-network" value={@chain.chain_id} checked /> {@chain.name}</label>
            <label><input type="radio" name="lab-network" value="8453" /> Base</label>
          </fieldset>
          <label><input type="checkbox" name="lab-refuse-switch" /> Refuse to switch network</label>
          <label><input type="checkbox" name="lab-decline" /> Decline in the wallet</label>
          <label><input type="checkbox" name="lab-slow" /> Answer slowly (1.5 s a request)</label>
          <p class="onchain-workshop-log" data-lab-log aria-live="polite"></p>
        </section>

        <section class="rg-panel rg-panel--surface" aria-labelledby="lab-example-heading">
          <h2 id="lab-example-heading">The example</h2>
          <.live_component
            module={AshTemplateWeb.OnchainExample}
            id="onchain-example"
            linked={if @signed_in, do: linked()}
            chain={@chain}
          />
        </section>
      </div>
    </main>
    """
  end

  defp linked, do: @linked
end
