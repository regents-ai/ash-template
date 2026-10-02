defmodule AshTemplateWeb.ShowcaseLive do
  @moduledoc "The component workshop. Demo state lives in this LiveView."
  use AshTemplateWeb, :live_view
  alias AshTemplateWeb.Read
  alias AshTemplateWeb.Showcase.{Catalog, Sample, Utilities}
  alias Regent.Primitives, as: P
  alias Regent.Structure, as: S

  # Fixture wallets for the slow-read example: how long each takes to answer
  # and what it holds. A zero balance is a real reading, unlike a failed one.
  @fixture_wallets [
    {"slow",
     %{label: "Slow wallet", delay: 3_000, holdings: [{"REGENT", "1,250"}, {"USDC", "40.00"}]}},
    {"quick", %{label: "Quick wallet", delay: 400, holdings: [{"REGENT", "0"}]}},
    {"new", %{label: "New wallet", delay: 800, holdings: []}}
  ]

  @capabilities [
    %{
      index: "001",
      title: "Clear boundaries",
      tone: "accent",
      kind: :circles,
      image: nil,
      description: "Rules and shared edges give every region a deliberate place on the page.",
      href: "#foundations",
      action: "See the basics"
    },
    %{
      index: "002",
      title: "Common structure",
      tone: "surface",
      kind: :triangle,
      image: nil,
      description:
        "One set of components, put together to suit each product. Change the words and picture without rebuilding the card.",
      href: "#composition",
      action: "Explore composition"
    },
    %{
      index: "003",
      title: "Your imagery",
      tone: "surface",
      kind: :image,
      image: "/images/brand/mark-flat-dark.svg",
      description:
        "Use an image with a short description for screen readers, or your own artwork. Buttons on the card are optional.",
      href: "#inventory",
      action: "See every component"
    }
  ]

  @providers %{"x" => :x, "github" => :github, "farcaster" => :farcaster}

  @sections [
    {"01", "foundations", "Foundations"},
    {"02", "capabilities", "Capabilities"},
    {"03", "feedback", "Feedback"},
    {"04", "composition", "Composition"},
    {"05", "identity", "Identity & wallets"},
    {"06", "data", "Built with Ash"},
    {"07", "inventory", "Complete inventory"}
  ]

  @pages [
    {"/showcase/catalog", "Agent catalog"},
    {"/showcase/privy", "Privy sign-in"},
    {"/showcase/wallet", "Wallet buttons"},
    {"/showcase/payments", "Pay with USDC"},
    {"/showcase/discussion", "Discussion"}
  ]

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(AshTemplateWeb.PublicDocuments.page("/showcase"))
     |> assign(
       sections: @sections,
       pages: @pages,
       privy_mode: privy_mode(),
       local?: AshTemplateWeb.Showcase.mode() == :local,
       catalog: Catalog.snapshot(),
       capabilities: @capabilities,
       form: to_form(%{"title" => "First launch", "quantity" => "1"}, as: :sample),
       errors: [],
       records: [],
       empty_items: [],
       empty_error: nil,
       fixture_wallets: @fixture_wallets,
       balance: %Read{},
       fail_reads: false,
       step_title: "Current step",
       step_editing: false,
       step_form: to_form(%{"title" => "Current step"}, as: :step),
       step_errors: [],
       result: nil,
       identities: [],
       connection_notice: nil,
       route_spec: AshTemplateWeb.RouteCatalog.fetch!(:app),
       account: %AshTemplate.AccessContext.AccountControl{kind: :preview, label: "Sample account"}
     ), layout: false}
  end

  def render(%{live_action: :preview} = assigns) do
    ~H"""
    <AshTemplateWeb.Layouts.app
      flash={%{"info" => "A sample message at the top of the page."}}
      inner_content={nil}
    />
    <AshTemplateWeb.Components.Shell.shell
      route_spec={@route_spec}
      account_control={@account}
      shell_instance={0}
    >
      <:content>
        <div style="padding: 32px">
          <h1>Page frame preview</h1>
          <p>Menu, account button, theme switch and background.</p>
          <a href="/showcase" target="_top">Back to showcase</a>
        </div>
      </:content>
    </AshTemplateWeb.Components.Shell.shell>
    """
  end

  def render(assigns) do
    ~H"""
    <link rel="stylesheet" href="/showcase/style.css" />
    <S.frame id="showcase" phx-hook="Showcase" class="sc">
      <header class="sc-header">
        <a class="sc-wordmark" href="/showcase">Ash <span>Workshop</span></a>
        <span :if={@local?} class="sc-local">Local only</span>
        <a :for={{href, label} <- @pages} href={href} class="sc-api">{label} ↗</a>
      </header>
      <div class="sc-layout">
        <aside class="sc-sidebar">
          <nav aria-label="Showcase sections">
            <a :for={{number, id, title} <- @sections} href={"##{id}"}>
              {number} <span>{title}</span>
            </a>
          </nav>
          <p class="sc-note">One library.<br />Four identities.</p>
        </aside>
        <main class="sc-main">
          <S.row rail={false} class="sc-intro">
            <p class="sc-eyebrow rg-support-band">The working collection</p>
            <h1>
              Shared foundations.<br />
              <span>Room to explore.</span>
            </h1>
          </S.row>
          <.palette_controls />
          <.foundations result={@result} />
          <.capabilities cards={@capabilities} />
          <.feedback
            empty_items={@empty_items}
            empty_error={@empty_error}
            fixture_wallets={@fixture_wallets}
            balance={@balance}
            fail_reads={@fail_reads}
          />
          <.composition
            step_title={@step_title}
            step_editing={@step_editing}
            step_form={@step_form}
            step_errors={@step_errors}
          />
          <.identity
            privy_mode={@privy_mode}
            account_control={@account_control}
            identities={@identities}
            connection_notice={@connection_notice}
          />
          <.data form={@form} errors={@errors} records={@records} result={@result} local?={@local?} />
          <.inventory catalog={@catalog} />
          <footer class="sc-footer">
            <span>Ash / Component workshop</span>
            <a href="#showcase">Back to top ↑</a>
          </footer>
        </main>
      </div>
    </S.frame>
    """
  end

  defp palette_controls(assigns) do
    ~H"""
    <section
      id="palette-controls"
      class="sc-palette"
      phx-update="ignore"
      aria-label="Palette controls"
    >
      <div class="sc-row sc-between">
        <div class="sc-segment" aria-label="Site palette">
          <button
            :for={{key, label} <- brands()}
            type="button"
            data-sc-brand={key}
            aria-pressed={to_string(key == "platform")}
          >{label}</button>
        </div>
        <div class="sc-segment" aria-label="Color mode">
          <button type="button" data-sc-mode="light" aria-pressed="false">Light</button>
          <button type="button" data-sc-mode="dark" aria-pressed="true">Dark</button>
        </div>
      </div>
      <div class="sc-theme-options" role="group" aria-label="Site themes">
        <button
          :for={
            {key, label, mode} <-
              for {key, label} <- brands(),
                  mode <- ~w(light dark),
                  do: {key, label, mode}
          }
          type="button"
          data-sc-theme={key <> ":" <> mode}
          aria-pressed={to_string(key == "platform" and mode == "dark")}
        >
          <span class="sc-theme-sample" aria-hidden="true">
            <span>Aa</span>
            <i></i>
          </span>
          <span>{label} <small>{mode}</small></span>
        </button>
      </div>
      <div class="sc-swatches">
        <label :for={
          {key, name} <- [
            {"bg", "Background"},
            {"surface", "Surface"},
            {"fg", "Text"},
            {"accent", "Primary"}
          ]
        }>
          <input type="color" data-sc-color={key} aria-label={name <> " color"} value="#202020" />
          <span>{name}</span>
          <output data-sc-value={key}></output>
        </label>
      </div>
      <div class="sc-row sc-between">
        <button type="button" data-sc-reset class="sc-text-button">Reset this palette</button>
        <output data-sc-contrast class="sc-mono" aria-live="polite"></output>
      </div>
      <div class="sc-row sc-shimmer-control">
        <label for="shimmer-color">Shimmer color</label>
        <input id="shimmer-color" type="color" data-sc-shimmer-color value="#FF5B19" />
        <output data-sc-shimmer-value>Automatic</output>
        <button type="button" data-sc-shimmer-reset class="sc-text-button">Use automatic color</button>
      </div>
      <.disclosure id="palette-notes" summary="Palette details">
        <p>
          Colors come from Regent's shared design kit. Platform uses charcoal, Autolaunch tangerine, Patchbay platinum and Techtree powder blue. Changes you make here stay in this browser. Changes to the shared kit reach each site the next time it is built.
        </p>
        <dl class="sc-token-list" data-sc-tokens></dl>
      </.disclosure>
    </section>
    """
  end

  attr :result, :map, default: nil

  defp foundations(assigns) do
    ~H"""
    <.section id="foundations" detail="The small pieces.">
      <div class="sc-grid">
        <.card>
          <h3>Buttons</h3>
          <div class="sc-row">
            <P.button phx-click="example_action">Primary</P.button>
            <P.button variant="secondary" phx-click="example_action">Secondary</P.button>
            <P.button variant="quiet" phx-click="example_action">Quiet</P.button>
            <P.button disabled>Disabled</P.button>
          </div>
          <p :if={@result && @result[:example]} role="status">{@result.example}</p>
          <.api module="Regent.Primitives" function="button" />
        </.card>
        <.card>
          <h3>Typography</h3>
          <S.technical_figure class="rg-support-figure">
            <p class="sc-type-display">Aa / 0123</p>
            <:caption>Pixel Square / regular 400</:caption>
          </S.technical_figure>
          <p>Geist Sans · body copy and interface.</p>
          <code>0x71C7..976F</code>
          <.disclosure id="type-tokens" summary="Type and spacing">
            <p>
              Titles and subtitles: Geist Pixel Square, weight 400. Body text and controls: Geist Sans. Addresses and code: Geist Mono. Space: 8 / 16 / 24 / 32 / 40 / 48 / 64 px.
            </p>
          </.disclosure>
        </.card>
        <.card>
          <h3>Fields</h3>
          <P.field :let={field} id="preview-email" label="Email">
            <input
              id={field.id}
              type="email"
              placeholder="you@example.com"
              aria-describedby={field.described_by}
            />
            <:hint>Optional contact address.</:hint>
          </P.field>
          <P.field :let={field} id="preview-network" label="Network">
            <select id={field.id}>
              <option>Base</option>
              <option>Ethereum</option>
            </select>
          </P.field>
          <P.field :let={field} id="preview-invalid" label="Required name" errors={["Enter a name."]}>
            <input
              id={field.id}
              aria-invalid={field.aria_invalid}
              aria-describedby={field.described_by}
            />
          </P.field>
          <.api module="Regent.Primitives" function="field" />
        </.card>
        <.card>
          <h3>Disclosure</h3>
          <.disclosure id="disclosure-example" summary="What is shared?">
            <p>
              The shared pieces decide how things look. Each site decides what they do and who can use them.
            </p>
          </.disclosure>
          <.disclosure id="disclosure-open" summary="Open by default" open>
            <p>
              A closed section still holds its text, so search and screen readers can find it.
            </p>
          </.disclosure>
          <.api module="Regent.Primitives" function="disclosure" />
        </.card>
      </div>
    </.section>
    """
  end

  attr :cards, :list, required: true

  defp capabilities(assigns) do
    ~H"""
    <.section id="capabilities" detail="One card. Your images and words.">
      <div class="rg-feature-grid">
        <S.capability_card
          :for={card <- @cards}
          id={"capability-#{card.index}"}
          title={card.title}
          description={card.description}
          index={card.index}
          tone={card.tone}
          image_src={card.image}
          image_alt="Placeholder mark"
        >
          <:media>
            <svg
              :if={!card.image}
              viewBox="0 0 240 240"
              fill="none"
              stroke="currentColor"
              stroke-width="1.2"
              aria-hidden="true"
            >
              <path d="M12 24V12H24 M216 12H228V24 M228 216V228H216 M24 228H12V216" />
              <circle
                :for={r <- [80, 62, 44, 26]}
                :if={card.kind == :circles}
                cx="120"
                cy={190 - r}
                r={r}
              />
              <path
                :for={y <- [36, 60, 84, 108, 132, 156]}
                :if={card.kind == :triangle}
                d={"M120 #{y}L40 194H200Z M120 #{y}V194"}
              />
            </svg>
          </:media>
          <:actions>
            <a href={card.href} class="rg-button rg-button--quiet">{card.action} ↗</a>
          </:actions>
        </S.capability_card>
      </div>
      <p class="sc-note">
        Hover or focus a card for the slower sweep. The color control above applies to cards and primary buttons.
      </p>
      <.api module="Regent.Structure" function="capability_card" />
    </.section>
    """
  end

  attr :empty_items, :list, required: true
  attr :empty_error, :string, default: nil
  attr :fixture_wallets, :list, required: true
  attr :balance, Read, required: true
  attr :fail_reads, :boolean, required: true

  defp feedback(assigns) do
    ~H"""
    <.section id="feedback" detail="A state worth showing.">
      <div class="sc-grid">
        <.card>
          <h3>Status</h3>
          <div class="sc-row">
            <P.status :for={tone <- ~w(neutral info success warning error)} tone={tone}>
              {String.capitalize(tone)}
            </P.status>
          </div>
          <.api module="Regent.Primitives" function="status" />
          <h3>Notices</h3>
          <P.notice
            :for={
              {tone, text} <- [
                {"info", "Ready for the next step."},
                {"success", "Saved successfully."},
                {"warning", "Review the current network."},
                {"error", "The wallet rejected this request."}
              ]
            }
            tone={tone}
          >
            {text}
          </P.notice>
          <.api module="Regent.Primitives" function="notice" />
        </.card>
        <.card id="empty-state-demo">
          <h3>Empty states</h3>
          <div aria-live="polite">
            <P.empty_state :if={@empty_items == []} title="Nothing here yet.">
              Your first item will appear here.
            </P.empty_state>
            <ul :if={@empty_items != []} id="empty-state-items">
              <li :for={item <- @empty_items}>{item.title}</li>
            </ul>
            <P.notice :if={@empty_error} tone="error">{@empty_error}</P.notice>
          </div>
          <div class="sc-row">
            <P.button id="add-item" phx-click="create_item" variant="secondary">
              {if @empty_items == [], do: "Create item", else: "Add item"}
            </P.button>
            <P.button :if={@empty_items != []} phx-click="reset_items" variant="quiet">
              Reset items
            </P.button>
          </div>
          <p>Items live only on this page. Reloading clears them.</p>
          <.api module="Regent.Primitives" function="empty_state" />
        </.card>
        <.card id="slow-read-demo">
          <h3>Slow reads <small>Practice</small></h3>
          <div class="rg-field">
            <div class="sc-segment" aria-label="Wallet to read">
              <button
                :for={{key, wallet} <- @fixture_wallets}
                id={"slow-read-#{key}"}
                type="button"
                phx-click="read_wallet"
                phx-value-wallet={key}
                aria-pressed={to_string(@balance.owner == key)}
              >
                {wallet.label}
              </button>
            </div>
            <label class="sc-row">
              <input
                id="slow-read-fail"
                type="checkbox"
                phx-click="toggle_read_failure"
                checked={@fail_reads}
              /> Make the next reads fail
            </label>
            <div id="slow-read-result" aria-live="polite">
              <P.status tone={read_tone(@balance.state)}>{read_label(@balance)}</P.status>
              <dl :if={@balance.value not in [nil, []]} class="sc-facts">
                <%= for {token, amount} <- @balance.value do %>
                  <dt>{token}</dt>
                  <dd>{amount}</dd>
                <% end %>
              </dl>
              <P.empty_state :if={@balance.value == []} title="Nothing in this wallet yet.">
                A reading that found nothing, not a failed one.
              </P.empty_state>
              <P.notice :if={@balance.state == :stale} tone="warning">
                Couldn’t refresh. Showing the reading from {read_time(@balance.read_at)}.
              </P.notice>
              <P.notice :if={@balance.state == :error} tone="error">
                Couldn’t read this wallet. No balance is shown until a read works.
              </P.notice>
            </div>
          </div>
          <div class="sc-row">
            <P.button
              :if={@balance.owner}
              id="slow-read-refresh"
              variant="secondary"
              phx-click="read_wallet"
              phx-value-wallet={@balance.owner}
            >Refresh</P.button>
            <P.button
              :if={@balance.owner}
              id="slow-read-disconnect"
              variant="quiet"
              phx-click="forget_wallet"
            >Disconnect</P.button>
          </div>
          <.disclosure id="slow-read-notes" summary="What to try">
            <p>
              Choose the slow wallet, then another before it answers: the slow answer is thrown away and never replaces the wallet you chose. Disconnect does the same. Tick the failure box and refresh to keep the last reading marked as old; choose a new wallet with it ticked to see a failed read shown as a failure, never as zero.
            </p>
          </.disclosure>
        </.card>
      </div>
    </.section>
    """
  end

  attr :step_title, :string, required: true
  attr :step_editing, :boolean, required: true
  attr :step_form, Phoenix.HTML.Form, required: true
  attr :step_errors, :list, required: true

  defp composition(assigns) do
    ~H"""
    <.section id="composition" detail="Pieces working together.">
      <div class="sc-grid">
        <S.panel id="showcase-step" tone="accent">
          <div class="rg-panel__heading">
            <h3>{@step_title}</h3>
            <span class="rg-panel__index">Step</span>
          </div>
          <.form :if={@step_editing} for={@step_form} id="step-form" phx-submit="save_step">
            <P.field :let={field} id="step-title" label="Step title" errors={@step_errors}>
              <input
                id={field.id}
                name="step[title]"
                value={@step_form[:title].value}
                aria-invalid={field.aria_invalid}
                aria-describedby={field.described_by}
                phx-mounted={JS.focus()}
                required
                maxlength="80"
              />
            </P.field>
            <div class="sc-row">
              <P.button type="submit">Save title</P.button>
              <P.button variant="quiet" phx-click="cancel_step">Cancel</P.button>
            </div>
          </.form>
          <div :if={!@step_editing} class="sc-row">
            <P.status tone="success">Ready</P.status>
            <P.button variant="quiet" phx-click="edit_step">Edit</P.button>
          </div>
          <p>Edits stay on this page.</p>
        </S.panel>
        <S.panel id="showcase-facts">
          <div class="rg-panel__heading">
            <h3>Activity</h3>
            <span class="rg-panel__index">Facts</span>
          </div>
          <dl id="showcase-facts-content" class="sc-facts">
            <dt>Network</dt>
            <dd>Base</dd>
            <dt>State</dt>
            <dd>Confirmed</dd>
          </dl>
          <div class="sc-row">
            <P.copy_button id="showcase-facts-copy" variant="quiet" text={facts_text()}>
              Copy
            </P.copy_button>
          </div>
          <p>Each site fills these in from its own records.</p>
        </S.panel>
      </div>
      <.disclosure id="shell-detail" summary="Page frame and theme switch">
        <iframe id="shell-preview" title="Page frame preview" src="/showcase/preview" loading="lazy"></iframe>
        <p>
          This preview shows the frame around every signed-in page: the menu, the account button and the light and dark switch.
        </p>
      </.disclosure>
    </.section>
    """
  end

  attr :privy_mode, :atom, required: true
  attr :account_control, :map, required: true
  attr :identities, :list, required: true
  attr :connection_notice, :map, default: nil

  defp identity(assigns) do
    ~H"""
    <.section id="identity" detail="See each request through.">
      <div class="sc-grid">
        <.card>
          <h3>Wallet steps <small>Practice</small></h3>
          <div id="wallet-fixture" class="rg-field" phx-hook="ShowcaseWallet" phx-update="ignore">
            <div class="sc-row">
              <P.button data-demo-connect>Connect practice wallet</P.button>
              <P.button variant="quiet" data-demo-disconnect>Disconnect</P.button>
            </div>
            <p data-demo-wallet role="status">Disconnected</p>
            <label for="fixture-outcome">Next outcome</label>
            <select id="fixture-outcome" data-demo-outcome>
              <option value="confirmed">Confirmed</option>
              <option value="rejected">Declined in the wallet</option>
              <option value="reverted">Turned down by the network</option>
            </select>
            <P.button data-demo-send>Send practice transaction</P.button>
            <ol data-demo-results aria-live="polite"></ol>
          </div>
          <.disclosure id="wallet-contract" summary="How the practice wallet works">
            <p>
              These practice pieces never touch a real wallet or network. Each press starts its own request, even while an earlier one is still waiting. Disconnect here only affects the practice wallet.
            </p>
          </.disclosure>
        </.card>
        <.card>
          <h3>Privy <small>Real sign-in</small></h3>
          <div data-sc-privy-mode={@privy_mode}>
            <div id="account-control" class="sc-row">
              <P.button
                :if={@privy_mode == :configured && @account_control.kind == :sign_in}
                data-account-target="sign-in"
              >Sign in with Privy</P.button>
              <P.button
                :if={@privy_mode == :configured && @account_control.kind == :signed_in}
                variant="secondary"
                data-account-target="sign-out"
              >Sign out</P.button>
              <P.button :if={@privy_mode != :configured} disabled aria-describedby="privy-unavailable">Sign in with Privy</P.button>
            </div>
            <p :if={@privy_mode == :configured && @account_control.kind == :signed_in}>
              Signed in as {@account_control.label}.
            </p>
            <p :if={@privy_mode == :unconfigured} id="privy-unavailable">
              Sign-in isn't available on this copy of the site.
            </p>
          </div>
          <p id="account-auth-status" role="status" phx-update="ignore" hidden></p>
          <.disclosure id="privy-scope" summary="Uses your real account">
            <p>
              These buttons use this site's real sign-in. You only see the button that
              fits where you are now. Signing in may open Privy. Signing out ends your
              visit on this site. The practice wallet is separate.
            </p>
          </.disclosure>
          <h3>Product pages</h3>
          <div class="sc-row">
            <a href="/app">Overview ↗</a>
            <a href="/account">Account ↗</a>
          </div>
          <.disclosure id="real-actions" summary="What real actions need">
            <p>
              These pages use real sign-in and check your wallet. Anything sent from your wallet asks you to approve it there first. This page never sends anything for you.
            </p>
          </.disclosure>
        </.card>
      </div>
      <.disclosure id="connections-detail" summary="Linked accounts · practice">
        <AshTemplateWeb.Components.VerifiedConnections.verified_connections
          id="showcase-connections"
          identities={@identities}
          authenticated
          notice={@connection_notice}
          description="Practice only. Nothing is linked for real."
        />
      </.disclosure>
    </.section>
    """
  end

  attr :form, Phoenix.HTML.Form, required: true
  attr :errors, :list, required: true
  attr :records, :list, required: true
  attr :result, :map, default: nil
  attr :local?, :boolean, required: true

  defp data(assigns) do
    ~H"""
    <.section id="data" detail="Real checks. Safe limits.">
      <div class="sc-grid">
        <.card>
          <h3>Ash form <small>This page only</small></h3>
          <.form for={@form} id="sample-form" phx-submit="create_sample">
            <P.field :let={field} id="sample-title" label="Title" errors={@errors}>
              <input
                id={field.id}
                name="sample[title]"
                value={@form[:title].value}
                aria-invalid={field.aria_invalid}
                aria-describedby={field.described_by}
              />
            </P.field>
            <P.field :let={field} id="sample-quantity" label="Quantity">
              <input
                id={field.id}
                name="sample[quantity]"
                type="number"
                value={@form[:quantity].value}
              />
            </P.field>
            <P.button type="submit">Add item</P.button>
          </.form>
          <ul id="sample-records">
            <li :for={record <- @records}>{record.title} × {record.quantity}</li>
          </ul>
          <.disclosure id="ash-demo-notes" summary="Rules for this form">
            <p>
              Built with Ash. The title needs 2 to 80 characters and the quantity must be from 1 to 100. Items live only on this page and are never saved.
            </p>
          </.disclosure>
        </.card>
        <.card>
          <h3>Sign-in check <small>Practice</small></h3>
          <form id="utility-form" class="rg-field" phx-submit="run_utility">
            <label for="utility-kind">Example</label>
            <select id="utility-kind" name="kind">
              <option value="privy_valid">Valid practice sign-in</option>
              <option value="privy_expired">Expired practice sign-in</option>
              <option value="privy_audience">Practice sign-in for another app</option>
            </select>
            <P.button type="submit">Check</P.button>
          </form>
          <pre id="utility-result" role="status">{utility_output(@result)}</pre>
          <P.copy_button
            :if={utility_output(@result)}
            id="utility-result-copy"
            variant="quiet"
            target="utility-result"
          >
            Copy result
          </P.copy_button>
          <.disclosure id="utility-notes" summary="What this checks">
            <p>
              Each example makes a practice sign-in and runs it through the same check the real site uses: one valid, one expired and one made for a different app. Practice sign-ins never sign anyone in, and they never touch a real wallet or network.
            </p>
          </.disclosure>
        </.card>
        <.card :if={@local?}>
          <h3>Postgres <small>Read only</small></h3>
          <P.button variant="secondary" phx-click="database">Check the database</P.button>
          <.disclosure id="database-notes" summary="Diagnostic boundary">
            <p>
              Runs SELECT current_database(), 1 only against this worktree's prepared loopback test database. Other database configurations are refused. No arbitrary query, fixture writes, schema changes or resets.
            </p>
          </.disclosure>
        </.card>
      </div>
    </.section>
    """
  end

  attr :catalog, :map, required: true

  defp inventory(assigns) do
    ~H"""
    <.section id="inventory" detail="Every piece in the kit, folded away.">
      <p class="sc-note">
        {length(@catalog.components)} components · {length(@catalog.domains)} Ash data groups
      </p>
      <.disclosure id="component-inventory" summary="Design components">
        <div :for={item <- @catalog.components} class="sc-inventory-row">
          <code>{item.module}.{item.function}/1</code>
          <small>Settings: {Enum.join(
            item.attributes,
            ", "
          )} · Parts: {Enum.join(item.slots, ", ")}</small>
        </div>
      </.disclosure>
      <.disclosure
        :for={{domain, index} <- Enum.with_index(@catalog.domains)}
        id={"domain-#{index}"}
        summary={domain.name}
      >
        <div :for={resource <- domain.resources} class="sc-inventory-row">
          <code>{resource.name}</code>
          <p>
            What it can do: {Enum.map_join(resource.actions, ", ", &"#{&1.name} (#{&1.type})")}
          </p>
          <small>Fields: {Enum.map_join(
            resource.attributes,
            ", ",
            &"#{&1.name}#{if &1.public, do: "", else: " (private)"}"
          )}</small>
        </div>
      </.disclosure>
      <.disclosure id="utility-inventory" summary={"Shared tools · #{length(@catalog.utilities)}"}>
        <div :for={item <- @catalog.utilities} class="sc-inventory-row">
          <code>{item.name}</code>
          <small>{item.owner}</small>
          <p>{Enum.join(item.functions, " · ")}</p>
        </div>
      </.disclosure>
      <.disclosure id="coverage-scope" summary="What this list covers">
        <p>
          This list covers every shared design component and the ones this site adds. Product pages are built from these pieces and keep their own behavior. The Ash groups show how the data is shaped, never the data itself. The shared tools are the libraries every site uses, plus this site's database settings.
        </p>
      </.disclosure>
    </.section>
    """
  end

  defp brands,
    do: [
      {"platform", "Platform"},
      {"autolaunch", "Autolaunch"},
      {"patchbay", "Patchbay"},
      {"techtree", "Techtree"}
    ]

  defp facts_text, do: "Network: Base\nState: Confirmed"

  defp utility_output(nil), do: nil
  defp utility_output(%{example: _example}), do: nil
  defp utility_output(%{check: text}), do: text

  attr :id, :string, required: true
  attr :detail, :string, required: true
  slot :inner_block, required: true

  defp section(assigns) do
    {number, _id, title} = List.keyfind(@sections, assigns.id, 1)
    assigns = assign(assigns, number: number, title: title)

    ~H"""
    <section id={@id} class="sc-section">
      <S.section_bar class="sc-heading">
        <span>{@number}</span>
        <h2 class="rg-section-bar__label">{@title}</h2>
        <p>{@detail}</p>
      </S.section_bar>
      {render_slot(@inner_block)}
    </section>
    """
  end

  attr :id, :string, default: nil
  slot :inner_block, required: true

  defp card(assigns) do
    ~H"""
    <div class="sc-example rg-feature">
      <S.panel id={@id} class="sc-card">{render_slot(@inner_block)}</S.panel>
    </div>
    """
  end

  attr :module, :string, required: true
  attr :function, :string, required: true

  defp api(assigns) do
    ~H"""
    <details class="sc-api-note">
      <summary>Code <span aria-hidden="true">›</span></summary>
      <code>{@module}.{@function}/1</code>
    </details>
    """
  end

  attr :id, :string, required: true
  attr :summary, :string, required: true
  attr :open, :boolean, default: false
  slot :inner_block, required: true

  # A disclosure the reader opens or closes; no later update from the server reverts it.
  defp disclosure(assigns) do
    ~H"""
    <P.disclosure phx-mounted={JS.ignore_attributes("open")} id={@id} summary={@summary} open={@open}>
      {render_slot(@inner_block)}
    </P.disclosure>
    """
  end

  def handle_event("create_sample", %{"sample" => params}, socket) do
    form = to_form(params, as: :sample)

    case Ash.create(Sample, params) do
      {:ok, record} ->
        {:noreply,
         assign(socket, records: [record | socket.assigns.records], errors: [], form: form)}

      {:error, error} ->
        {:noreply, assign(socket, errors: [Exception.message(error)], form: form)}
    end
  end

  def handle_event("create_item", _, socket) do
    items = socket.assigns.empty_items

    case Ash.create(Sample, %{title: "Workshop item #{length(items) + 1}", quantity: 1}) do
      {:ok, item} -> {:noreply, assign(socket, empty_items: items ++ [item], empty_error: nil)}
      {:error, error} -> {:noreply, assign(socket, :empty_error, Exception.message(error))}
    end
  end

  def handle_event("read_wallet", %{"wallet" => key}, socket) do
    fail? = socket.assigns.fail_reads

    case List.keyfind(@fixture_wallets, key, 0) do
      {^key, wallet} ->
        {:noreply,
         Read.start(socket, :balance, key, fn -> read_fixture_wallet(wallet, fail?) end)}

      nil ->
        {:noreply, socket}
    end
  end

  def handle_event("forget_wallet", _, socket), do: {:noreply, Read.clear(socket, :balance)}

  def handle_event("toggle_read_failure", _, socket),
    do: {:noreply, update(socket, :fail_reads, &(!&1))}

  def handle_event("reset_items", _, socket),
    do: {:noreply, assign(socket, empty_items: [], empty_error: nil)}

  def handle_event("edit_step", _, socket) do
    step_form = to_form(%{"title" => socket.assigns.step_title}, as: :step)
    {:noreply, assign(socket, step_editing: true, step_errors: [], step_form: step_form)}
  end

  def handle_event("cancel_step", _, socket),
    do: {:noreply, assign(socket, step_editing: false, step_errors: [])}

  def handle_event("save_step", %{"step" => params}, socket) do
    # Reuse the local sample action's title validation, never a product resource.
    case Ash.create(Sample, Map.take(params, ["title"])) do
      {:ok, item} ->
        {:noreply, assign(socket, step_title: item.title, step_editing: false, step_errors: [])}

      {:error, error} ->
        {:noreply,
         assign(socket,
           step_errors: [Exception.message(error)],
           step_form: to_form(params, as: :step)
         )}
    end
  end

  def handle_event("run_utility", params, socket),
    do: {:noreply, assign(socket, :result, %{check: run_utility(params["kind"])})}

  def handle_event("database", _, socket),
    do: {:noreply, assign(socket, :result, %{check: Utilities.database()})}

  def handle_event("example_action", _, socket),
    do: {:noreply, assign(socket, :result, %{example: "Action received."})}

  def handle_event(
        "request_verified_connection",
        %{"provider" => provider, "action" => action},
        socket
      ) do
    provider = @providers[provider]
    others = Enum.reject(socket.assigns.identities, &(&1.provider == provider))

    identities =
      if action == "link" and not is_nil(provider),
        do: [
          %{provider: provider, username: "workshop", display_name: "Workshop sample"} | others
        ],
        else: others

    {:noreply,
     assign(socket,
       identities: identities,
       connection_notice: %{
         tone: :info,
         message: "Practice list updated. Nothing was linked for real."
       }
     )}
  end

  def handle_async({Read, _name, _generation} = name, result, socket),
    do: {:noreply, Read.settle(socket, name, result)}

  defp read_fixture_wallet(wallet, fail?) do
    Process.sleep(wallet.delay)
    if fail?, do: {:error, :unreachable}, else: {:ok, wallet.holdings}
  end

  defp read_tone(:ready), do: "success"
  defp read_tone(:empty), do: "neutral"
  defp read_tone(:stale), do: "warning"
  defp read_tone(:error), do: "error"
  defp read_tone(_reading), do: "info"

  defp read_label(%Read{state: :idle}), do: "Choose a wallet"
  defp read_label(%Read{state: :loading, value: nil}), do: "Reading…"
  defp read_label(%Read{state: :loading}), do: "Refreshing…"
  defp read_label(%Read{state: :stale}), do: "Old reading"
  defp read_label(%Read{state: :error}), do: "Read failed"

  defp read_label(%Read{state: state, read_at: read_at}) when state in [:ready, :empty],
    do: "Read at #{read_time(read_at)}"

  defp read_time(read_at), do: Calendar.strftime(read_at, "%H:%M:%S UTC")

  @doc "Configuration status for local reference pages; never returns configuration values."
  def privy_mode do
    config = Application.get_env(:ash_template, :privy, [])

    if Enum.all?([:app_id, :verification_key], &present?(config[&1])),
      do: :configured,
      else: :unconfigured
  end

  defp present?(value), do: is_binary(value) and String.trim(value) != ""

  defp run_utility("privy_valid"), do: Utilities.privy(:valid)
  defp run_utility("privy_expired"), do: Utilities.privy(:expired)
  defp run_utility("privy_audience"), do: Utilities.privy(:audience)
  defp run_utility(_kind), do: "Choose one of the listed examples."
end
