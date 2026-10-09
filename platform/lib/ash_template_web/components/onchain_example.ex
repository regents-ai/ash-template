defmodule AshTemplateWeb.OnchainExample do
  @moduledoc """
  The reference wallet-button component: every step built on the server, every
  press sent straight to the wallet, every outcome checked against the review it
  was sent from. Copy its shape; replace its steps.

  "Record" sends a transaction that succeeds, "Fail on purpose" one the chain
  turns down, and "Sign" asks for an EIP-712 signature. None of it moves value.
  The parent passes `account` (the signed-in account, `nil` signed out), `chain`,
  its `session_lease` as `lease` and its `client_key`; the hook reports Privy's
  active wallet, which acts only when the account links it.
  """
  use AshTemplateWeb, :live_component

  alias AshTemplate.{AccessContext, ChainClient, Limits}
  alias AshTemplateWeb.Live.Session
  alias AshTemplateWeb.OnchainSteps
  alias Regent.Primitives, as: P
  alias RegentChain.{Call, Review}

  # The identity precompile accepts any input; the bn254 addition precompile
  # refuses these points, so the transaction reverts. Neither holds value.
  @record_to "0x0000000000000000000000000000000000000004"
  @fail_to "0x0000000000000000000000000000000000000006"
  @titles %{"record" => "Record", "fail" => "Fail on purpose"}

  @impl true
  def mount(socket) do
    {:ok,
     socket
     |> Session.check_component_events(&take_account/2)
     |> OnchainSteps.init()
     |> assign(active: nil, amount: "1", balance: nil, signer: nil, wallet: nil, signed: nil)}
  end

  @impl true
  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(Map.take(assigns, [:id, :lease, :chain, :client_key]))
     |> take_account(assigns.account)}
  end

  @impl true
  def handle_event("onchain_active_wallet", params, socket) do
    active = OnchainSteps.active_wallet(params)
    socket = if active == socket.assigns.active, do: socket, else: assign(socket, press_note: nil)
    {:noreply, socket |> assign(active: active) |> sync()}
  end

  def handle_event("change", %{"amount" => amount}, socket),
    do: {:noreply, socket |> assign(amount: amount) |> sync()}

  # A press made before the review caught up with the form: the form is taken
  # as the page's own, and the reply carries the review for it.
  def handle_event("prepare_and_send", %{"form" => %{"amount" => amount}, "step" => name}, socket)
      when is_binary(amount) do
    socket = socket |> assign(amount: amount) |> sync()

    case socket.assigns.review do
      %{} = review when is_binary(name) -> {:reply, %{review: review, send: name}, socket}
      _none -> {:reply, %{}, socket}
    end
  end

  def handle_event("step_sent", params, socket),
    do: {:noreply, OnchainSteps.sent(socket, params)}

  def handle_event("step_signed", params, socket) do
    case OnchainSteps.signed(socket, params) do
      {:ok, signed, socket} -> {:noreply, assign(socket, signed: signed)}
      :error -> {:noreply, socket}
    end
  end

  def handle_event("step_failed", %{"reason" => reason}, socket) when is_binary(reason) do
    %{linked: linked, active: active, chain: chain} = socket.assigns
    AshTemplateWeb.Telemetry.wallet_failed(:onchain_example, reason)

    {:noreply,
     assign(socket, press_note: OnchainSteps.failure_note(reason, linked, active, chain.name))}
  end

  def handle_event("check_again", %{"hash" => hash}, socket),
    do: {:noreply, OnchainSteps.check_again(socket, hash)}

  @impl true
  # The balance is read again once a step lands, not on every check before it.
  def handle_async({:onchain_step, hash}, result, socket) do
    socket = OnchainSteps.checked(socket, hash, result)

    case Enum.find(socket.assigns.presses.sent, &(&1.hash == hash)) do
      %{outcome: outcome} when outcome in [:confirmed, :reverted] ->
        {:noreply, read_balance(socket)}

      _reading ->
        {:noreply, socket}
    end
  end

  def handle_async(:balance, {:ok, {:ok, wei}}, socket),
    do: {:noreply, assign(socket, balance: wei)}

  def handle_async(:balance, _unread, socket), do: {:noreply, assign(socket, balance: :unread)}

  # The account as the page gave it, or as it reads now before each event
  # (`Session.check_component_events/2`): the wallets that may act and the
  # review follow it.
  defp take_account(socket, account) do
    context = AccessContext.for_account(account)

    socket
    |> assign(
      linked: AccessContext.linked_wallets(context),
      own: AccessContext.own_wallet(context)
    )
    |> sync()
  end

  # The review follows the signer and the form. With no eligible signer there is
  # no review, and the figures stay on the account's own wallet.
  defp sync(socket) do
    %{linked: linked, active: active, chain: chain, amount: amount} = socket.assigns
    signer = OnchainSteps.signer(linked, active)

    review =
      if signer,
        do:
          Review.new(socket.assigns.id, signer, chain, steps(amount, chain), %{"amount" => amount})

    wallet = OnchainSteps.shown_wallet(linked, socket.assigns.own, active)

    socket =
      if wallet == socket.assigns.wallet,
        do: assign(socket, signer: signer),
        else: socket |> assign(signer: signer, wallet: wallet, balance: nil) |> read_balance()

    socket
    |> assign(mismatch: OnchainSteps.mismatch_note(linked, active))
    |> OnchainSteps.put_review(review)
  end

  defp steps(amount, chain) do
    case Integer.parse(String.trim(amount)) do
      {n, ""} when n in 1..1_000_000 ->
        [
          Review.step("record", @record_to, Call.encode("record(uint256)", [n])),
          Review.step("fail", @fail_to, Call.encode("fail(uint256)", [n])),
          Review.signature("sign", note(n, chain))
        ]

      _not_a_number ->
        []
    end
  end

  defp note(n, chain) do
    %{
      "domain" => %{"name" => "Ash Template", "version" => "1", "chainId" => chain.chain_id},
      "types" => %{
        "EIP712Domain" => [
          %{"name" => "name", "type" => "string"},
          %{"name" => "version", "type" => "string"},
          %{"name" => "chainId", "type" => "uint256"}
        ],
        "Note" => [%{"name" => "number", "type" => "uint256"}]
      },
      "primaryType" => "Note",
      "message" => %{"number" => n}
    }
  end

  defp read_balance(%{assigns: %{wallet: nil}} = socket), do: socket

  # Signed out the shown wallet is whatever the browser reports, so every read
  # counts against the visitor's address allowance; past it, the figure already
  # shown stays.
  defp read_balance(socket) do
    %{chain: chain, wallet: wallet, balance: balance} = socket.assigns

    case Limits.spend(:wallet_read, {:client, socket.assigns.client_key}) do
      :ok -> start_async(socket, :balance, fn -> ChainClient.balance(chain, wallet) end)
      :limited -> assign(socket, balance: balance || :unread)
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <section id={@id} class="onchain-example" phx-hook="OnchainSteps">
      <form class="onchain-example-form" phx-change="change" phx-submit="change" phx-target={@myself}>
        <label for={"#{@id}-amount"}>Number to record</label>
        <input
          id={"#{@id}-amount"}
          name="amount"
          value={@amount}
          inputmode="numeric"
          autocomplete="off"
          data-onchain-input="amount"
        />
      </form>

      <%!-- Lines above the buttons stay in the page and are only hidden, so one
           appearing never replaces the button a person has just pressed. --%>
      <p class="onchain-example-review" aria-live="polite" hidden={!@review}>
        {@review && review_line(@review)}
      </p>
      <p class="onchain-example-from" hidden={!@wallet}>
        <%= if @wallet do %>
          Sending from <code>{RegentFormat.short_address(@wallet)}</code>
          on {@chain.name} · {balance(@balance)}
        <% end %>
      </p>
      <p class="onchain-example-note" hidden={!@mismatch}>{@mismatch}</p>

      <div class="onchain-example-actions">
        <P.button data-onchain-step="record"><span data-press-label>Record</span></P.button>
        <P.button variant="secondary" data-onchain-step="fail">
          <span data-press-label>Fail on purpose</span>
        </P.button>
        <P.button variant="secondary" data-onchain-step="sign"><span data-press-label>Sign</span></P.button>
      </div>

      <p :if={@press_note} class="onchain-example-note" role="status">{@press_note}</p>
      <p class="onchain-example-note" role="status" data-onchain-lost hidden>
        This page lost its connection, so nothing was sent. Press again once it's back.
      </p>

      <p :if={@signed} class="onchain-example-signed" role="status">
        Signed by <code>{RegentFormat.short_address(@signed.review.signer)}</code>
        for the number {@signed.review.inputs["amount"]}.
      </p>

      <ol :if={@presses.sent != []} class="onchain-example-sent" aria-live="polite">
        <li
          :for={
            {entry, shown} <- Enum.map(@presses.sent, &{&1, OnchainSteps.describe(&1, @chain.name)})
          }
          data-state={shown.state}
        >
          <strong>{title(entry)}</strong>
          <span>{shown.words}</span>
          <code>{RegentFormat.short_hash(entry.hash)}</code>
          <P.button
            :if={shown.state == :stalled}
            variant="quiet"
            phx-click="check_again"
            phx-value-hash={entry.hash}
            phx-target={@myself}
          >
            Check again
          </P.button>
        </li>
      </ol>
    </section>
    """
  end

  # What the buttons send, read from the review itself, so a press sends what the page shows.
  defp review_line(%{steps: []}), do: "Enter a whole number from 1 to 1,000,000 to record."

  defp review_line(%{inputs: %{"amount" => amount}}),
    do: "Record and Sign use the number #{amount}."

  defp title(%{name: name, review: %{inputs: %{"amount" => amount}}}),
    do: "#{Map.get(@titles, name, "Transaction")} #{amount}"

  defp title(_unknown), do: "Transaction"

  defp balance(nil), do: "reading balance"
  defp balance(:unread), do: "balance unavailable right now"

  defp balance(wei) do
    eth = wei |> Decimal.new() |> Decimal.div(Decimal.new(1_000_000_000_000_000_000))
    "#{eth |> Decimal.normalize() |> Decimal.to_string(:normal)} ETH"
  end
end
