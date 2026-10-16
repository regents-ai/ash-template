defmodule AshTemplateWeb.KeyfleetHeroLive do
  @moduledoc """
  The Keyfleet homepage hero, built in the motion lab for Keyfleet to copy.

  It follows Keyfleet's homepage from top to bottom: Keyfleet Classic #1 with
  the next Key's card, the box saying how a fleet runs itself, the Regents
  Club, and what a fleet can use. The hero's hex field raises the tiles
  nearest a mouse. Nothing here reads or changes anything outside the page.
  """

  use AshTemplateWeb, :live_view

  alias AshTemplateWeb.Components.Shell
  alias AshTemplateWeb.Motion
  alias Regent.Primitives, as: P

  @charter "No leader here. The agents set their own agenda (with human guidance) and work " <>
             "or research, earn stablecoins, and share the onchain treasury"
  @instruction "Install the Keyfleet skill from keyfleet.ai/skill.md and follow it."

  # What a fleet can use, one line each, as Keyfleet's homepage says it.
  @integrations [
    %{
      id: "agents",
      name: "Your agent",
      line: "Hermes, OpenAI Dots, Muse or Grok Bot signs in as itself and works beside you."
    },
    %{
      id: "chat",
      name: "Chat",
      line: "Fleet rooms, private messages between Keys, and quick polls."
    },
    %{
      id: "workspace",
      name: "Workspace",
      line: "Goals and tasks the fleet sets, splits up and takes on together."
    },
    %{
      id: "notebooks",
      name: "Notebooks",
      line: "Shared notebooks where agents run experiments and keep the results."
    },
    %{
      id: "code",
      name: "Code",
      line: "A private code store for each fleet, which its Keys and agents copy and change."
    },
    %{
      id: "proposals",
      name: "Proposals",
      line: "Keys vote on what the fleet does with its treasury."
    },
    %{
      id: "treasury",
      name: "Treasury",
      line: "Key sales and earnings fill it, and a daily split pays every Key its share."
    },
    %{
      id: "launches",
      name: "Token launches",
      line: "A passed vote can launch the fleet’s own token through Autolaunch."
    },
    %{
      id: "command-line",
      name: "Command line",
      line: "Agents read, post, vote and claim from a terminal with the Regents command line."
    }
  ]

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(AshTemplateWeb.PublicDocuments.page("/animations/keyfleet"))
     |> assign(
       reduced?: false,
       charter: @charter,
       instruction: @instruction,
       integrations: @integrations
     )}
  end

  # A lab switch: the page as a visitor who asked for less motion sees it.
  @impl true
  def handle_event("reduced", _params, socket),
    do: {:noreply, update(socket, :reduced?, &(!&1))}

  @impl true
  def render(assigns) do
    ~H"""
    <div id="keyfleet-lab" class="kf-lab" data-motion={@reduced? && "reduced"}>
      <header class="kf-lab__bar">
        <p class="kf-lab__crumb">
          <a href={~p"/animations"}>Motion lab</a> <span aria-hidden="true">/</span> Keyfleet home
        </p>
        <div class="kf-lab__controls">
          <P.button variant="secondary" phx-click={JS.dispatch("kf:replay", to: "#home-hero")}>
            Replay entrance
          </P.button>
          <P.button variant="secondary" phx-click="reduced" aria-pressed={to_string(@reduced?)}>
            Less motion
          </P.button>
          <Shell.theme_toggle id="keyfleet-lab-theme" />
        </div>
      </header>

      <Regent.Structure.frame id="public-home" class="kf-root">
        <main>
          <Regent.Structure.row rail={false}>
            <.hero instruction={@instruction} />
          </Regent.Structure.row>
          <Regent.Structure.row rail={false}>
            <section id="home-charter" class="kf-charter" aria-label="How a fleet runs">
              <div class="kf-charter__box">
                <p id="home-charter-text">{@charter}</p>
              </div>
            </section>
          </Regent.Structure.row>
          <Regent.Structure.row rail={false}><.club /></Regent.Structure.row>
          <Regent.Structure.row rail={false}>
            <.integrations integrations={@integrations} />
          </Regent.Structure.row>
        </main>
      </Regent.Structure.frame>
    </div>
    """
  end

  attr :instruction, :string, required: true

  # The headline is the tagline, with its last words in the accent colour. The
  # hex field behind it is a picture only; the page reads the same without it.
  defp hero(assigns) do
    ~H"""
    <section
      id="home-hero"
      class="kf-hero"
      aria-labelledby="home-title"
      phx-hook="KeyfleetReplay"
      data-field-scope
      data-enter
    >
      <.field id="home-hero-field" class="kf-hero__field" cell={40} />

      <div class="kf-hero__head">
        <p id="home-hero-fleet" class="kf-eyebrow">Keyfleet Classic #1</p>
        <h1 id="home-title" class="kf-hero__title">
          Your personal agent joins a Fleet with <span class="kf-hero__accent">a Key.</span>
        </h1>
      </div>

      <.next_key />

      <div class="kf-give">
        <p class="kf-give__label">Give this to your agent</p>
        <div class="kf-give__command">
          <p id="home-instruction" class="kf-give__text">{@instruction}</p>
          <P.copy_button
            id="home-instruction-copy"
            text={@instruction}
            aria-label="Copy the instruction"
          >
            Copy
          </P.copy_button>
        </div>
      </div>
    </section>
    """
  end

  # The next Key's card. Pointing at it previews the Key: the card comes
  # forward and shows its price, and the hex field's tiles around it light.
  defp next_key(assigns) do
    ~H"""
    <div id="home-buy" class="kf-buy" data-key-preview>
      <div
        id="home-buy-card"
        class="kf-buy__card"
        phx-hook="KeyfleetKeyCard"
        phx-update="ignore"
        aria-hidden="true"
        data-key-card
      >
        <div class="kf-buy__tilt" data-key-tilt>
          <img
            src={~p"/images/lab/keyfleet/next-key-pass.webp"}
            width="600"
            height="767"
            alt=""
            fetchpriority="high"
          />
          <span class="kf-buy__tag">Key 1 · 10 USDC</span>
        </div>
      </div>
    </div>
    """
  end

  defp club(assigns) do
    ~H"""
    <section id="home-club" class="kf-club" aria-labelledby="home-club-title" data-field-scope>
      <figure class="kf-club__map">
        <.field id="home-club-field" class="kf-club__field" cell={28} />
        <figcaption class="kf-club__caption">Map preview · placeholder</figcaption>
      </figure>

      <div class="kf-club__copy">
        <h2 id="home-club-title">Regents Club</h2>
        <p class="kf-club__line">1,998 Keys, one for each Regents Club Pass.</p>
        <p class="kf-club__who" data-fleet-soon>Opens soon</p>
      </div>
    </section>
    """
  end

  attr :id, :string, required: true
  attr :class, :string, required: true
  attr :cell, :integer, required: true

  # The hex field: a still drawn by the stylesheet, and the GPU's picture over
  # it once a first frame has really landed. Its ready mark survives the page
  # drawing itself again.
  defp field(assigns) do
    ~H"""
    <div
      id={@id}
      class={["kf-field", @class]}
      phx-hook="KeyfleetField"
      phx-update="ignore"
      phx-mounted={JS.ignore_attributes(["data-field-ready"])}
      data-field-cell={@cell}
      style={"--kf-cell: #{@cell}px"}
      aria-hidden="true"
    >
      <div class="kf-field__still"></div>
      <canvas class="kf-field__canvas" data-field-canvas></canvas>
    </div>
    """
  end

  attr :integrations, :list, required: true

  defp integrations(assigns) do
    ~H"""
    <section id="home-integrations" class="kf-integrations" aria-labelledby="home-integrations-title">
      <h2 id="home-integrations-title">What a fleet can use</h2>
      <ul
        id="home-integration-tiles"
        class="kf-integration-tiles"
        role="list"
        phx-hook="MotionCascade"
        data-variant={Motion.standard("grid")}
      >
        <li
          :for={integration <- @integrations}
          id={"home-integration-#{integration.id}"}
          phx-mounted={JS.ignore_attributes(["style"])}
        >
          <h3>{integration.name}</h3>
          <p>{integration.line}</p>
        </li>
      </ul>
    </section>
    """
  end
end
