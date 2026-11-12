defmodule AshTemplateWeb.HomeLive do
  @moduledoc """
  The homepage, which tracks regents.sh's: the datascape filling the window, one
  glass panel over it that holds the header, the name and its line, the actions
  and, at its foot, the product tabs, and the copyright at the window's foot,
  in regents.sh's words. When regents.sh's homepage changes, this page changes with
  it (`scripts/drift.sh` compares the two). Only the name and the header's own
  links are this site's.
  """

  use AshTemplateWeb, :live_view

  alias AshTemplateWeb.Components.{AgentTools, RegentLinks}
  alias AshTemplateWeb.{PublicDocuments, RouteCatalog}

  @name "Ash Template"

  @staking_summary "Stake $REGENT to share in Regents Labs' USDC revenue, in proportion to how much of all REGENT you stake, plus 20% a year in REGENT, for now."

  # The lab's one plain line under its name, on the page and in the agent copy.
  @mission "We build tools for people and their agents. REGENT stakers share in the revenue."

  @doc "A public text representation saying what the page says, in the page's order."
  def agent_markdown do
    products =
      Enum.map_join(nav_links(), " · ", fn {label, _id, href, _new_tab?} ->
        "[#{label}](#{href})"
      end)

    """
    # #{@name}

    #{@mission}

    [Enter App](#{PublicDocuments.url("/app")}) · [WebMCP Tools](#{PublicDocuments.url("/llms.txt")}) · [Connect your agent from the command line](#{PublicDocuments.url("/agents")})

    ## Products

    #{products}

    © 2026 Regents Labs
    """
  end

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(PublicDocuments.page("/"))
     |> assign(route_spec: RouteCatalog.fetch!(:home))}
  end

  # The datascape fills the window, with one glass panel over it that holds the page.
  # While the picture is drawn the panel starts away: pressing a panel in the picture
  # brings it in, and once it has stood for a moment, flying the picture sends it away
  # again. Without scripts, without WebGPU, or with less motion asked for, the
  # server's still picture stays and the panel stays open. The copyright stands at
  # the window's foot throughout, under the panel where the two meet.
  def render(assigns) do
    assigns = assign(assigns, name: @name, mission: @mission)

    ~H"""
    <div
      id="public-home"
      class="rl-root home"
      phx-hook="Datascape"
      phx-mounted={JS.ignore_attributes(["data-datascape-ready", "data-datascape-glass-state"])}
    >
      <a class="shell-skip" href="#home-content">Skip to content</a>
      <img
        class="home__still"
        src={~p"/images/animations/datascape.webp"}
        width="1600"
        height="900"
        alt=""
        aria-hidden="true"
      />
      <div id="home-stage" class="home__stage" phx-update="ignore">
        <canvas id="home-canvas" data-datascape-canvas aria-hidden="true"></canvas>
      </div>
      <footer class="home__copyright">© 2026 Regents Labs</footer>

      <div
        id="home-glass"
        class="home__glass"
        data-datascape-glass
        phx-mounted={JS.ignore_attributes(["style"])}
      >
        <.landing_header />

        <main id="home-content" class="home__main">
          <div class="rl-statement">
            <h1 id="home-title" class="rl-statement__name">{@name}</h1>
            <p class="rl-statement__line">{@mission}</p>
          </div>
          <div class="rl-hero-actions">
            <a href={~p"/app"} class="rg-button rg-button--no-arrow rl-hero-cta">
              <span class="rg-button__label">Enter App</span>
            </a>
            <AgentTools.button
              id="home-agent-tools-button"
              dialog="home-agent-tools"
              class="rg-button rg-button--secondary rg-button--no-arrow rl-hero-secondary"
            >
              <span class="rg-button__label">WebMCP Tools</span>
            </AgentTools.button>
          </div>
          <p class="rl-hero-agents">
            <.link navigate={~p"/agents"}>Connect your agent from the command line</.link>
          </p>
        </main>

        <.products />
      </div>

      <AgentTools.dialog id="home-agent-tools" />
    </div>
    """
  end

  # The homepage is always dark, so its header always carries the dark mark, here
  # without the mark's own ground, which would show as a square on the glass.
  defp landing_header(assigns) do
    ~H"""
    <header class="rl-header" data-home-header>
      <div class="rl-header-bar">
        <.link navigate={~p"/"} class="rl-brand" aria-label="Ash Template home">
          <img
            src={~p"/images/brand/mark-flat-dark-clear.svg"}
            width="252"
            height="186"
            alt=""
          />
        </.link>

        <div class="rl-header-links">
          <RegentLinks.header_links id="home-token-menu" />
        </div>
      </div>
    </header>
    """
  end

  # The panel's foot: the product sites and the staking page, under their small title.
  defp products(assigns) do
    ~H"""
    <nav class="home__foot" aria-labelledby="home-products-title">
      <h2 id="home-products-title" class="rl-overline">Products</h2>
      <div class="rl-product-tabs">
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
      </div>
    </nav>
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
  The world cube's six worlds, each behind the face whose room was drawn for it,
  with the three panes of glass that hang in each room. The cube lab pages show
  them; the homepage's tabs are drawn from the same products.
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

  # The four products, in the tabs' order, in regents.sh's words: each one's cube
  # face, its line and its three panes.
  defp products do
    [
      %{
        face: 0,
        name: "Autolaunch",
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
        name: "Techtree",
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
        name: "Patchbay",
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
        name: "Keyfleet",
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
