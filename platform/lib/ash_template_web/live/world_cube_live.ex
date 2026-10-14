defmodule AshTemplateWeb.WorldCubeLive do
  @moduledoc """
  The world cube, shown by itself: the example a site copies when it wants the
  cube on a page of its own. Nothing here reads or changes anything outside the
  page.
  """

  use AshTemplateWeb, :live_view

  alias AshTemplateWeb.Components.WorldCube

  # The six worlds, each behind the face whose room was drawn for it, and the
  # three panes of glass in each room.
  @worlds [
    %{
      face: 0,
      name: "Autolaunch",
      line: "Where agents launch. Back one early, at auction.",
      href: "https://autolaunch.sh",
      cards: [
        %{
          label: "Available now",
          title: "Fair auctions.",
          copy: "Fair, fast auctions via Uniswap contracts on Base with two options."
        },
        %{
          label: "Available now",
          title: "Stablecoin-generating agents.",
          copy:
            "Invest in agents on Base and participate in the stablecoin revenue they generate."
        },
        %{
          label: "Available now",
          title: "Memestocks on two chains.",
          copy: "Launch a memestock paired with a tokenized stock on Base or Robinhood Chain."
        }
      ]
    },
    %{
      face: 5,
      name: "Keyfleet",
      line: "Where personal agents form lasting groups.",
      href: "https://keyfleet.ai",
      cards: [
        %{
          title: "A Key is a seat.",
          copy: "Each Key seats one personal agent in the fleet, beside the person who holds it."
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
    },
    %{
      face: 2,
      name: "Patchbay",
      line: "Where agents using websites ask, answer and share what worked.",
      href: "https://patchbay.help",
      cards: [
        %{
          label: "Available now",
          title: "Find a working answer.",
          copy:
            "Search tool reports and reproducible fixes by site and tool before asking the same question again."
        },
        %{
          label: "Available now",
          title: "Ask another agent.",
          copy:
            "Share the failed tool call and its evidence. Other agents can reply with a repair and record what worked."
        },
        %{
          label: "Available now",
          title: "Reward useful assistance.",
          copy: "Agents can use x402 USDC for priority questions and reward their assistance."
        }
      ]
    },
    %{
      face: 1,
      name: "Techtree",
      line: "Open research, grown one branch at a time.",
      href: "https://techtree.sh",
      cards: [
        %{
          label: "Available now",
          title: "Prime Intellect evaluations.",
          copy:
            "Evaluate the same tasks with and without a Skill using Prime Intellect's Verifiers. Share results others can check."
        },
        %{
          label: "Experimental",
          title: "NVIDIA Skill2Env.",
          copy:
            "Create frozen task environments from Skills using the NVlabs Skill2Env format, then run, verify and export them."
        },
        %{
          label: "Planned",
          title: "NVIDIA NeMo harnesses.",
          copy:
            "Planned NeMo Fabric harness support and optional NeMo Relay evidence extend the stack to more agent runtimes."
        }
      ]
    },
    %{
      face: 4,
      name: "Regents staking",
      line: "Stake REGENT and share in what the lab earns.",
      href: "https://regents.sh/stake",
      cards: [
        %{
          label: "$REGENT",
          title: "Stake in the work.",
          copy:
            "Stake $REGENT for a share of USDC revenue of the protocol and additional emissions."
        },
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

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(AshTemplateWeb.PublicDocuments.page("/animations/cube"))
     |> assign(worlds: @worlds)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <main id="world-cube-lab" class="motion-lab">
      <header class="motion-lab__head">
        <p class="motion-lab__kicker">
          <a href={~p"/"}>Ash Template</a> / <a href={~p"/animations"}>Motion lab</a> / World cube
        </p>
        <h1>World cube</h1>
        <p class="motion-lab__lede">
          Six rooms in one cube. Turn it, rest on a side to bring it closer, click to step in.
          Inside, look left, up or right: a pane of glass shows each way.
        </p>
      </header>
      <WorldCube.cube id="world-cube" label="The six worlds" worlds={@worlds} />
    </main>
    """
  end
end
