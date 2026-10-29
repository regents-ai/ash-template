defmodule AshTemplateWeb.AccountLive do
  @moduledoc """
  /account, the same on every Regent site: the signed-in person's Account, one
  tab each. Account (their profile, their Credits, the agents they paired and
  pairing a new one, in the layout every Regent site shares,
  `Regent.Account.layout`), Points (`AshTemplateWeb.PointsLive`), Credits (their
  Credits history, `AshTemplateWeb.CreditsHistoryLive`), Wallets (the wallets
  their sign-in verified) and Connections (the accounts they have connected).
  The site's own sections and tabs come first (`AshTemplateWeb.AccountSite`).

  The site's shell LiveView routes the tabs (`AshTemplateWeb.AccountRoutes`),
  calls `attach/1` in its mount, which reads what each tab shows and answers its
  events, and draws `page/1` on a tab. Everything is read from the sign-in the
  shell already holds; nothing on the page asks the visitor to sign in again.

  Copied from ash-template unchanged; `scripts/drift.sh --account` names any site
  whose copy differs.
  """

  use AshTemplateWeb, :html

  import AshTemplateWeb.Components.PageHead, only: [page_head: 1]
  import AshTemplateWeb.Components.VerifiedConnections
  import Phoenix.LiveView, only: [attach_hook: 4, connected?: 1, push_event: 3, send_update: 2]

  alias AshTemplate.Accounts
  alias AshTemplate.Accounts.LinkedIdentity.Providers
  alias AshTemplate.Actors.Human

  alias AshTemplateWeb.{
    AccountSite,
    AgentsPanel,
    CreditsHistoryLive,
    PairingBox,
    PointsLive,
    Read
  }

  alias AshTemplateWeb.RouteCatalog.RouteTarget

  @shared_tabs [
    %RouteTarget{route_id: :account, label: "Account", path: "/account"},
    %RouteTarget{route_id: :points, label: "Points", path: "/account/points"},
    %RouteTarget{route_id: :credits, label: "Credits", path: "/account/credits"},
    %RouteTarget{route_id: :wallets, label: "Wallets", path: "/account/wallets"},
    %RouteTarget{route_id: :connections, label: "Connections", path: "/account/connections"}
  ]
  @tab_ids Enum.map(@shared_tabs, & &1.route_id)

  @actions %{"link" => :link, "unlink" => :unlink}
  @refused %{
    tone: :error,
    message: "That connection couldn’t be updated. Refresh the page and try again."
  }

  @doc "The tabs of /account in order: the site's own, then the five every site has."
  def tabs, do: AccountSite.tabs() ++ @shared_tabs

  @doc "Whether a live action is one of the five shared tabs."
  def tab?(action), do: action in @tab_ids

  @doc """
  Readies the shell LiveView for the tabs: what each shows, read when it opens
  and again when it changes, and the Connections tab's events. Called from the
  shell's `mount/3`, once the sign-in is on the socket.
  """
  def attach(socket) do
    if connected?(socket), do: hear_points(socket.assigns.access_context)

    socket
    |> assign(
      verified_connections: %Read{},
      points: %Read{},
      credits_history: %Read{},
      points_bonus: %Read{},
      points_earning: [],
      verified_connections_notice: nil,
      connection_outcome: nil
    )
    |> attach_hook(:account_tabs, :handle_params, fn _params, _uri, socket ->
      {:cont, open(socket, socket.assigns.live_action)}
    end)
    |> attach_hook(:account_tabs, :handle_event, &event/3)
    |> attach_hook(:account_tabs, :handle_info, &info/2)
  end

  attr :tab, :atom, required: true, doc: "the live action, one of the five shared tabs"
  attr :signed_out_reason, :atom, default: :signed_out
  attr :lease, :map, required: true
  attr :account, :map, default: nil
  attr :account_control, :map, required: true
  attr :sign_in_wallets, :map, required: true
  attr :credits_read, Read, required: true
  attr :credits_history, Read, required: true
  attr :points, Read, required: true
  attr :points_bonus, Read, required: true
  attr :points_earning, :list, required: true
  attr :verified_connections, Read, required: true
  attr :verified_connections_notice, :map, default: nil

  @doc "The tab the shell is on."
  def page(%{tab: :account} = assigns) do
    ~H"""
    <.profile
      signed_out_reason={@signed_out_reason}
      lease={@lease}
      account={@account}
      account_control={@account_control}
      credits_read={@credits_read}
    />
    """
  end

  def page(%{tab: :points} = assigns) do
    ~H"""
    <PointsLive.page
      signed_out_reason={@signed_out_reason}
      account={@account}
      points={@points}
      bonus={@points_bonus}
      earning={@points_earning}
    />
    """
  end

  def page(%{tab: :credits} = assigns) do
    ~H"""
    <CreditsHistoryLive.page
      signed_out_reason={@signed_out_reason}
      account={@account}
      history={@credits_history}
    />
    """
  end

  def page(%{tab: :wallets} = assigns) do
    ~H"""
    <.wallets
      signed_out_reason={@signed_out_reason}
      account={@account}
      sign_in_wallets={@sign_in_wallets}
    />
    """
  end

  def page(%{tab: :connections} = assigns) do
    ~H"""
    <.connections
      signed_out_reason={@signed_out_reason}
      account={@account}
      verified_connections={@verified_connections}
      verified_connections_notice={@verified_connections_notice}
    />
    """
  end

  attr :lease, :map, required: true
  attr :account, :map, default: nil
  attr :signed_out_reason, :atom, default: :signed_out
  attr :account_control, :map, required: true
  attr :credits_read, Read, required: true

  defp profile(assigns) do
    ~H"""
    <.settings_page
      id="account-page"
      title="Account"
      account={@account}
      signed_out_reason={@signed_out_reason}
    >
      <:tip>Your profile, your Credits and your agents.</:tip>
      <Regent.Account.layout id="account">
        <:site :for={section <- AccountSite.sections()}>
          {section.(%{account: @account, lease: @lease, account_control: @account_control})}
        </:site>
        <:identity>
          <Regent.Account.identity
            id="account-identity"
            name={@account_control.label}
            wallet={@account_control.wallet}
            ens_name={@account_control.ens_name}
          >
            <:picture>
              <AshTemplateWeb.Components.Shell.account_picture
                id="account-identity-picture"
                squares={@account_control.squares}
                picture={@account_control.picture}
                size={64}
              />
            </:picture>
          </Regent.Account.identity>
        </:identity>
        <:agents>
          <.live_component module={AgentsPanel} id="account-agents" lease={@lease} account={@account} />
        </:agents>
        <:pairing>
          <.live_component
            module={PairingBox}
            id="account-pairing-box"
            lease={@lease}
            account={@account}
          />
        </:pairing>
        <:credits>
          <Regent.Account.credits_summary
            id="account-credits"
            available={
              @credits_read.value && RegentCredits.Amount.format(@credits_read.value.available)
            }
            held={@credits_read.value && RegentCredits.Amount.format(@credits_read.value.held)}
            state={if @credits_read.state in [:idle, :empty], do: :loading, else: @credits_read.state}
          >
            <a href="https://regents.sh/account">Manage Credits on regents.sh</a>
          </Regent.Account.credits_summary>
        </:credits>
        <:profile>
          <%!-- The name is saved from the browser with the sign-in's own proof. --%>
          <div id="account-profile" phx-hook="PublicName" phx-update="ignore">
            <Regent.Profile.panel
              id="account-public-name"
              class="account-panel"
              display_name={@account.display_name}
            />
          </div>
        </:profile>
      </Regent.Account.layout>
    </.settings_page>
    """
  end

  attr :account, :map, default: nil
  attr :signed_out_reason, :atom, default: :signed_out
  attr :sign_in_wallets, :map, required: true

  defp wallets(assigns) do
    assigns = assign(assigns, :named, named_wallets(assigns.account, assigns.sign_in_wallets))

    ~H"""
    <.settings_page
      id="wallets-page"
      title="Wallets"
      account={@account}
      signed_out_reason={@signed_out_reason}
    >
      <:tip>The wallets your sign-in verified.</:tip>
      <section class="account-panel account-details" aria-labelledby="account-wallets-title">
        <h2 id="account-wallets-title">Your wallets</h2>
        <dl>
          <div :if={@named.user}>
            <dt>User wallet</dt>
            <dd>
              <Regent.Primitives.address id="account-user-wallet" address={@named.user} />
            </dd>
          </div>
          <div>
            <dt>Regents embedded wallet</dt>
            <dd :if={@named.embedded}>
              <Regent.Primitives.address id="account-embedded-wallet" address={@named.embedded} />
            </dd>
            <dd :if={is_nil(@named.embedded)}>Made for you at your next sign-in</dd>
          </div>
          <div :if={@named.others != []}>
            <dt>Other linked wallets</dt>
            <dd>
              <ul class="account-wallet-list">
                <li :for={wallet <- @named.others}>
                  <Regent.Primitives.address id={"account-wallet-#{wallet}"} address={wallet} />
                </li>
              </ul>
            </dd>
          </div>
        </dl>
      </section>
    </.settings_page>
    """
  end

  attr :account, :map, default: nil
  attr :signed_out_reason, :atom, default: :signed_out
  attr :verified_connections, Read, required: true
  attr :verified_connections_notice, :map, default: nil

  defp connections(assigns) do
    ~H"""
    <.settings_page
      id="connections-page"
      title="Connections"
      account={@account}
      signed_out_reason={@signed_out_reason}
    >
      <:tip>Accounts you have connected, such as X, GitHub and Farcaster.</:tip>
      <.verified_connections
        id="account-verified-connections"
        class="account-panel"
        identities={@verified_connections.value}
        read_state={@verified_connections.state}
        notice={@verified_connections_notice}
      />
    </.settings_page>
    """
  end

  attr :id, :string, required: true
  attr :title, :string, required: true
  attr :account, :map, default: nil
  attr :signed_out_reason, :atom, default: :signed_out
  slot :tip, required: true
  slot :inner_block, required: true

  defp settings_page(assigns) do
    ~H"""
    <article id={@id} class="account-page rg-utility">
      <.page_head title={@title}>
        <:tip>{render_slot(@tip)}</:tip>
      </.page_head>

      <Regent.Account.signed_out
        :if={is_nil(@account)}
        id={"#{@id}-signed-out"}
        reason={@signed_out_reason}
      >
        <:sign_in>
          <Regent.Primitives.button type="button" data-account-target="sign-in">
            Sign in
          </Regent.Primitives.button>
        </:sign_in>
      </Regent.Account.signed_out>

      {@account && render_slot(@inner_block)}
    </article>
    """
  end

  # The sign-in names which linked wallet Privy made for the person and which is
  # their own. A name for a wallet the account no longer holds is not shown, so
  # an outside wallet is never shown as the Regents wallet.
  defp named_wallets(nil, _sign_in_wallets), do: %{user: nil, embedded: nil, others: []}

  defp named_wallets(%{wallet_addresses: wallets}, sign_in_wallets) do
    linked = wallets |> List.wrap() |> Enum.map(&String.downcase/1) |> Enum.uniq()
    named = fn key -> if sign_in_wallets[key] in linked, do: sign_in_wallets[key] end
    user = named.("user")
    embedded = named.("embedded")

    %{user: user, embedded: embedded, others: linked -- [user, embedded]}
  end

  # A points award or correction for this account reaches the Points tab.
  defp hear_points(%{principal: {:human, account}}),
    do: Phoenix.PubSub.subscribe(AshTemplate.PubSub, "points:#{account.id}")

  defp hear_points(_access_context), do: :ok

  # Each tab reads what it shows when it opens; leaving it drops the reading.
  defp open(socket, action) do
    socket
    |> load_points(action)
    |> load_credits_history(action)
    |> load_verified_connections(action)
  end

  defp event("request_verified_connection", %{"action" => action, "provider" => provider}, socket) do
    with %Human{} <- human_actor(socket),
         {:ok, provider} <- Providers.parse(provider),
         {:ok, action} <- Map.fetch(@actions, action),
         {:ok, request} <-
           identity_request(action, provider, socket.assigns.verified_connections.value) do
      {:halt,
       socket
       |> assign(
         verified_connections_notice: %{tone: :info, message: connection_started(request)}
       )
       |> push_event("verified-connections:request", request)}
    else
      _refused -> {:halt, assign(socket, verified_connections_notice: @refused)}
    end
  end

  # The outcome is judged against the connections read after the provider came back.
  defp event("refresh_verified_connections", params, socket) do
    {:halt,
     socket
     |> assign(connection_outcome: params, verified_connections_notice: nil)
     |> read_verified_connections()
     |> report_connection_outcome()}
  end

  # The Account tab saved the person's name in the shared profile. Every event
  # reads the account again first (`AshTemplateWeb.Live.Session`), so the page
  # already shows the new name everywhere it appears.
  defp event("public_name_saved", _params, socket), do: {:halt, socket}

  defp event("credits_history_older", _params, socket) do
    with %Read{value: %{more?: true} = history} <- socket.assigns.credits_history,
         account when account != nil <- current_account(socket) do
      actor = AshTemplate.Credits.person(account)

      {:halt,
       Read.now(socket, :credits_history, account.privy_user_id, fn ->
         CreditsHistoryLive.older(history, &RegentCredits.history(&1, actor: actor))
       end)}
    else
      _no_more -> {:halt, socket}
    end
  end

  defp event(_event, _params, socket), do: {:cont, socket}

  defp info(%{topic: "points:" <> _}, %{assigns: %{live_action: :points}} = socket),
    do: {:halt, read_points(socket)}

  defp info(%{topic: "points:" <> _}, socket), do: {:halt, socket}

  # The balance changed on this or any Regent site: the Credits tab reads its
  # history again, and the shell its balance.
  defp info(:credits_changed, socket),
    do: {:cont, load_credits_history(socket, socket.assigns.live_action)}

  # An agent paired, checked in or was unpaired, here or on another Regent site:
  # the Account tab lists the agents and holds the pairing box.
  defp info(:agents_changed, %{assigns: %{live_action: :account}} = socket) do
    send_update(AgentsPanel, id: "account-agents", agents_changed: true)
    send_update(PairingBox, id: "account-pairing-box", agents_changed: true)
    {:cont, socket}
  end

  defp info(_message, socket), do: {:cont, socket}

  defp current_account(%{assigns: %{access_context: %{principal: {:human, account}}}}),
    do: account

  defp current_account(_socket), do: nil

  defp human_actor(socket) do
    case current_account(socket) do
      nil -> nil
      account -> Human.for_account(account)
    end
  end

  # The newest page of the account's Credits history, read again on each
  # change with the older pages already shown kept below it.
  defp load_credits_history(socket, :credits) do
    case current_account(socket) do
      nil ->
        Read.clear(socket, :credits_history)

      account ->
        actor = AshTemplate.Credits.person(account)
        shown = shown_history(socket.assigns.credits_history, account)

        Read.now(socket, :credits_history, account.privy_user_id, fn ->
          newest_history(actor, shown)
        end)
    end
  end

  defp load_credits_history(socket, _action), do: Read.clear(socket, :credits_history)

  defp newest_history(actor, shown) do
    with {:ok, page} <- RegentCredits.history(%{}, actor: actor),
         do: {:ok, CreditsHistoryLive.refreshed(page, shown)}
  end

  defp shown_history(%Read{owner: owner, value: %{} = history}, %{privy_user_id: owner}),
    do: history

  defp shown_history(_read, _account), do: nil

  # The NFT tier is read from Base once per page open, never on each award
  # notice, and not at all while nothing earns.
  defp load_points(socket, :points) do
    socket
    |> assign(:points_earning, RegentPoints.Rules.active())
    |> read_points()
    |> read_points_bonus()
  end

  defp load_points(socket, _action),
    do: socket |> Read.clear(:points) |> Read.clear(:points_bonus)

  defp read_points(socket) do
    case human_actor(socket) do
      %Human{} = actor ->
        Read.now(socket, :points, actor.human_account_id, fn ->
          RegentPoints.summary(actor: actor)
        end)

      nil ->
        Read.clear(socket, :points)
    end
  end

  defp read_points_bonus(%{assigns: %{points_earning: []}} = socket),
    do: Read.clear(socket, :points_bonus)

  defp read_points_bonus(socket) do
    case human_actor(socket) do
      %Human{human_account_id: id} ->
        Read.start(socket, :points_bonus, id, fn -> points_bonus(id) end)

      nil ->
        Read.clear(socket, :points_bonus)
    end
  end

  # Base is read for the person's NFTs, counted against the same per-account
  # allowance as the Buy panel's reads.
  defp points_bonus(id) do
    case AshTemplate.Limits.spend(:wallet_read, {:human, id}) do
      :ok -> RegentPoints.Bonus.current(id)
      :limited -> {:error, :limited}
    end
  end

  defp load_verified_connections(socket, :connections), do: read_verified_connections(socket)

  defp load_verified_connections(socket, _action) do
    socket
    |> Read.clear(:verified_connections)
    |> assign(verified_connections_notice: nil, connection_outcome: nil)
  end

  # The account's own record is the only thing a connection is read from, so
  # nothing the browser reports can name a connection the record does not hold.
  defp read_verified_connections(socket) do
    case human_actor(socket) do
      %Human{} = actor ->
        Read.now(socket, :verified_connections, actor.human_account_id, fn ->
          Accounts.list_my_linked_identities(actor: actor)
        end)

      nil ->
        Read.clear(socket, :verified_connections)
    end
  end

  defp identity_request(:link, provider, _identities),
    do: {:ok, %{action: :link, provider: provider}}

  defp identity_request(:unlink, provider, identities) when is_list(identities) do
    case Enum.find(identities, &(&1.provider == provider)) do
      nil -> :error
      identity -> {:ok, %{action: :unlink, provider: provider, subject: identity.subject}}
    end
  end

  defp identity_request(_action, _provider, _identities), do: :error

  # X and GitHub take the whole tab to their own approval page and bring it
  # back; Farcaster asks for a scan here.
  defp connection_started(%{action: :link, provider: :farcaster}),
    do: "Scan the code with Farcaster to approve the connection."

  defp connection_started(%{action: :link, provider: provider}),
    do: "Taking you to #{Providers.label(provider)} to approve the connection."

  defp connection_started(%{action: :unlink, provider: provider}),
    do: "Disconnecting #{Providers.label(provider)}…"

  defp report_connection_outcome(%{assigns: %{connection_outcome: nil}} = socket), do: socket

  defp report_connection_outcome(%{assigns: assigns} = socket) do
    notice = connection_outcome(assigns.connection_outcome, assigns.verified_connections)
    assign(socket, verified_connections_notice: notice, connection_outcome: nil)
  end

  defp connection_outcome(%{"error" => "already-connected"}, _read),
    do: %{tone: :error, message: "That account is already connected to another account here."}

  defp connection_outcome(%{"error" => error}, _read) when is_binary(error) and error != "",
    do: %{tone: :error, message: "That connection couldn’t be verified. Try again."}

  defp connection_outcome(params, %Read{state: state, value: identities})
       when state in [:ready, :empty] do
    with {:ok, provider} <- Providers.parse(params["provider"]),
         {:ok, action} <- Map.fetch(@actions, params["action"]) do
      label = Providers.label(provider)

      case {action, Enum.any?(identities, &(&1.provider == provider))} do
        {:link, true} ->
          %{tone: :success, message: "#{label} connected."}

        {:link, false} ->
          %{tone: :error, message: "#{label} didn’t come back connected. Try again."}

        {:unlink, false} ->
          %{tone: :success, message: "#{label} disconnected."}

        {:unlink, true} ->
          %{tone: :error, message: "#{label} is still connected. Try again."}
      end
    else
      :error -> nil
    end
  end

  defp connection_outcome(_params, _read), do: nil
end
