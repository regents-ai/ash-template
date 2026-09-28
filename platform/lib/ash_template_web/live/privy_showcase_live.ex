defmodule AshTemplateWeb.PrivyShowcaseLive do
  @moduledoc """
  Executable reference for the Privy integration.

  The router supplies BOTH the showcase gate and the ordinary trusted Session hook.
  Shell.account_control/1 and data-account-target use the production auth_lazy.ts
  dispatcher. PrivyShowcase only observes the existing wallet store and publishes
  its selected address; it never creates a provider, session, signature or payment.
  """
  use AshTemplateWeb, :live_view

  alias AshTemplateWeb.Components.Shell
  alias AshTemplateWeb.ShowcaseLive
  alias Regent.Primitives, as: P

  @wallet ~r/\A0x[0-9a-fA-F]{40}\z/

  def mount(_params, session, socket) do
    {:ok,
     socket
     |> assign(AshTemplateWeb.PublicDocuments.page("/showcase/privy"))
     |> assign(
       theme: session["theme"] || "dark",
       mode: ShowcaseLive.privy_mode(),
       local?: AshTemplateWeb.Showcase.mode() == :local,
       wallet: nil
     ), layout: false}
  end

  def render(assigns) do
    ~H"""
    <link rel="stylesheet" href="/showcase/style.css" />
    <main
      id="privy-reference"
      class="sc privy-reference"
      phx-hook="PrivyShowcase"
      data-privy-enabled={to_string(@mode == :configured)}
    >
      <header class="sc-header privy-reference-header">
        <a class="sc-wordmark" href="/showcase">Ash <span>Workshop</span></a>
        <span class="sc-local">
          {if @local?,
            do: "Local only · this page only reads your wallet",
            else: "This page only reads your wallet"}
        </span>
        <%!-- Same markup and event markers as the site header. No second auth handler. --%>
        <Shell.account_control account_control={@account_control} enabled={@mode == :configured} />
        <Shell.theme_toggle id="privy-reference-theme" theme={@theme} />
      </header>

      <div class="privy-reference-content">
        <section class="privy-reference-intro">
          <p class="sc-eyebrow">Working example</p>
          <h1>Sign in with Privy</h1>
          <p>
            Sign in once, connect the wallet you want to use, and watch the selection arrive without replacing this page.
          </p>
          <p>Nothing on this page asks you to approve a transaction or sign a message.</p>
          <P.button
            type="button"
            disabled={@mode != :configured}
            data-account-target={
              if @account_control.kind == :signed_in, do: "connect-wallet", else: "sign-in"
            }
          >
            {if @account_control.kind == :signed_in,
              do: "Connect or change wallet",
              else: "Sign in with Privy"}
          </P.button>
          <p :if={@mode == :unconfigured} role="status">
            Sign-in isn't available on this copy of the site.
          </p>
        </section>

        <section class="rg-panel rg-panel--surface" aria-labelledby="privy-state-heading">
          <h2 id="privy-state-heading">Account and wallet</h2>
          <dl class="privy-reference-facts">
            <div>
              <dt>Status</dt><dd id="privy-session-state">
                {if @account_control.kind == :signed_in, do: "Signed in", else: "Signed out"}
              </dd>
            </div>
            <div>
              <dt>Account</dt><dd>{@account_control.label}</dd>
            </div>
            <div>
              <dt>Wallet in use</dt><dd id="privy-selected-wallet">
                {@wallet || "No wallet selected"}
              </dd>
            </div>
          </dl>
          <P.button
            type="button"
            disabled={@mode != :configured}
            data-account-target={
              if @account_control.kind == :signed_in, do: "connect-wallet", else: "sign-in"
            }
          >
            Connect wallet
          </P.button>
          <p>
            Signing in and having a wallet ready to send are two separate steps. Disconnect in the header clears the wallet shown here.
          </p>
        </section>

        <section
          class="rg-panel rg-panel--surface privy-reference-setup"
          aria-labelledby="privy-setup-heading"
        >
          <h2 id="privy-setup-heading">Set up your own copy</h2>
          <ol>
            <li>
              In your Privy dashboard, turn on wallet sign-in and add your site's exact web address to the allowed list.
            </li>
            <li>
              Give your copy of the site its Privy app ID and verification key, named
              <code>PRIVY_APP_ID</code>
              and <code>PRIVY_VERIFICATION_KEY</code>. Keep the Privy app secret off the page people load.
            </li>
            <li>
              Create your database, then prepare sign-in with the command <code>mix ash_template.setup_local_auth</code>.
            </li>
            <li>
              Start the site with the commands <code>mix assets.build</code>
              and <code>mix phx.server</code>, then open this page.
            </li>
          </ol>
          <details>
            <summary>What each part does</summary>
            <ul>
              <li>The sign-in button in the header, the same on every page.</li>
              <li>
                One small script that hears every sign-in button press and keeps the page and the site in step.
              </li>
              <li>The Privy connection: signing in, choosing a wallet and signing out.</li>
              <li>This page's wallet readout, which only watches and never signs anyone in.</li>
              <li>
                The site's own record of who is signed in. A wallet address in the browser never proves who you are.
              </li>
            </ul>
          </details>
          <p>
            The look comes from Regent's shared design kit, and the sign-in check comes from a shared Regent library. The Privy connection shown here belongs to this site.
          </p>
          <a
            href="https://docs.privy.io/authentication/user-authentication/logout"
            target="_blank"
            rel="noopener noreferrer"
          >Privy's guide to signing out ↗</a>
        </section>
      </div>
    </main>
    """
  end

  # The address is a public read target, never proof of authentication. Session
  # authority is independently supplied and rechecked by Live.Session.
  def handle_event("privy_wallet_changed", %{"address" => address}, socket),
    do: {:noreply, assign(socket, :wallet, normalize_wallet(address))}

  defp normalize_wallet(address) when is_binary(address) do
    if Regex.match?(@wallet, address), do: String.downcase(address)
  end

  defp normalize_wallet(_address), do: nil
end
