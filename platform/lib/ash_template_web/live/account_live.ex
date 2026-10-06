defmodule AshTemplateWeb.AccountLive do
  @moduledoc """
  The signed-in person's Settings, one tab each: Profile (who the site knows
  them as, their Credits and this browser's session), Wallets (the wallets
  their sign-in verified) and Connections (the accounts they have connected).

  Everything here is read from the sign-in the shell already holds; nothing on
  the page asks the visitor to sign in again.
  """

  use AshTemplateWeb, :html

  import AshTemplateWeb.Components.VerifiedConnections

  alias AshTemplate.PublicIdentity

  attr :account, :map, default: nil
  attr :account_control, :map, required: true
  attr :credits, Decimal, default: nil

  def profile(assigns) do
    ~H"""
    <.settings_page id="account-page" title="Profile" account={@account}>
      <:lede>Who Ash Template knows you as, and your session on this browser.</:lede>
      <div class="account-grid">
        <Regent.HolographicCard.card
          id="account-identity"
          class="account-identity"
          phx-hook="HolographicCard"
          data-holo-crown="false"
        >
          <p class="account-kicker">Your account</p>
          <div class="account-identity__who">
            <img
              :if={@account_control.avatar_src}
              class="account-identity__avatar"
              src={@account_control.avatar_src}
              referrerpolicy="no-referrer"
              width="64"
              height="64"
              alt=""
            />
            <div class="account-identity__name">
              <h2>{@account_control.label}</h2>
              <p :if={short_wallet(@account) not in [nil, @account_control.label]}>
                <code>{short_wallet(@account)}</code>
              </p>
            </div>
          </div>
        </Regent.HolographicCard.card>

        <section class="account-panel account-details" aria-labelledby="account-details-title">
          <h2 id="account-details-title">Details</h2>
          <dl>
            <div>
              <dt>Display name</dt>
              <dd>{@account.display_name || "Not set"}</dd>
            </div>
          </dl>
        </section>

        <section
          :if={@credits}
          id="account-credits"
          class="account-panel account-details"
          aria-labelledby="account-credits-title"
        >
          <h2 id="account-credits-title">Credits</h2>
          <dl>
            <div>
              <dt>Balance</dt>
              <dd>{RegentCredits.Amount.format(@credits)}</dd>
            </div>
          </dl>
          <p>
            All account settings, including what your agents may spend, live at <a href="https://regents.sh/account">regents.sh/account</a>.
            Sign in there with the same login you use here.
          </p>
        </section>

        <section class="account-panel account-session" aria-labelledby="account-session-title">
          <h2 id="account-session-title">Session</h2>
          <p>Signing out ends this session on this browser only.</p>
          <Regent.Primitives.button type="button" variant="secondary" data-account-target="sign-out">
            Sign out
          </Regent.Primitives.button>
        </section>
      </div>
    </.settings_page>
    """
  end

  attr :account, :map, default: nil

  def wallets(assigns) do
    ~H"""
    <.settings_page id="wallets-page" title="Wallets" account={@account}>
      <:lede>The wallets your sign-in verified.</:lede>
      <section class="account-panel account-details" aria-labelledby="account-wallets-title">
        <h2 id="account-wallets-title">Your wallets</h2>
        <dl>
          <div>
            <dt>Wallet</dt>
            <dd :if={@account.wallet_address} class="account-wallet">
              <code>{@account.wallet_address}</code>
              <Regent.Primitives.copy_button id="account-wallet-copy" text={@account.wallet_address}>
                Copy
              </Regent.Primitives.copy_button>
            </dd>
            <dd :if={is_nil(@account.wallet_address)}>No wallet linked</dd>
          </div>
          <div :if={other_wallets(@account) != []}>
            <dt>Other linked wallets</dt>
            <dd>
              <ul class="account-wallet-list">
                <li :for={wallet <- other_wallets(@account)}><code>{wallet}</code></li>
              </ul>
            </dd>
          </div>
        </dl>
      </section>
    </.settings_page>
    """
  end

  attr :account, :map, default: nil
  attr :verified_connections, AshTemplateWeb.Read, required: true
  attr :verified_connections_notice, :map, default: nil

  def connections(assigns) do
    ~H"""
    <.settings_page id="connections-page" title="Connections" account={@account}>
      <:lede>The accounts you have connected, such as X, GitHub and Farcaster.</:lede>
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
  slot :lede, required: true
  slot :inner_block, required: true

  defp settings_page(assigns) do
    ~H"""
    <article id={@id} class="account-page">
      <header class="account-heading">
        <p class="account-kicker">Settings</p>
        <h1 tabindex="-1">{@title}</h1>
        <p class="account-lede">{render_slot(@lede)}</p>
      </header>

      <section :if={is_nil(@account)} class="account-panel account-signed-out">
        <h2>Sign in to see your settings</h2>
        <p>Your profile, wallets and connections appear here once you are signed in.</p>
        <Regent.Primitives.button type="button" data-account-target="sign-in">
          Sign in
        </Regent.Primitives.button>
      </section>

      {@account && render_slot(@inner_block)}
    </article>
    """
  end

  defp other_wallets(%{wallet_address: primary, wallet_addresses: wallets}) do
    primary = primary && String.downcase(primary)

    wallets
    |> List.wrap()
    |> Enum.map(&String.downcase/1)
    |> Enum.uniq()
    |> Enum.reject(&(&1 == primary))
  end

  # The card names the person the way the header does; the wallet is only
  # repeated beneath when that name is something other than the wallet itself.
  defp short_wallet(%{wallet_address: wallet}) when is_binary(wallet),
    do: PublicIdentity.short_wallet(wallet)

  defp short_wallet(_account), do: nil
end
