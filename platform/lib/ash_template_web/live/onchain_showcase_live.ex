defmodule AshTemplateWeb.OnchainShowcaseLive do
  @moduledoc """
  Local workshop for wallet buttons on a lab chain on this machine.
  `AshTemplateWeb.OnchainExample` runs here as on a product page; a lab account
  (linking wallets A and B, or signed out) and the `OnchainLab` stand-in wallet
  app, whose wallets are the lab chain's first three accounts, replace the real ones.
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
  @addresses Enum.map(@wallets, &elem(&1, 1))
  @linked Enum.take(@addresses, 2)
  # The stand-in wallet sets its own gas, so a step the chain turns down is still sent.
  @gas "0x30d40"
  # What the tester can make the stand-in wallet do.
  @switches [
    {"lab-refuse-switch", "Refuse to switch network"},
    {"lab-decline", "Decline in the wallet"},
    {"lab-slow", "Answer slowly (1.5 s a request)"}
  ]

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(AshTemplateWeb.PublicDocuments.page("/showcase/onchain"))
     |> assign(
       chain: Application.fetch_env!(:ash_template, :lab_chain),
       wallets: @wallets,
       linked: @linked,
       switches: @switches,
       signed_in: true
     ), layout: false}
  end

  @impl true
  def handle_event("sign_in", _params, socket), do: {:noreply, assign(socket, signed_in: true)}
  def handle_event("sign_out", _params, socket), do: {:noreply, assign(socket, signed_in: false)}

  # The stand-in wallet's requests that need the lab chain. Only its own
  # accounts send, and only there.
  def handle_event(
        "lab_rpc",
        %{"chain_id" => chain_id, "method" => method, "params" => params},
        socket
      )
      when chain_id == socket.assigns.chain.chain_id do
    {:reply, lab_reply(socket.assigns.chain, method, params), socket}
  end

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
        %{error: %{code: -32_603, message: "The lab chain is not running."}}
    end
  end

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
        <h1>Wallet lab</h1>
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
          data-lab-chain-ids={@chain.chain_id}
        >
          <h2 id="lab-wallet-heading">Wallet app</h2>
          <fieldset>
            <legend>Open wallet</legend>
            <label :for={{name, address} <- @wallets}>
              <input type="radio" name="lab-wallet" value={address} data-lab-wallet={name} />
              {name} <code>{RegentFormat.short_address(address)}</code>
              {if address in @linked, do: "(on the account)", else: "(not on the account)"}
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
          <label :for={{name, label} <- @switches}>
            <input type="checkbox" name={name} /> {label}
          </label>
          <p class="onchain-workshop-log" data-lab-log aria-live="polite"></p>
        </section>

        <section class="rg-panel rg-panel--surface" aria-labelledby="lab-example-heading">
          <h2 id="lab-example-heading">The example</h2>
          <.live_component
            module={AshTemplateWeb.OnchainExample}
            id="onchain-example"
            linked={if @signed_in, do: @linked}
            chain={@chain}
          />
        </section>
      </div>
    </main>
    """
  end
end
