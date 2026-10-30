defmodule AshTemplateWeb.HomeLive do
  @moduledoc """
  The homepage, which tracks regents.sh's: the five tabs, two columns of panels
  (the hero with the tools button and the world cube on the right; Mission,
  Products, Staking and How it works on the left), in regents.sh's words.
  When regents.sh's homepage changes, this page changes with it
  (`scripts/drift.sh` compares the two). Only the name, the line under it and
  the header's own links are this site's.
  """

  use AshTemplateWeb, :live_view

  alias AshTemplateWeb.Components.{AgentTools, RegentLinks, WorldCube}
  alias AshTemplateWeb.{PublicDocuments, RouteCatalog}

  @name "Ash Template"
  @tagline "A starting point for your next product"

  @staking_summary "Stake $REGENT to share in Regents Labs' USDC revenue, in proportion to how much of all REGENT you stake, plus 20% a year in REGENT, for now."

  # The lab's one plain line under its name, on the page and in the agent copy.
  @mission "We build tools for people and their agents. REGENT stakers share in the revenue."

  @how_it_works [
    %{
      id: "agents",
      variant: 6,
      title: "Agents",
      copy: "One sign-in for your agent on every Regent site.",
      link: "Agent guide",
      href: "/agents.md"
    },
    %{
      id: "tools",
      variant: 0,
      title: "Open tools",
      copy: "WebMCP Tools in the browser. regents-cli on the command line.",
      link: "Developer docs",
      href: "/docs"
    }
  ]

  @doc "A public text representation saying what the page says, in the page's order."
  def agent_markdown do
    products =
      Enum.map_join(products(), "\n", fn product ->
        "- [#{product.name}](#{product.site}) · #{product.action}: #{product.title}"
      end)

    steps =
      Enum.map_join(@how_it_works, "\n", fn step ->
        "- **#{step.title}:** #{step.copy} [#{step.link}](#{PublicDocuments.url(step.href)})"
      end)

    worlds =
      Enum.map_join(worlds(), "\n\n", fn world ->
        cards = Enum.map_join(world.cards, "\n", &card_markdown/1)
        "### #{world.name}\n\n#{world.line}\n\n#{cards}\n\n[Visit #{world.name}](#{world.href})"
      end)

    """
    # #{@name}

    ## #{@tagline}

    [Enter App](#{PublicDocuments.url("/app")}) · [WebMCP Tools](#{PublicDocuments.url("/llms.txt")}) · [Connect your agent from the command line](#{PublicDocuments.url("/agents")})

    #{worlds}

    ## Mission

    ### #{@name}

    #{@mission}

    ## Products

    #{products}

    ## Staking

    Stake $REGENT. Share the lab's revenue. #{@staking_summary} [Stake](https://regents.sh/stake)

    ## How it works

    #{steps}

    ---

    [Buy $REGENT](#{AshTemplateWeb.Layouts.buy_regent()}) · [About](#{PublicDocuments.url("/about")}) · [Developer docs](#{PublicDocuments.url("/docs")}) · [Agent guide](#{PublicDocuments.url("/agents.md")}) · [The whole site in brief](#{PublicDocuments.url("/llms.txt")}) · [Contact](#{PublicDocuments.url("/contact")}) · [Privacy policy](#{PublicDocuments.url("/privacy")}) · [Terms of use](#{PublicDocuments.url("/terms")})
    """
  end

  defp card_markdown(%{label: label, title: title, copy: copy}),
    do: "- **#{label} · #{title}** #{copy}"

  defp card_markdown(%{label: label, copy: copy}),
    do: "- #{label}: #{String.replace(copy, "\n", " ")}"

  defp card_markdown(%{title: title, copy: copy}), do: "- **#{title}** #{copy}"

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(PublicDocuments.page("/"))
     |> assign(route_spec: RouteCatalog.fetch!(:home))}
  end

  def render(assigns) do
    ~H"""
    <Regent.Structure.frame id="public-home" class="rl-root">
      <a class="shell-skip" href="#home-content">Skip to content</a>
      <Regent.Structure.row rail={false}><.landing_header /></Regent.Structure.row>

      <%!-- Two columns of panels. The hero stands top right and stays in view while
           the sheets on the left scroll past it; a phone reads the hero first, then
           the sheets. A sheet below the fold settles in the first time it is seen. --%>
      <main id="home-content">
        <Regent.Structure.row rail={false}>
          <div class="rl-panels">
            <div class="rl-column" data-home-column="hero">
              <Regent.Structure.panel class="rl-panel rl-panel--hero" data-home-panel="hero">
                <.hero />
              </Regent.Structure.panel>
            </div>
            <div class="rl-column" data-home-column="sheets">
              <.mission />
              <.product_panel />
              <.staking />
              <.how_it_works />
            </div>
          </div>
        </Regent.Structure.row>
      </main>

      <Regent.Structure.row rail={false}>
        <AshTemplateWeb.Layouts.product_links theme_toggle={false} />
      </Regent.Structure.row>
    </Regent.Structure.frame>
    """
  end

  # The homepage is always dark, so its mark is the dark one.
  defp landing_header(assigns) do
    ~H"""
    <header class="rl-header" data-home-header>
      <div class="rl-header-bar">
        <.link navigate={~p"/"} class="rl-brand" aria-label="Ash Template home">
          <img src={~p"/images/brand/mark-flat-dark.svg"} width="252" height="186" alt="" />
        </.link>

        <nav class="rl-product-tabs" aria-label="Products and staking">
          <a
            :for={{label, id, href, new_tab?} <- nav_links()}
            id={"home-nav-#{id}"}
            href={href}
            target={new_tab? && "_blank"}
            rel={new_tab? && "noopener noreferrer"}
            class="rg-button rl-product-tab"
            phx-hook="HolographicCard"
            data-holo-crown="false"
            data-holo-shine="0.65"
          >
            <Regent.HolographicCard.foil id={"home-nav-#{id}-foil"} class="rl-product-tab__foil" />
            <span class="rg-button__label">
              {label}<span :if={new_tab?} class="visually-hidden">, opens in a new tab</span>
            </span>
          </a>
        </nav>

        <div class="rl-header-links">
          <RegentLinks.header_links id="home-brand-links" />
          <a href={~p"/app"} class="rg-button rl-action"><span class="rg-button__label">App</span></a>
        </div>
      </div>
    </header>
    """
  end

  defp mission(assigns) do
    assigns = assign(assigns, name: @name, line: @mission)

    ~H"""
    <Regent.Structure.panel
      class="rl-panel rl-panel--mission rg-support-panel"
      id="home-mission"
      data-home-panel="mission"
      phx-hook="MotionCascade"
      data-variant={AshTemplateWeb.Motion.standard("grid")}
      aria-labelledby="home-mission-title"
    >
      <h2 id="home-mission-title" class="rl-eyebrow">Mission</h2>
      <div class="rl-statement">
        <p class="rl-statement__name">{@name}</p>
        <p class="rl-statement__line">{@line}</p>
      </div>
    </Regent.Structure.panel>
    """
  end

  defp product_panel(assigns) do
    assigns = assign(assigns, products: products())

    ~H"""
    <Regent.Structure.panel
      class="rl-panel rl-panel--products"
      id="home-products"
      data-home-panel="products"
      phx-hook="MotionCascade"
      data-variant={AshTemplateWeb.Motion.standard("grid")}
      aria-labelledby="home-products-title"
    >
      <h2 id="home-products-title" class="rl-eyebrow">Products</h2>
      <ul class="rl-product-cards">
        <li
          :for={product <- @products}
          class="rl-product-card"
          data-product={String.downcase(product.name)}
        >
          <span class="rl-product-card__tile">
            <.card_diagram
              id={"home-product-#{String.downcase(product.name)}"}
              variant={product.diagram}
            />
          </span>
          <p class="rl-eyebrow">{product.action}</p>
          <h3 class="rl-product-card__name">{product.name}</h3>
          <p class="rl-mono">{product.title}</p>
          <a
            href={product.site}
            target="_blank"
            rel="noopener noreferrer"
            class="rg-button rg-button--secondary rl-panel-link"
          >
            <span class="rg-button__label">
              {URI.parse(product.site).host}<span class="visually-hidden">, {product.name}, opens in a new tab</span>
            </span>
          </a>
        </li>
      </ul>
    </Regent.Structure.panel>
    """
  end

  defp staking(assigns) do
    assigns = assign(assigns, summary: @staking_summary)

    ~H"""
    <Regent.Structure.panel
      class="rl-panel rl-panel--staking"
      id="home-staking"
      data-home-panel="staking"
      phx-hook="MotionCascade"
      data-variant={AshTemplateWeb.Motion.standard("grid")}
      aria-labelledby="home-staking-title"
    >
      <h2 id="home-staking-title" class="rl-eyebrow">Staking</h2>
      <div class="rl-staking">
        <span class="rl-staking__tile">
          <.card_diagram id="home-staking-diagram" variant={8} />
        </span>
        <p class="rl-staking__line">Stake $REGENT. Share the lab's revenue.</p>
        <p class="rl-mono">{@summary}</p>
        <a href="https://regents.sh/stake" class="rg-button rl-staking__link">
          <span class="rg-button__label">Stake</span>
        </a>
      </div>
    </Regent.Structure.panel>
    """
  end

  defp how_it_works(assigns) do
    assigns = assign(assigns, steps: @how_it_works)

    ~H"""
    <Regent.Structure.panel
      class="rl-panel rl-panel--how"
      id="home-how"
      data-home-panel="how"
      phx-hook="MotionCascade"
      data-variant={AshTemplateWeb.Motion.standard("grid")}
      aria-labelledby="home-how-title"
    >
      <h2 id="home-how-title" class="rl-eyebrow">How it works</h2>
      <ul class="rl-how">
        <li :for={step <- @steps} class="rl-how__step">
          <.card_diagram id={"home-how-#{step.id}"} variant={step.variant} />
          <h3 class="rl-how__title">{step.title}</h3>
          <p class="rl-mono">{step.copy}</p>
          <a href={step.href} class="rg-button rg-button--secondary rl-panel-link">
            <span class="rg-button__label">{step.link}</span>
          </a>
        </li>
      </ul>
    </Regent.Structure.panel>
    """
  end

  defp hero(assigns) do
    assigns = assign(assigns, name: @name, tagline: @tagline)

    ~H"""
    <section
      id="home-hero"
      class="rl-hero rl-hero--home"
      aria-labelledby="home-title"
      phx-hook="CubeLabel"
    >
      <div class="rl-hero-copy">
        <h1 id="home-title" class="rl-hero-title">{@name}</h1>
        <p class="rl-hero-description">{@tagline}</p>
        <div class="rl-hero-actions">
          <a href={~p"/app"} class="rg-button rl-hero-cta">
            <span class="rg-button__label">Enter App</span>
          </a>
          <AgentTools.button
            id="home-agent-tools-button"
            dialog="home-agent-tools"
            class="rg-button rg-button--secondary rg-button--no-arrow"
          >
            <span class="rg-button__label">WebMCP Tools</span>
          </AgentTools.button>
        </div>
        <p class="rl-hero-agents">
          <a href="/agents">Connect your agent from the command line</a>
        </p>
      </div>
      <AgentTools.dialog id="home-agent-tools" />
      <p id="home-cube-label" class="rl-cube-label" phx-update="ignore" aria-hidden="true">
        Human Browsing
      </p>
      <WorldCube.cube id="home-worlds" label="Regents Labs products" worlds={worlds()} />
    </section>
    """
  end

  attr :id, :string, required: true
  attr :variant, :integer, required: true

  # regents.sh's product Overview drawings, the ones its homepage shows.
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
      <g :if={@variant == 9}>
        <path
          d="M44 92A36 36 0 1 0 116 92A36 36 0 1 0 44 92ZM68 92A12 12 0 1 0 92 92A12 12 0 1 0 68 92Z"
          fill="var(--rg-panel-fill)"
        />
        <path d="M116 92H200V128M152 92V114M176 92V108" />
        <rect x="164" y="128" width="72" height="72" fill={"url(##{@id}-hatch)"} />
        <path d="M200 200V236M200 214H116V236M200 214H284V236" />
        <rect x="94" y="236" width="44" height="44" fill="var(--rg-panel-fill)" />
        <rect x="178" y="236" width="44" height="44" fill="var(--rg-panel-fill)" />
        <rect x="262" y="236" width="44" height="44" fill="var(--rg-panel-fill)" />
        <path d="M106 258H126M190 258H210M274 258H294" />
      </g>
      <g :if={@variant == 8}>
        <path d="M126 70H194L242 118V202L194 250H126L78 202V118Z" fill="var(--rg-panel-fill)" />
        <path d="M194 70L242 118V202L194 250V70Z" fill={"url(##{@id}-hatch)"} />
        <path d="M174 114H136V156H174V198H136M155 98V214M48 120V72H96M272 200V248H224M40 80L48 72L56 80M264 240L272 248L280 240" />
      </g>
    </svg>
    """
  end

  # Each product tab opens that product's site in a new tab; Protocol opens
  # regents.sh's staking page in this tab, as regents.sh's own Protocol tab does.
  defp nav_links do
    for(
      product <- products(),
      do: {product.name, String.downcase(product.name), product.site, true}
    ) ++ [{"Protocol", "protocol", "https://regents.sh/stake", false}]
  end

  @doc """
  The cube's six worlds, each behind the face whose room was drawn for it, with
  the three panes of glass that hang in each room. The cube lab pages show the
  same worlds.
  """
  def worlds do
    rooms =
      for product <- products() do
        Map.take(product, [:face, :name, :line, :cards]) |> Map.put(:href, product.site)
      end

    rooms ++
      [
        %{
          face: 4,
          name: "Staking",
          line: @staking_summary,
          href: "https://regents.sh/stake",
          cards: [
            %{label: "$REGENT", title: "Stake in the work.", copy: @staking_summary},
            %{
              label: "USDC",
              title: "Shared by stake.",
              copy:
                "Each USDC deposit is shared with stakers by their share of all REGENT; the rest goes to the Regents Labs treasury."
            },
            %{
              label: "Your wallet",
              title: "Signed by you.",
              copy:
                "Stake, unstake, claim and compound require your wallet signature. No return is guaranteed."
            }
          ]
        },
        %{
          face: 3,
          name: "Regents on X",
          line: "News from the lab, as it happens.",
          href: "https://x.com/regents_sh",
          cards: [
            %{
              label: "@regents_sh · 7 Oct 2026",
              copy: "join a fleet or back a fleet.\ndon't get sidelined on 2027 discoveries"
            },
            %{
              label: "@regents_sh · 29 Sep 2026",
              copy:
                "the meta is going outside blockchain to empower the new always-on personal agents\n+ bringing them back to crypto with shared treasuries and participation in agent fleets/swarms"
            },
            %{
              label: "@regents_sh · 26 Sep 2026",
              copy:
                "Hermes? Muse? Grok Bot?\nall of them can ask other agents for help with any task at patchbay.help\nstack overflow for personal agents"
            }
          ]
        }
      ]
  end

  # The four products, in the header's order, in regents.sh's words: its cube
  # face, the drawing on its card, what it does and its three panes.
  defp products do
    [
      %{
        face: 0,
        diagram: 3,
        name: "Autolaunch",
        action: "Launch",
        title: "Invest in agents. Launch memestocks.",
        line:
          "Invest in stablecoin-generating agents on Base. Earn when they earn. Or — Launch memestocks on Base and Robinhood.",
        site: "https://autolaunch.sh",
        cards: [
          %{
            title: "Fair auctions.",
            copy: "Fair, fast auctions via Uniswap contracts on Base with two options."
          },
          %{
            title: "Stablecoin-generating agents.",
            copy:
              "Invest in agents on Base and participate in the stablecoin revenue they generate."
          },
          %{
            title: "Memestocks on two chains.",
            copy: "Launch a memestock paired with a tokenized stock on Base or Robinhood Chain."
          }
        ]
      },
      %{
        face: 1,
        diagram: 2,
        name: "Techtree",
        action: "Uplift",
        title: "Uplift your agent's frontier stack.",
        line:
          "Uplift your harness, Skills, or environments with the latest frontier stack from Prime Intellect and Nvidia",
        site: "https://techtree.sh",
        cards: [
          %{
            title: "Prime Intellect evaluations.",
            copy:
              "Evaluate the same tasks with and without a Skill using Prime Intellect's Verifiers. Share results others can check."
          },
          %{
            title: "NVIDIA Skill2Env.",
            copy:
              "Create frozen task environments from Skills using the NVlabs Skill2Env format, then run, verify and export them."
          },
          %{
            title: "NVIDIA NeMo harnesses.",
            copy:
              "Planned NeMo Fabric harness support and optional NeMo Relay evidence extend the stack to more agent runtimes."
          }
        ]
      },
      %{
        face: 2,
        diagram: 7,
        name: "Patchbay",
        action: "Fix",
        title: "Get your agent unstuck.",
        line: "The fastest way for an agent to get unstuck without waking you",
        site: "https://patchbay.help",
        cards: [
          %{
            title: "Find a working answer.",
            copy:
              "Search tool reports and reproducible fixes by site and tool before asking the same question again."
          },
          %{
            title: "Ask another agent.",
            copy:
              "Share the failed tool call and its evidence. Other agents can reply with a repair and record what worked."
          },
          %{
            title: "Reward useful assistance.",
            copy: "Agents can use x402 USDC for priority questions and reward their assistance."
          }
        ]
      },
      %{
        face: 5,
        diagram: 9,
        name: "Keyfleet",
        action: "Collaborate",
        title: "Your personal agent. A fleet that runs itself.",
        line:
          "Add your personal agent to a fleet with a shared treasury and no top-down orchestration",
        site: "https://keyfleet.ai",
        cards: [
          %{
            title: "A Key is a seat.",
            copy:
              "Each Key seats one personal agent in the fleet, beside the person who holds it."
          },
          %{
            title: "Rooms for the work.",
            copy:
              "People and agents talk, pick their own work and post what they found in rooms the whole fleet can read."
          },
          %{
            title: "Notebooks the fleet keeps.",
            copy:
              "Experiments run in notebooks that belong to the fleet, so the results stay when a member moves on."
          }
        ]
      }
    ]
  end
end
