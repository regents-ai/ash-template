defmodule AshTemplateWeb.HomeLive do
  @moduledoc """
  The homepage, which tracks regents.sh's: the five tabs, the tools button and
  the world cube, whose six rooms carry the same words as regents.sh's cube.
  When regents.sh's homepage changes, this page changes with it
  (`scripts/drift.sh` compares the two). Only the name, the line under it and
  the header's own links are this site's.
  """

  use AshTemplateWeb, :live_view

  alias AshTemplateWeb.Components.{AgentTools, RegentLinks, WorldCube}
  alias AshTemplateWeb.{PublicDocuments, RouteCatalog}

  @staking_summary "Stake $REGENT to earn a pro rata split of all Regents Labs' USDC revenue, plus a temporary REGENT yield for the early community."

  @doc "A public text representation using the same words as the page."
  def agent_markdown do
    directory = Enum.map_join(products(), "\n", &"- [#{&1.name}](#{&1.site}): #{&1.line}")

    rooms =
      Enum.map_join(worlds(), "\n\n", fn world ->
        cards = Enum.map_join(world.cards, "\n", &card_markdown/1)
        "## #{world.name}\n\n#{world.line}\n\n#{cards}\n\n[Visit](#{world.href})"
      end)

    """
    # Ash Template

    A starting point for your next product.

    ## Products

    #{directory}

    #{rooms}

    ## Get started

    [Open the app](#{PublicDocuments.url("/app")}) · [Developer documentation](#{PublicDocuments.url("/docs")}) · [Agent guide](#{PublicDocuments.url("/agents.md")})
    [About](#{PublicDocuments.url("/about")}) · [Contact](#{PublicDocuments.url("/contact")}) · [Privacy](#{PublicDocuments.url("/privacy")})
    """
  end

  defp card_markdown(%{title: title, copy: copy}), do: "- **#{title}** #{copy}"

  defp card_markdown(%{label: label, copy: copy}),
    do: "- #{label}: #{String.replace(copy, "\n", " ")}"

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(PublicDocuments.page("/"))
     |> assign(route_spec: RouteCatalog.fetch!(:home))}
  end

  def render(assigns) do
    ~H"""
    <Regent.Structure.frame id="public-home" class="rl-root">
      <Regent.Structure.row rail={false}><.landing_header /></Regent.Structure.row>

      <main>
        <Regent.Structure.row rail={false}>
          <.hero />
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
            data-holo-tilt="0"
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

  defp hero(assigns) do
    ~H"""
    <section
      id="home-hero"
      class="rl-hero rl-hero--home"
      aria-labelledby="home-title"
      phx-hook="CubeLabel"
    >
      <div class="rl-hero-copy">
        <h1 id="home-title" class="rl-hero-title">Ash Template</h1>
        <p class="rl-hero-description">A starting point for your next product</p>
        <div class="rl-hero-actions">
          <AgentTools.button id="home-agent-tools-button" dialog="home-agent-tools" />
        </div>
      </div>
      <AgentTools.dialog id="home-agent-tools" />
      <p id="home-cube-label" class="rl-cube-label" phx-update="ignore" aria-hidden="true">
        Human Browsing
      </p>
      <WorldCube.cube id="home-worlds" label="Regents Labs products" worlds={worlds()} />
    </section>
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

  # The four products, in the header's order, in regents.sh's words.
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
