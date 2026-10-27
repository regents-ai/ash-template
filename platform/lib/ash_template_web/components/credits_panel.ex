defmodule AshTemplateWeb.CreditsPanel do
  @moduledoc """
  The Buy Credits panel: the balance, the amount, the wallet presses
  and what each press did, all in one place. Built on the reference wallet
  component (`AshTemplateWeb.OnchainExample`): the server builds the steps
  (`RegentCredits.Chains.steps/3`), every press goes straight to the wallet, and
  each sent Buy is followed by a job (`AshTemplate.Credits.CheckPurchase`) that
  reports and checks it until it counts. The parent hears how it ended on the
  person's purchase topic and hands it to the panel as `purchase`.

  Credits are bought with USDC on Base only: the wallet is asked onto Base when
  a press needs it. The USDC of the wallet that pays is shown.

  Buy is disabled only when it is certain to fail, from the chain at the latest
  block: the Base approval does not cover the amount yet, or the wallet holds
  too little USDC. Explanations wait in tips; the panel shows figures, choices,
  presses and outcomes. "Where to spend" opens a window listing each Regents
  Product and what Credits buy there (`AshTemplateWeb.Components.Shell.regents_products/0`).

  The parent passes `account` (the signed-in account), its `credits` reading
  (`state` and the `RegentCredits.balance/1` value, kept current by the
  parent; the figures show while it is `:ready` or read again, and a dash
  otherwise), its
  `session_lease` as `lease` and `id`.
  """
  use AshTemplateWeb, :live_component

  alias AshTemplate.{AccessContext, ChainClient, Limits}
  alias AshTemplate.Credits.CheckPurchase
  alias AshTemplateWeb.Components.Shell
  alias AshTemplateWeb.Live.Session
  alias AshTemplateWeb.OnchainSteps
  alias Regent.Primitives, as: P
  alias RegentChain.{Call, Presses, Review}
  alias RegentCredits.{Amount, Chains}

  @impl true
  def mount(socket) do
    {:ok,
     socket
     |> Session.check_component_lease(&take_account/2)
     |> OnchainSteps.init()
     |> assign(
       active: nil,
       signer: nil,
       wallet: nil,
       amount: "5",
       number: Ecto.UUID.generate(),
       numbers: %{},
       usdc: nil,
       allowance: nil,
       latest: %{},
       purchases: %{}
     )}
  end

  @impl true
  # How a Buy this panel sent ended, as its check told the parent.
  def update(%{purchase: {hash, shown}}, socket) do
    case socket.assigns.purchases do
      %{^hash => _sent} -> {:ok, put_purchase(socket, hash, shown)}
      _other_page -> {:ok, socket}
    end
  end

  def update(%{account: account} = assigns, socket) do
    {:ok,
     socket
     |> assign(id: assigns.id, lease: assigns.lease, credits: assigns.credits)
     |> take_account(account)}
  end

  @impl true
  def handle_event("onchain_active_wallet", params, socket) do
    active = OnchainSteps.active_wallet(params)
    socket = if active == socket.assigns.active, do: socket, else: assign(socket, press_note: nil)
    {:noreply, socket |> assign(active: active) |> sync()}
  end

  def handle_event("change", %{"amount" => amount}, socket),
    do: {:noreply, socket |> assign(amount: amount) |> sync()}

  # The page asks when the panel opens, when it comes back into view and after
  # each press, so the funds behind a disabled Buy are read again then.
  def handle_event("refresh_funds", _params, socket), do: {:noreply, read_funds(socket)}

  # A press made before the review caught up with the form: the form is taken
  # as the page's own, and the reply carries the review for it. A step certain
  # to fail for the wallet and form as they stand now is not handed over: the
  # press came while the page still showed another wallet or amount, and the
  # button now shows why it can't be pressed.
  def handle_event(
        "prepare_and_send",
        %{"form" => %{"amount" => amount}, "step" => name},
        socket
      )
      when is_binary(amount) and is_binary(name) do
    socket = socket |> assign(amount: amount) |> sync()

    case {socket.assigns.review, blocked_step(socket.assigns, name)} do
      {%{} = review, nil} -> {:reply, %{review: review, send: name}, socket}
      _none_or_blocked -> {:reply, %{}, socket}
    end
  end

  def handle_event("step_sent", %{"transaction_hash" => hash} = params, socket)
      when is_binary(hash) do
    socket = OnchainSteps.sent(socket, params)

    case Enum.find(socket.assigns.presses.sent, &(&1.hash == String.downcase(hash))) do
      %{name: "buy", review: %{} = review} = entry ->
        {:noreply, follow(socket, entry.hash, review)}

      _other ->
        {:noreply, socket}
    end
  end

  def handle_event("step_failed", %{"reason" => reason}, socket) when is_binary(reason) do
    %{linked: linked, active: active, amount: amount} = socket.assigns
    AshTemplateWeb.Telemetry.wallet_failed(:credits_panel, reason)

    note =
      if problem = amount_problem(amount),
        do: [problem],
        else: OnchainSteps.failure_note(reason, linked, active, "Base")

    {:noreply, assign(socket, press_note: note)}
  end

  def handle_event("check_again", %{"hash" => hash}, socket),
    do: {:noreply, OnchainSteps.check_again(socket, hash)}

  def handle_event("check_purchase_again", %{"hash" => hash}, socket) do
    case Enum.find(socket.assigns.presses.sent, &(&1.hash == hash and &1.name == "buy")) do
      %{review: %{} = review} -> {:noreply, follow(socket, hash, review)}
      _unknown -> {:noreply, socket}
    end
  end

  @impl true
  # The funds are read again once a step lands, not at every read while it waits.
  def handle_async({:onchain_step, hash}, result, socket) do
    socket = socket |> OnchainSteps.checked(hash, result) |> approved(hash)

    case Enum.find(socket.assigns.presses.sent, &(&1.hash == hash)) do
      %{outcome: outcome} when outcome in [:confirmed, :reverted] ->
        {:noreply, read_funds(socket)}

      _waiting ->
        {:noreply, socket}
    end
  end

  # Each read answers with the wallet it was for, and lands only while that
  # wallet is still the one shown: the check before it can move the panel to
  # another. Only a figure read now may hold Buy back.
  def handle_async(figure, result, socket) when figure in [:usdc, :allowance] do
    case read(result, socket.assigns.wallet) do
      :other_wallet ->
        {:noreply, socket}

      :unread ->
        {:noreply, assign(socket, figure, :unread)}

      micro ->
        {:noreply,
         assign(socket, [{figure, micro}, latest: Map.put(socket.assigns.latest, figure, micro)])}
    end
  end

  # A confirmed approval sets what staking may take to exactly its amount, so
  # the panel knows it from the receipt it just read, before the next read. It
  # is the shown wallet's figure only when that wallet sent it.
  defp approved(%{assigns: %{wallet: wallet}} = socket, hash) do
    case Enum.find(socket.assigns.presses.sent, &(&1.hash == hash)) do
      %{
        name: "approve",
        outcome: :confirmed,
        review: %{signer: ^wallet, inputs: %{"amount" => amount}}
      } ->
        assign(socket, allowance: Chains.micro(dollars(amount)))

      _other ->
        socket
    end
  end

  # The review follows the signer and the amount. A new amount is a new purchase
  # number; a repeat press of the same review buys again under the same number,
  # which is a second purchase.
  defp sync(socket) do
    %{linked: linked, active: active, amount: amount} = socket.assigns
    signer = OnchainSteps.signer(linked, active)
    dollars = dollars(amount)
    inputs = %{"amount" => amount}

    socket =
      if {inputs, signer} == {socket.assigns[:inputs], socket.assigns.signer},
        do: socket,
        else: assign(socket, inputs: inputs, number: Ecto.UUID.generate())

    review =
      if signer do
        steps =
          if dollars, do: Chains.steps(:base, dollars, socket.assigns.number), else: []

        Review.new(socket.assigns.id, signer, Chains.chain(:base), steps, inputs)
      end

    # A new amount changes no balance, so only a new wallet reads them.
    wallet = OnchainSteps.shown_wallet(linked, socket.assigns.own, active)

    socket =
      if wallet == socket.assigns.wallet,
        do: assign(socket, signer: signer),
        else:
          socket
          |> assign(signer: signer, wallet: wallet, usdc: nil, allowance: nil, latest: %{})
          |> read_funds()

    socket
    |> assign(mismatch: OnchainSteps.mismatch_note(linked, active))
    |> remember_number(review)
    |> OnchainSteps.put_review(review)
  end

  defp remember_number(socket, nil), do: socket

  defp remember_number(socket, review),
    do: assign(socket, numbers: Map.put(socket.assigns.numbers, review.id, socket.assigns.number))

  # A sent Buy is followed by its own job, which reports it once the chain
  # holds it and checks it until it counts; the page shows it waiting until
  # the job says how it ended. Pressing Check again follows it once more.
  defp follow(socket, hash, review) do
    number = Map.fetch!(socket.assigns.numbers, review.id)
    dollars = dollars(review.inputs["amount"])

    case CheckPurchase.start(socket.assigns.account, review.signer, dollars, number, hash) do
      {:ok, _job} -> put_purchase(socket, hash, %{purchase: :reporting, stalled?: false})
      {:error, _not_queued} -> put_purchase(socket, hash, %{purchase: nil, stalled?: false})
    end
  end

  defp put_purchase(socket, hash, shown),
    do: assign(socket, purchases: Map.put(socket.assigns.purchases, hash, shown))

  # The shown wallet's USDC on Base, and what REGENT staking may take of it,
  # both at the latest block. The figures already shown stay on screen, but from
  # here until each new read lands none of them holds Buy back. Each account has
  # a read allowance; past it, a wallet not read yet shows them unavailable.
  defp read_funds(%{assigns: %{wallet: nil}} = socket), do: socket

  defp read_funds(socket) do
    %{usdc: usdc, allowance: allowance} = socket.assigns
    socket = assign(socket, latest: %{})

    case Limits.spend(:wallet_read, {:human, socket.assigns.account.id}) do
      :ok -> start_reads(socket)
      :limited -> assign(socket, usdc: usdc || :unread, allowance: allowance || :unread)
    end
  end

  defp start_reads(socket) do
    wallet = socket.assigns.wallet

    socket
    |> start_async(:usdc, fn -> {wallet, usdc_call("balanceOf(address)", [wallet])} end)
    |> start_async(:allowance, fn ->
      {wallet, usdc_call("allowance(address,address)", [wallet, Chains.staking()])}
    end)
  end

  defp read({:ok, {wallet, {:ok, micro}}}, wallet), do: micro
  defp read({:ok, {wallet, _unread}}, wallet), do: :unread
  defp read({:ok, {_other, _answer}}, _wallet), do: :other_wallet
  defp read({:exit, _reason}, _wallet), do: :unread

  defp usdc_call(signature, args) do
    call = %{to: Chains.usdc(:base), data: Call.encode(signature, args)}

    with {:ok, "0x" <> hex} <-
           ChainClient.rpc(Chains.chain(:base), "eth_call", [call, "latest"]) do
      {:ok, String.to_integer(hex, 16)}
    end
  end

  # The account as the page gave it, or as it reads now before each event and
  # each background result (`Session.check_component_lease/2`): the wallets that may act and the
  # review follow it.
  defp take_account(socket, account) do
    context = AccessContext.for_account(account)

    socket
    |> assign(
      account: account,
      linked: AccessContext.linked_wallets(context),
      own: AccessContext.own_wallet(context)
    )
    |> sync()
  end

  defp dollars(amount) do
    case Integer.parse(String.trim(amount)) do
      {n, ""} when n in 5..500 -> n
      _not_whole_dollars -> nil
    end
  end

  # Why an amount can't be bought, in words for the person; nil when it can.
  defp amount_problem(amount) do
    case Integer.parse(String.trim(amount)) do
      {n, ""} when n in 5..500 -> nil
      {n, ""} when n < 5 -> "The minimum is 5 USDC."
      {n, ""} when n > 500 -> "The maximum is 500 USDC per purchase."
      _not_whole -> "Enter a whole number from 5 to 500."
    end
  end

  @impl true
  def render(assigns) do
    dollars = dollars(assigns.amount)

    assigns =
      assign(assigns,
        dollars: dollars,
        problem: amount_problem(assigns.amount),
        approve: approve_step(assigns, dollars),
        buy: step(assigns, "buy"),
        blocked: blocked(assigns, dollars)
      )

    ~H"""
    <section id={@id} class="credits-panel" phx-hook="OnchainSteps" data-refresh-funds>
      <header class="credits-panel__head">
        <dl
          id={"#{@id}-figures"}
          class="credits-panel__figures"
          phx-hook="MotionCount"
          data-variant="flash"
        >
          <dt>Regents Credits</dt>
          <dd><span data-count>{figure(@credits, :available)}</span>{missing(@credits)}</dd>
          <dt>Held</dt>
          <dd><span data-count>{figure(@credits, :held)}</span>{missing(@credits)}</dd>
        </dl>
        <div class="credits-panel__links">
          <.link class="credits-panel__history" navigate={~p"/account/credits"}>
            Purchase History
          </.link>
          <button type="button" class="credits-panel__where" popovertarget={"#{@id}-where"}>
            <Shell.nine_dots_icon class="credits-panel__where-icon" /> Where to spend
          </button>
        </div>
      </header>

      <%!-- The browser opens and closes it (`popover`), above the Buy dialog, and
           closes it on Escape or a press outside; a page update never shuts it. --%>
      <section
        id={"#{@id}-where"}
        class="credits-where"
        popover
        role="dialog"
        aria-labelledby={"#{@id}-where-title"}
      >
        <header class="credits-where__head">
          <h2 id={"#{@id}-where-title"}>Where to spend Credits</h2>
          <button
            type="button"
            class="credits-where__close"
            popovertarget={"#{@id}-where"}
            popovertargetaction="hide"
            aria-label="Close"
          >
            <svg viewBox="0 0 24 24" aria-hidden="true"><path d="M6 6l12 12M18 6L6 18" /></svg>
          </button>
        </header>
        <ul>
          <li :for={site <- Shell.regents_products()}>
            <a href={site.url} target="_blank" rel="noopener">
              <span class="shell-apps__tile" data-tone={site.tone}><Shell.crown /></span>
              <span class="credits-where__words">
                <strong>{site.name}</strong>
                <span>{site.credits}</span>
              </span>
            </a>
          </li>
        </ul>
      </section>

      <form
        id={"#{@id}-form"}
        class="credits-panel__form"
        phx-change="change"
        phx-submit="change"
        phx-target={@myself}
      >
        <label class="credits-panel__label" for={"#{@id}-amount"}>USDC on Base</label>
        <div class="credits-panel__amount" data-invalid={@problem && "true"}>
          <input
            id={"#{@id}-amount"}
            name="amount"
            value={@amount}
            inputmode="numeric"
            autocomplete="off"
            aria-describedby={"#{@id}-rate #{@id}-problem"}
            aria-invalid={@problem && "true"}
            data-onchain-input="amount"
          />
          <span aria-hidden="true">USDC</span>
        </div>
        <p id={"#{@id}-rate"} class="credits-panel__rate">
          Regents Credits can be used across all Regents sites.
        </p>
        <p
          id={"#{@id}-problem"}
          class="credits-panel__problem"
          role="alert"
          phx-hook="MotionRefusal"
          data-refused
        >
          {@problem}
        </p>
      </form>

      <%!-- Lines above the buttons stay in the page with their room kept, so one
           appearing never moves or replaces the button a person is about to press. --%>
      <div class="credits-panel__wallet" data-empty={is_nil(@wallet)}>
        <span class="credits-panel__muted">{if @signer, do: "Paying from", else: "Wallet"}</span>
        <P.address :if={@wallet} id={"#{@id}-wallet"} address={@wallet} />
        <span class="credits-panel__usdc">{usdc(@usdc)}</span>
      </div>
      <p class="credits-panel__note credits-panel__mismatch">
        <OnchainSteps.note :if={@mismatch} id={"#{@id}-mismatch"} parts={@mismatch} />
      </p>

      <ol class="credits-panel__steps">
        <li class="credits-panel__step" data-state={@approve.state}>
          <P.button variant="secondary" data-onchain-step="approve">
            <span data-press-label>Approve</span>
          </P.button>
          <div class="credits-panel__step-words">
            <strong>
              Approve {@dollars && "#{@dollars} "}USDC
              <P.tip id={"#{@id}-approve-tip"} label="About approving">
                Lets REGENT staking take this USDC for your purchase. Each purchase needs its own approval.
              </P.tip>
            </strong>
            <span :if={@approve.words}>{@approve.words}</span>
          </div>
          <.check_again step={@approve} myself={@myself} />
        </li>
        <li class="credits-panel__step" data-state={@buy.state}>
          <P.button
            data-onchain-step="buy"
            disabled={@blocked != nil}
            aria-describedby={@blocked && "#{@id}-buy-why"}
          >
            <span data-press-label>Buy</span>
          </P.button>
          <div class="credits-panel__step-words">
            <strong>
              Buy {@dollars && "#{@dollars} "}Credits
              <P.tip id={"#{@id}-buy-tip"} label="About buying">
                Sends the USDC to REGENT staking. Your Credits arrive in about 2 seconds.
              </P.tip>
            </strong>
            <span :if={@buy.words}>{@buy.words}</span>
            <span :if={@buy.help?}>
              If USDC left your wallet, post the link in <a
                href="https://patchbay.help/credits-help"
                target="_blank"
                rel="noopener"
              >Credits help</a>.
            </span>
            <span :if={@blocked} id={"#{@id}-buy-why"}>{@blocked}</span>
          </div>
          <.check_again step={@buy} myself={@myself} />
        </li>
      </ol>

      <%!-- Room for three lines is kept, so a note never moves the links below. --%>
      <div class="credits-panel__press-notes">
        <p :if={@press_note} class="credits-panel__note" role="status">
          <OnchainSteps.note id={"#{@id}-press-note"} parts={@press_note} />
        </p>
        <p class="credits-panel__note" role="status" data-onchain-lost hidden>
          Connection lost, so nothing was sent. Press again once it's back.
        </p>
      </div>

      <footer class="credits-panel__legal">
        <a href="https://regents.sh/terms" target="_blank" rel="noopener">Terms of Service</a>
        <a href="https://regents.sh/credits/refunds" target="_blank" rel="noopener">
          Refund Policy
        </a>
      </footer>
    </section>
    """
  end

  attr :step, :map, required: true
  attr :myself, :any, required: true

  defp check_again(%{step: %{entry: entry, stalled?: true}} = assigns) do
    assigns = assign(assigns, event: check_event(entry), hash: entry.hash)

    ~H"""
    <P.button
      variant="quiet"
      class="credits-panel__again"
      phx-click={@event}
      phx-value-hash={@hash}
      phx-target={@myself}
    >
      Check again
    </P.button>
    """
  end

  defp check_again(assigns), do: ~H""

  defp check_event(%{name: "buy", review: %{}}), do: "check_purchase_again"
  defp check_event(_entry), do: "check_again"

  # The latest press of the named step for the form as it stands now: its state
  # (`:ready` before any), what it did in words, and whether it waits on a
  # Check again.
  defp step(assigns, name) do
    %{presses: %{sent: sent}, purchases: purchases, inputs: inputs} = assigns

    case Enum.find(sent, &(&1.name == name and match?(%{inputs: ^inputs}, &1.review))) do
      nil ->
        %{state: :ready, words: nil, help?: false, entry: nil, stalled?: false}

      entry ->
        shown = purchases[entry.hash]

        %{
          state: step_state(state(entry, shown)),
          words: words(entry, shown),
          help?: help?(shown),
          entry: entry,
          stalled?: stalled?(entry, shown)
        }
    end
  end

  # Approve shows what the chain says staking may take: done while that covers
  # the amount, whichever press made it so, and ready again once a Buy spends it.
  defp approve_step(assigns, dollars) do
    step = step(assigns, "approve")

    cond do
      step.state == :pending -> step
      covered?(assigns.allowance, dollars) -> %{step | state: :done, words: nil}
      step.state == :done -> %{step | state: :ready, words: nil}
      true -> step
    end
  end

  defp covered?(allowance, dollars) when is_integer(allowance) and is_integer(dollars),
    do: allowance >= Chains.micro(dollars)

  defp covered?(_allowance, _dollars), do: false

  # Why Buy is certain to fail right now, from the shown wallet's last read at
  # the latest block; nil when it may go through. A figure still being read,
  # unread or past the read allowance is never a reason.
  defp blocked_step(assigns, "buy"), do: blocked(assigns, dollars(assigns.amount))
  defp blocked_step(_assigns, _step), do: nil

  defp blocked(_assigns, nil), do: nil

  defp blocked(%{latest: latest}, dollars) do
    micro = Chains.micro(dollars)

    cond do
      is_integer(latest[:usdc]) and latest.usdc < micro ->
        "Send USDC on Base to your wallet address first"

      is_integer(latest[:allowance]) and latest.allowance < micro ->
        "Approve first"

      true ->
        nil
    end
  end

  defp step_state(state) when state in [:confirmed, :credited], do: :done
  defp step_state(state) when state in [:pending, :checking, :stalled], do: :pending
  defp step_state(_failed), do: :failed

  defp stalled?(%{name: "buy"}, %{} = shown), do: purchase_stalled?(shown)
  defp stalled?(entry, nil), do: Presses.stalled?(entry)
  defp stalled?(_entry, _shown), do: false

  # Until the balance is read, or when it can't be, each figure is a dash, as
  # in the header; a word beside it would wrap on a phone and move the buttons.
  # The last balance read stays while it is read again.
  defp figure(%{state: state, value: %{} = balance}, field) when state in [:ready, :loading],
    do: balance |> Map.fetch!(field) |> Amount.format() |> String.replace_suffix(" Credits", "")

  defp figure(_credits, _field), do: "—"

  defp missing(%{state: state, value: %{}}) when state in [:ready, :loading], do: nil

  defp missing(%{state: state} = assigns) when state in [:error, :stale],
    do: ~H|<span class="visually-hidden">Unavailable</span>|

  defp missing(assigns), do: ~H|<span class="visually-hidden">Loading</span>|

  defp state(entry, nil), do: OnchainSteps.describe(entry, chain_name_of(entry)).state
  defp state(_entry, %{purchase: :reporting}), do: :checking
  defp state(_entry, %{purchase: nil}), do: :unrecorded
  defp state(_entry, %{purchase: purchase}), do: purchase.status

  # A step on its way or done shows as a mark; only trouble needs words.
  defp words(entry, nil) do
    case OnchainSteps.describe(entry, chain_name_of(entry)) do
      %{state: :pending} -> "Waiting for #{chain_name_of(entry)}"
      %{state: :confirmed} -> nil
      %{words: words} -> words
    end
  end

  defp words(entry, %{purchase: :reporting}), do: "Waiting for #{chain_name_of(entry)}"

  defp words(_entry, %{purchase: nil}),
    do: "Your wallet sent this, but this page couldn't record it."

  defp words(_entry, %{purchase: purchase} = shown) do
    case purchase do
      %{status: :credited, amount: amount} ->
        "#{Amount.format(amount)} added"

      %{status: :failed, reason: "reverted"} ->
        "Didn't go through. Nothing moved."

      %{status: :failed, reason: "already credited"} ->
        "Already counted."

      %{status: :failed, reason: "not found"} ->
        "Base never showed this payment. No Credits added."

      %{status: :failed} ->
        "Not the purchase this page prepared. No Credits added."

      %{status: :checking} ->
        checking_words(shown)
    end
  end

  # A sent payment the page couldn't match to a purchase points to Credits help.
  defp help?(%{purchase: nil}), do: true

  defp help?(%{purchase: %{status: :failed, reason: reason}}),
    do: reason not in ["reverted", "already credited", "not found"]

  defp help?(_shown), do: false

  defp checking_words(shown) do
    if purchase_stalled?(shown),
      do: "Still checking. It counts even if you close this page.",
      else: "Waiting for Base"
  end

  defp purchase_stalled?(%{purchase: %{status: :checking}, stalled?: stalled?}), do: stalled?
  defp purchase_stalled?(_shown), do: false

  defp chain_name_of(%{review: %{chain: %{name: name}}}), do: name
  defp chain_name_of(_unknown), do: "the network"

  defp usdc(nil), do: "…"
  defp usdc(:unread), do: "unavailable"

  defp usdc(micro) do
    dollars = micro |> Decimal.new() |> Decimal.div(1_000_000) |> Decimal.round(2, :down)
    "#{Decimal.to_string(dollars, :normal)} USDC"
  end
end
