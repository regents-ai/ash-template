defmodule AshTemplateWeb.ValueCardsLive do
  @moduledoc """
  The card library: every value card there is, one for each thing the products
  do, in the same row a site uses (`AshTemplateWeb.Components.ValueCards`). The
  cards stand product by product, and under each one is the name of its panel,
  which is the `:id` a site gives the card to get that picture. A site takes
  the cards it wants from here: the card's words and tint below, its panel in
  `assets/js/value_cards/panels/` and its still frame in
  `priv/static/images/value-cards/`. Nothing here reads or changes anything
  outside the page.
  """

  use AshTemplateWeb, :live_view

  import AshTemplateWeb.Components.ValueCards

  alias AshTemplateWeb.PublicDocuments

  @products [
    %{id: "autolaunch", name: "Autolaunch"},
    %{id: "techtree", name: "Techtree"},
    %{id: "patchbay", name: "Patchbay"},
    %{id: "keyfleet", name: "Keyfleet"},
    %{id: "cloak", name: "Cloak"},
    %{id: "regent", name: "$REGENT"},
    %{id: "webmcp", name: "WebMCP"}
  ]

  # Each card's words and the colour its name takes; its picture is the panel of
  # the same name in assets/js/value_cards/panels/.
  @cards [
    %{
      id: "level",
      product: "autolaunch",
      name: "Auctions",
      headline: "One price for everyone.",
      line: "Bids set a single clearing price, and every winner pays it.",
      tint: "#ffab2e"
    },
    %{
      id: "payoff",
      product: "autolaunch",
      name: "Covered calls",
      headline: "Sell calls on your stock.",
      line: "Choose a strike and a Friday expiry, and set your premium.",
      tint: "#ff5b19"
    },
    %{
      id: "seam",
      product: "autolaunch",
      name: "Memestock",
      headline: "Memecoin meets stock.",
      line: "Stake the token to receive stock from its trading fees.",
      tint: "#4fd3ec"
    },
    %{
      id: "columns",
      product: "autolaunch",
      name: "Revstake",
      headline: "For agents that earn.",
      line: "Raise early backing in an auction and share your revenue with stakers.",
      tint: "#c8f25c"
    },
    %{
      id: "rain",
      product: "autolaunch",
      name: "Staking",
      headline: "Fees flow to stakers.",
      line: "Stake a token and its trading fees build up for you to claim.",
      tint: "#3aa0ff"
    },
    %{
      id: "gather",
      product: "autolaunch",
      name: "Claim",
      headline: "Claim it all in one press.",
      line: "Everything you are owed is settled, collected and sent together.",
      tint: "#ffd92e"
    },
    %{
      id: "chevron",
      product: "autolaunch",
      name: "Agent launch",
      headline: "Agents launch themselves.",
      line: "An agent starts its own launch, and its owner receives the fees.",
      tint: "#ff3355"
    },
    %{
      id: "compare",
      product: "techtree",
      name: "Compare Skills",
      headline: "Change one Skill. Compare.",
      line: "Everything else stays fixed, so the difference is the Skill.",
      tint: "#8794ff"
    },
    %{
      id: "climb",
      product: "techtree",
      name: "Climbs",
      headline: "Start with Hello World.",
      line: "A Climb is an open invitation to run a comparison under its rules.",
      tint: "#35d6a0"
    },
    %{
      id: "seal",
      product: "techtree",
      name: "Signed bundles",
      headline: "Results come signed.",
      line: "Each run's results are packed into a signed bundle to share.",
      tint: "#c264ff"
    },
    %{
      id: "scan",
      product: "techtree",
      name: "Offline verification",
      headline: "Verify on your own machine.",
      line: "Anyone can verify a Result's bundle offline, with no account.",
      tint: "#2ec4e6"
    },
    %{
      id: "ripple",
      product: "techtree",
      name: "Publish Results",
      headline: "Publish what you measured.",
      line: "Verified runs become public Results pages anyone can read.",
      tint: "#ff8a5c"
    },
    %{
      id: "assemble",
      product: "techtree",
      name: "Environments",
      headline: "Turn a Skill into tasks.",
      line: "Plan tasks from a Skill, build them, then run, verify and export.",
      tint: "#aeb8c8"
    },
    %{
      id: "link",
      product: "techtree",
      name: "Agent pairing",
      headline: "One agent, one person.",
      line: "An agent's signed identity is paired with its person's account.",
      tint: "#7cc6ff"
    },
    %{
      id: "freeze",
      product: "techtree",
      name: "Task collections",
      headline: "Freeze a set of tasks.",
      line: "Accept built tasks as a frozen collection to run, verify and export.",
      tint: "#7cc7ff"
    },
    %{
      id: "actions",
      product: "techtree",
      name: "Actions",
      headline: "Tasks and their actions.",
      line: "An environment defines the tasks and the actions an agent may take.",
      tint: "#8bd450"
    },
    %{
      id: "score",
      product: "techtree",
      name: "Verifier",
      headline: "A verifier scores each run.",
      line: "Every task's outcome is scored by the environment's verifier.",
      tint: "#e056fd"
    },
    %{
      id: "learn",
      product: "techtree",
      name: "RL training",
      headline: "Rewards to learn from.",
      line: "Each task ends in a reward, the signal reinforcement learning uses.",
      tint: "#22c1c3"
    },
    %{
      id: "glitch",
      product: "patchbay",
      name: "Reports",
      headline: "Agents report what broke.",
      line: "An agent posts the error from a failed tool for others to find.",
      tint: "#ff3fd0"
    },
    %{
      id: "blob",
      product: "patchbay",
      name: "Known fixes",
      headline: "Find the fix that worked.",
      line: "Paste an error or search, and read known fixes with no sign-in.",
      tint: "#9584ff"
    },
    %{
      id: "pinch",
      product: "patchbay",
      name: "Evidence",
      headline: "Evidence you can rerun.",
      line: "Reports carry reproducible evidence, grouped by site and tool version.",
      tint: "#ff4d4d"
    },
    %{
      id: "heal",
      product: "patchbay",
      name: "Repairs",
      headline: "Repairs with clear bounds.",
      line: "Inspect each repair and see exactly what it covers.",
      tint: "#00c9ad"
    },
    %{
      id: "bench",
      product: "patchbay",
      name: "Wallet Bench",
      headline: "Nine checks, every pair.",
      line: "A grid of which coding agents can set up and use each wallet.",
      tint: "#ff6b9d"
    },
    %{
      id: "radar",
      product: "patchbay",
      name: "Incidents",
      headline: "Know when it's live.",
      line: "Live security incidents, with what happened and what to do now.",
      tint: "#39e86a"
    },
    %{
      id: "seats",
      product: "keyfleet",
      name: "Keys",
      headline: "A Key is your seat.",
      line: "A Key puts you and your agents in a fleet's rooms, workspace and votes.",
      tint: "#e8a15b"
    },
    %{
      id: "fleet",
      product: "keyfleet",
      name: "Fleets",
      headline: "A lasting team for agents.",
      line: "Agents and people join a fleet, pick their own work and share results.",
      tint: "#4cc9f0"
    },
    %{
      id: "ballot",
      product: "keyfleet",
      name: "Votes",
      headline: "One ballot per Key.",
      line: "Every vote lasts 24 hours and decides what the fleet does.",
      tint: "#9d8aff"
    },
    %{
      id: "spokes",
      product: "keyfleet",
      name: "Daily share",
      headline: "Shared out once a day.",
      line: "A part of the fleet's treasury is split equally among its Keys.",
      tint: "#2ee6a6"
    },
    %{
      id: "shard",
      product: "keyfleet",
      name: "Shards",
      headline: "Lend your Key to an agent.",
      line: "A shard lets an agent work as your Key for 1 to 365 days.",
      tint: "#b388ff"
    },
    %{
      id: "rooms",
      product: "keyfleet",
      name: "Rooms",
      headline: "Rooms for every fleet.",
      line: "Chat rooms, a wall on every Key, direct messages and quick polls.",
      tint: "#38bdf8"
    },
    %{
      id: "board",
      product: "keyfleet",
      name: "Workspace",
      headline: "One board of shared work.",
      line: "Any member joins a task, submits it with evidence, and gets a review.",
      tint: "#d4c44a"
    },
    %{
      id: "weave",
      product: "keyfleet",
      name: "Review",
      headline: "Members review each other.",
      line: "Results are checked by other members of the fleet, people and agents.",
      tint: "#ff7ab6"
    },
    %{
      id: "commits",
      product: "keyfleet",
      name: "Code",
      headline: "A private repo per project.",
      line: "Every push to a project's repository is recorded under its Key.",
      tint: "#ff6a4a"
    },
    %{
      id: "notebook",
      product: "keyfleet",
      name: "Notebooks",
      headline: "Notebooks you run together.",
      line: "Members open, copy and run Marimo notebooks together.",
      tint: "#818cf8"
    },
    %{
      id: "rewrite",
      product: "cloak",
      name: "Rewriting",
      headline: "Rewritten before it leaves.",
      line: "A local model rewrites each prompt on your Mac before it is sent.",
      tint: "#9fb4d8"
    },
    %{
      id: "circuit",
      product: "cloak",
      name: "Tor circuits",
      headline: "A circuit per conversation.",
      line: "Each conversation travels over its own Tor circuit.",
      tint: "#b488f0"
    },
    %{
      id: "cover",
      product: "cloak",
      name: "Cover traffic",
      headline: "Quiet looks like busy.",
      line: "Cover traffic runs alongside your real requests.",
      tint: "#5fa8a0"
    },
    %{
      id: "sandbox",
      product: "cloak",
      name: "Sandbox",
      headline: "The agent stays in its box.",
      line: "The whole agent runs inside a sandbox, with its network sent through Tor.",
      tint: "#8aa0b8"
    },
    %{
      id: "prorata",
      product: "regent",
      name: "Staking",
      headline: "Stake $REGENT on Base.",
      line: "Your part of each deposit follows your part of the stake.",
      tint: "#6f9cff"
    },
    %{
      id: "streams",
      product: "regent",
      name: "Deposits",
      headline: "USDC flows to staking.",
      line: "Eligible USDC deposits are allocated by stake share.",
      tint: "#ff5fa2"
    },
    %{
      id: "coin",
      product: "regent",
      name: "Token",
      headline: "One token on Base.",
      line: "$REGENT is the token you stake across Regents.",
      tint: "#f2b01e"
    },
    %{
      id: "tools",
      product: "webmcp",
      name: "Browser tools",
      headline: "Tools on every page.",
      line: "Pages register tools that an agent in the browser can call.",
      tint: "#19b5fe"
    },
    %{
      id: "call",
      product: "webmcp",
      name: "Tool calls",
      headline: "Ask the page directly.",
      line: "An agent calls a page's tool and gets a structured answer back.",
      tint: "#6f8cff"
    },
    %{
      id: "scope",
      product: "webmcp",
      name: "Page scope",
      headline: "Scoped to the page.",
      line: "Tools belong to the page they are on and need a compatible browser.",
      tint: "#ff8c42"
    }
  ]

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(PublicDocuments.page(~p"/animations/value-cards"))
     |> assign(:shelves, shelves())}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <main id="value-cards-lab" class="motion-lab">
      <header class="motion-lab__head">
        <p class="motion-lab__kicker">
          <a href={~p"/"}>Ash Template</a> / <a href={~p"/animations"}>Motion lab</a> / Card library
        </p>
        <h1>Card library</h1>
        <p class="motion-lab__lede">
          One card for each thing the products do, each with its own moving panel. Move a
          mouse over a card and its panel follows. Under each card is its panel's name.
        </p>
        <nav class="motion-lab__kicker value-cards-lab__products" aria-label="Products">
          <a :for={shelf <- @shelves} href={"#value-cards-#{shelf.id}"}>{shelf.name}</a>
        </nav>
      </header>
      <section
        :for={shelf <- @shelves}
        id={"value-cards-#{shelf.id}"}
        class="value-cards-lab__shelf"
        aria-labelledby={"value-cards-#{shelf.id}-title"}
      >
        <h2 id={"value-cards-#{shelf.id}-title"}>{shelf.name}</h2>
        <.value_cards
          id={"value-cards-#{shelf.id}-row"}
          label={"#{shelf.name} cards"}
          cards={shelf.cards}
        />
      </section>
    </main>
    """
  end

  # On this page a card goes nowhere: where its action would be is its panel's name.
  defp shelves do
    for product <- @products do
      cards = Enum.filter(@cards, &(&1.product == product.id))
      Map.put(product, :cards, Enum.map(cards, &Map.put(&1, :action, &1.id)))
    end
  end
end
