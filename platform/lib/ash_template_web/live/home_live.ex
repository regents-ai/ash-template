defmodule AshTemplateWeb.HomeLive do
  use AshTemplateWeb, :live_view

  alias AshTemplateWeb.Components.RegentLinks
  alias AshTemplateWeb.{Motion, PublicDocuments, RouteCatalog, Showcase}

  @doc "A public text representation using the same copy as the page."
  def agent_markdown do
    chapters =
      Enum.map_join(chapters(), "\n\n", fn chapter ->
        proofs =
          Enum.map_join(chapter.proofs, "\n", fn {title, copy} -> "- **#{title}** #{copy}" end)

        Enum.join(["## #{chapter.title}", chapter.description, proofs], "\n\n")
      end)

    """
    # Ash Template

    A starting point for a product with wallet sign-in, an account page and a documented API.

    #{chapters}

    ## Get started

    [Open the app](#{PublicDocuments.url("/app")}) · [Developer documentation](#{PublicDocuments.url("/docs")}) · [Agent guide](#{PublicDocuments.url("/llms.txt")})
    #{kit_markdown(Showcase.linked?())}[About](#{PublicDocuments.url("/about")}) · [Contact](#{PublicDocuments.url("/contact")}) · [Privacy](#{PublicDocuments.url("/privacy")})
    """
  end

  defp kit_markdown(false), do: ""

  defp kit_markdown(true) do
    "[Showcase](#{PublicDocuments.url("/showcase")}) · [Motion lab](#{PublicDocuments.url("/animations")}) · " <>
      "[Build skills](#{PublicDocuments.url("/skills")})\n"
  end

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(PublicDocuments.page("/"))
     |> assign(route_spec: RouteCatalog.fetch!(:home), showcase?: Showcase.linked?())}
  end

  def render(assigns) do
    ~H"""
    <Regent.Structure.frame id="public-home" class="rl-root">
      <Regent.Structure.row rail={false}><.landing_header /></Regent.Structure.row>

      <main>
        <Regent.Structure.row rail={false}><.hero /></Regent.Structure.row>

        <%= for chapter <- chapters() do %>
          <Regent.Structure.row rail={false}><.chapter chapter={chapter} /></Regent.Structure.row>
        <% end %>

        <Regent.Structure.row rail={false}>
          <.closing_frame showcase?={@showcase?} />
        </Regent.Structure.row>
      </main>

      <Regent.Structure.row rail={false}><.landing_footer /></Regent.Structure.row>
    </Regent.Structure.frame>
    """
  end

  # The homepage is always dark, so its mark is the dark one.
  defp landing_header(assigns) do
    ~H"""
    <header class="rl-header" data-home-header>
      <div class="rl-header-bar">
        <.link navigate={~p"/"} class="rl-brand" aria-label="Ash Template home">
          <img
            src={~p"/images/brand/mark-flat-dark.svg"}
            width="252"
            height="186"
            alt=""
          />
        </.link>

        <nav class="rl-product-tabs" aria-label="Homepage sections">
          <a
            :for={{label, anchor} <- nav_links()}
            id={"home-nav-#{anchor}"}
            href={"##{anchor}"}
            class="rg-button rl-product-tab"
          >
            {label}
          </a>
        </nav>

        <div class="rl-header-links">
          <RegentLinks.header_links id="home-brand-links" />
          <.action href={~p"/app"} class="rl-action">App</.action>
        </div>
      </div>
    </header>
    """
  end

  defp hero(assigns) do
    ~H"""
    <section class="rl-hero rl-hero--home" aria-labelledby="home-title">
      <div class="rl-hero-stage">
        <%!-- Placeholder art: replace this image with the product's own. --%>
        <div id="home-hero-art" class="rl-hero-media" aria-hidden="true">
          <img
            class="rl-hero-art"
            src={~p"/images/home/hero-bg-dark.svg"}
            width="1700"
            height="1200"
            alt=""
            fetchpriority="high"
          />
        </div>

        <div class="rl-hero-copy" data-home-hero-copy>
          <h1 id="home-title" class="rl-hero-title">Ash Template</h1>
          <p class="rl-hero-description">A starting point for your next product</p>
          <div class="rl-hero-actions">
            <.action href={~p"/app"}>Open the app</.action>
          </div>
        </div>
        <div class="rl-hero-products">
          <ul
            id="home-highlights"
            class="rl-hero-cards"
            role="list"
            data-home-hero-cards
            aria-label="Highlights"
          >
            <li
              :for={card <- chapters()}
              id={"home-card-#{card.anchor}"}
              class="rl-hero-card"
              data-home-hero-card={card.anchor}
            >
              <div class="rl-card-heading">
                <h2>{card.eyebrow}</h2>
              </div>
              <p>{card.line}</p>
              <div class="rl-card-actions">
                <.action href={card.href} class="rg-button--secondary rl-action">{card.cta}</.action>
              </div>
            </li>
          </ul>
        </div>
      </div>
    </section>
    """
  end

  # A chapter carries one numbered part of the story.
  defp chapter(assigns) do
    ~H"""
    <section
      id={@chapter.anchor}
      class={["rl-chapter", "rl-chapter--#{@chapter.anchor}"]}
      aria-labelledby={"#{@chapter.anchor}-title"}
    >
      <header class="rl-chapter-intro">
        <p class="rl-chapter-index" aria-hidden="true">{@chapter.index}</p>
        <div>
          <p class="rl-overline">{@chapter.eyebrow}</p>
          <h2 id={"#{@chapter.anchor}-title"}>{@chapter.title}</h2>
          <p>{@chapter.description}</p>

          <div class="rl-chapter-actions">
            <.action href={@chapter.href} class="rg-button--secondary rl-action">
              {@chapter.cta}
            </.action>
          </div>
        </div>
      </header>

      <.proof_grid proofs={@chapter.proofs} brand={@chapter.anchor} offset={@chapter.diagrams} />
    </section>
    """
  end

  defp proof_grid(assigns) do
    ~H"""
    <div
      :if={@proofs != []}
      id={"home-proofs-#{@brand}"}
      class="rl-proof-grid rg-feature-grid"
      phx-hook="MotionCascade"
      data-variant={Motion.standard("grid")}
    >
      <Regent.Structure.capability_card
        :for={{{title, copy}, index} <- Enum.with_index(@proofs)}
        title={title}
        description={copy}
        id={"home-proof-#{@brand}-#{index}"}
        class="rl-proof-card"
        data-card-color={Enum.at(~w(orange blue platinum), index)}
        phx-hook="HolographicCard"
        data-holo-crown="false"
        data-holo-ink
        data-holo-tilt="0"
      >
        <:media>
          <Regent.HolographicCard.foil
            id={"home-proof-foil-#{@brand}-#{index}"}
            class="rg-holo-foil--ink"
          />
          <.card_diagram id={"home-diagram-#{@brand}-#{index}"} variant={@offset + index} />
        </:media>
      </Regent.Structure.capability_card>
    </div>
    """
  end

  attr :id, :string, required: true
  attr :variant, :integer, required: true

  # Static line diagrams: registration marks and sparse geometry, not charts.
  defp card_diagram(assigns) do
    ~H"""
    <svg
      id={@id}
      class="rl-card-diagram"
      data-diagram={@variant}
      viewBox="0 0 320 320"
      fill="none"
      stroke="currentColor"
      stroke-width="1.2"
      aria-hidden="true"
      focusable="false"
    >
      <defs>
        <pattern id={"#{@id}-hatch"} width="7" height="7" patternUnits="userSpaceOnUse">
          <path d="M-2 2L2-2M0 7L7 0M5 9L9 5" stroke-width=".65" />
        </pattern>
      </defs>
      <path d="M8 28V8H28M292 8H312V28M312 292V312H292M28 312H8V292" />
      <g :if={@variant == 0}>
        <path d="M86 50H204L244 90V266H86Z" fill="var(--rg-panel-fill)" />
        <path d="M204 50V90H244M66 72V282H220M108 116H218M108 134H186M108 212H218M108 230H174" />
        <rect x="108" y="158" width="46" height="32" fill={"url(##{@id}-hatch)"} />
        <path d="M176 160H218M176 176H204M176 190H218" />
      </g>
      <g :if={@variant == 1}>
        <path d="M56 70V252M264 70V252M48 90H272M48 136H272M48 182H272M48 228H272" />
        <rect x="82" y="77" width="46" height="26" fill="var(--rg-panel-fill)" />
        <rect x="178" y="123" width="46" height="26" fill="var(--rg-panel-fill)" />
        <rect x="122" y="169" width="46" height="26" fill={"url(##{@id}-hatch)"} />
        <rect x="82" y="215" width="46" height="26" fill="var(--rg-panel-fill)" />
        <path d="M145 158V144M138 151H152" />
      </g>
      <g :if={@variant == 2}>
        <path d="M64 196L160 148L256 196V220L160 268L64 220Z" fill="var(--rg-panel-fill)" />
        <path d="M64 196L160 244L256 196M160 244V268" />
        <path d="M64 148L160 100L256 148V172L160 220L64 172Z" fill="var(--rg-panel-fill)" />
        <path d="M64 148L160 196L256 148M160 196V220" />
        <path d="M64 100L160 52L256 100V124L160 172L64 124Z" fill="var(--rg-panel-fill)" />
        <path d="M64 100L160 148L256 100M160 148V172" />
        <path d="M160 148L256 100V124L160 172Z" fill={"url(##{@id}-hatch)"} />
      </g>
      <g :if={@variant == 3}>
        <rect x="60" y="104" width="156" height="144" fill="var(--rg-panel-fill)" />
        <rect x="82" y="82" width="156" height="144" fill="var(--rg-panel-fill)" />
        <rect x="104" y="60" width="156" height="144" fill="var(--rg-panel-fill)" />
        <path d="M104 96H260M120 78H126M136 78H142M152 78H158M122 122H186M122 138H164" />
        <rect x="202" y="122" width="38" height="60" fill={"url(##{@id}-hatch)"} />
        <path d="M122 178H178V156H190" />
      </g>
      <g :if={@variant == 4}>
        <path d="M60 76H132V244H60M188 76H260V244H188M132 160H188" />
        <path d="M60 100H114M60 124H100M60 148H114M60 172H100M60 196H114M60 220H100M206 100H260M220 124H260M206 148H260M220 172H260M206 196H260M220 220H260" />
        <path d="M160 128L192 160L160 192L128 160Z" fill="var(--rg-panel-fill)" />
        <path d="M160 128L192 160L160 192Z" fill={"url(##{@id}-hatch)"} />
      </g>
      <g :if={@variant == 5}>
        <path d="M160 80V132M80 160H132M188 160H240M160 188V240M90 90L132 132M188 188L230 230" />
        <rect x="132" y="132" width="56" height="56" fill={"url(##{@id}-hatch)"} />
        <rect x="144" y="48" width="32" height="32" /><rect x="48" y="144" width="32" height="32" />
        <rect x="240" y="144" width="32" height="32" /><rect x="144" y="240" width="32" height="32" />
        <path d="M70 70H90V90H70ZM230 230H250V250H230Z" />
      </g>
      <g :if={@variant == 6}>
        <path d="M80 80H120V144H150M80 160H150M80 240H120V176H150M196 160H248" />
        <rect x="48" y="64" width="32" height="32" /><rect x="48" y="144" width="32" height="32" />
        <rect x="48" y="224" width="32" height="32" /><rect
          x="150"
          y="112"
          width="46"
          height="96"
          fill={"url(##{@id}-hatch)"}
        />
        <rect x="248" y="132" width="24" height="56" /><path d="M254 146H266M254 160H266M254 174H266" />
      </g>
      <g :if={@variant == 7}>
        <path d="M112 130H264V246H232V270L208 246H112Z" fill="var(--rg-panel-fill)" />
        <path d="M56 56H224V180H110L80 210V180H56Z" fill="var(--rg-panel-fill)" />
        <path d="M80 88H198M80 108H182M80 128H198M80 148H150M140 208H240M140 224H208" />
        <rect x="236" y="146" width="12" height="36" fill={"url(##{@id}-hatch)"} />
      </g>
      <g :if={@variant == 8}>
        <path d="M126 70H194L242 118V202L194 250H126L78 202V118Z" fill="var(--rg-panel-fill)" />
        <path d="M194 70L242 118V202L194 250V70Z" fill={"url(##{@id}-hatch)"} />
        <path d="M174 114H136V156H174V198H136M155 98V214M48 120V72H96M272 200V248H224M40 80L48 72L56 80M264 240L272 248L280 240" />
      </g>
    </svg>
    """
  end

  attr :showcase?, :boolean, required: true

  defp closing_frame(assigns) do
    ~H"""
    <section id="start" class="rl-closing" aria-labelledby="start-title">
      <p class="rl-overline">Get started</p>
      <h2 id="start-title">Make it yours.</h2>
      <p>
        Rename the product, replace this page, and keep the sign-in, the account page and the
        public documents that already work.
      </p>
      <div class="rl-closing-actions">
        <.action href={~p"/app"} class="rl-action rl-action--strong">Open the app</.action>
        <.action href={~p"/docs"} class="rl-action">Read the docs</.action>
        <.action
          :for={{href, label} <- kit_links()}
          :if={@showcase?}
          href={href}
          class="rg-button--secondary rl-action"
        >
          {label}
        </.action>
      </div>
    </section>
    """
  end

  defp landing_footer(assigns) do
    ~H"""
    <footer class="rl-footer">
      <nav class="rl-document-links" aria-label="Site information">
        <a href={~p"/docs"}>Docs</a>
        <a href={~p"/about"}>About</a>
        <a href={~p"/contact"}>Contact</a>
        <a href={~p"/privacy"}>Privacy</a>
        <a href={~p"/terms"}>Terms</a>
      </nav>
      <nav class="rl-footer-links" aria-label="Social links">
        <RegentLinks.header_links id="footer-brand-links" />
      </nav>
      <p>© 2026 Ash Template</p>
    </footer>
    """
  end

  attr :href, :string, required: true
  attr :class, :string, default: nil
  slot :inner_block, required: true

  # The class list is built here, not in the tag: a literal list there renders a
  # trailing space when `class` is nil.
  defp action(assigns) do
    assigns = assign(assigns, :class, ["rg-button", assigns.class])

    ~H"""
    <a href={@href} class={@class}>
      <span class="rg-button__label">{render_slot(@inner_block)}</span>
    </a>
    """
  end

  defp kit_links,
    do: [
      {~p"/showcase", "See the components"},
      {~p"/animations", "Motion lab"},
      {~p"/skills", "Build skills"}
    ]

  # The three chapters, in page order: each is a hero card, a header tab and a
  # numbered section. `diagrams` is the first of its three card diagrams.
  defp chapters do
    [
      %{
        index: "01",
        anchor: "signin",
        eyebrow: "Sign in",
        line: "One wallet sign-in, with social accounts you can connect afterwards.",
        title: "One sign-in, verified on the server.",
        description:
          "People sign in with a wallet. The server verifies the proof, keeps the session and never trusts the browser's word for who is present.",
        href: "/app",
        cta: "Open the app",
        diagrams: 0,
        proofs: [
          {"Wallet first.", "Sign in with the wallet you already have; no password to keep."},
          {"Connections.", "Connect X, GitHub or Farcaster to the account once signed in."},
          {"Sessions.", "Sign out ends the session on this browser only; nothing else changes."}
        ]
      },
      %{
        index: "02",
        anchor: "account",
        eyebrow: "Account",
        line: "Your wallets, your display name and your connected accounts on one page.",
        title: "Everything the site knows, on one page.",
        description:
          "The account page shows the wallet the sign-in verified, any other linked wallets, the display name and the connected accounts.",
        href: "/account",
        cta: "See your account",
        diagrams: 3,
        proofs: [
          {"Your wallets.", "The primary wallet and every other wallet the sign-in named."},
          {"Your name.", "A display name and a picture generated from the wallet address."},
          {"Your say.",
           "Connect and disconnect accounts; each change is confirmed by the record."}
        ]
      },
      %{
        index: "03",
        anchor: "agents",
        eyebrow: "Agents",
        line: "A documented API, an agent guide and an OpenAPI description from day one.",
        title: "Readable by people and by agents.",
        description:
          "Every public page has a text form, the API is described in OpenAPI, and the agent guide explains how to use both.",
        href: "/docs",
        cta: "Read the docs",
        diagrams: 6,
        proofs: [
          {"Text first.", "Public pages answer in Markdown when an agent asks for it."},
          {"OpenAPI.", "The served API is described at /openapi.json and versioned by header."},
          {"Agent guide.", "/llms.txt says what the site is and where each thing lives."}
        ]
      }
    ]
  end

  # Every tab names a section on this page.
  defp nav_links, do: Enum.map(chapters(), &{&1.eyebrow, &1.anchor}) ++ [{"Start", "start"}]
end
