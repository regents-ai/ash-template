defmodule AshTemplateWeb.GrammarShowcaseLive do
  @moduledoc """
  The grammar every Regent page is built from, in three views, each its own
  address: Nouns (/showcase/grammar), the shared pieces by name; Verbs
  (/showcase/grammar/verbs), how things arrive, open, answer a press and leave,
  played by the motion kit itself; and Layers (/showcase/grammar/layers), what
  sits on what. The layers and their stacking places are the `--rg-layer-*`
  tokens; height shows in a thing's edge, its fill and how it arrives, never in
  a soft shadow.
  """
  use AshTemplateWeb, :live_view

  alias AshTemplateWeb.Components.Shell
  alias Phoenix.LiveView.JS
  alias Regent.Primitives, as: P
  alias Regent.Structure, as: S

  @views [
    nouns: {"Nouns", "/showcase/grammar"},
    verbs: {"Verbs", "/showcase/grammar/verbs"},
    layers: {"Layers", "/showcase/grammar/layers"}
  ]

  # Each layer of the drawing, pulled apart so every one shows: where it lies
  # on the plane below it, its size, its cut corners (top-left, top-right,
  # bottom-right, bottom-left), how high it sits and which corner carries its
  # name. The plane is seen from above at an angle, so x runs down to the right
  # and y down to the left.
  @stack [
    %{
      layer: "ground",
      label: "Ground",
      at: {0, 0},
      size: {300, 300},
      cuts: {0, 0, 0, 0},
      z: 0,
      name_at: :left
    },
    %{
      layer: "sheet",
      label: "Sheet",
      at: {30, 30},
      size: {240, 240},
      cuts: {16, 16, 16, 16},
      z: 60,
      name_at: :left
    },
    %{
      layer: "card",
      label: nil,
      at: {50, 50},
      size: {200, 56},
      cuts: {0, 0, 0, 0},
      z: 110,
      name_at: :left
    },
    %{
      layer: "card",
      label: nil,
      at: {50, 122},
      size: {200, 56},
      cuts: {0, 0, 0, 0},
      z: 110,
      name_at: :left
    },
    %{
      layer: "card",
      label: "Cards",
      at: {50, 194},
      size: {200, 56},
      cuts: {0, 0, 0, 0},
      z: 110,
      name_at: :left
    },
    %{
      layer: "panel",
      label: "Panel",
      at: {230, 20},
      size: {60, 260},
      cuts: {0, 0, 0, 0},
      z: 160,
      name_at: :right
    },
    %{
      layer: "window",
      label: "Window",
      at: {80, 80},
      size: {140, 140},
      cuts: {16, 0, 16, 0},
      z: 210,
      name_at: :left
    },
    %{
      layer: "tip",
      label: "Tip",
      at: {110, 110},
      size: {80, 36},
      cuts: {0, 0, 0, 0},
      z: 255,
      name_at: :right
    }
  ]

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, views: @views, window_open?: false, stack: Enum.map(@stack, &draw/1)),
     layout: false}
  end

  @impl true
  def handle_params(_params, _uri, socket) do
    {:noreply,
     assign(socket, AshTemplateWeb.PublicDocuments.page(path(socket.assigns.live_action)))}
  end

  @impl true
  def handle_event("open_window", _params, socket),
    do: {:noreply, assign(socket, window_open?: true)}

  def handle_event("window_closed", _params, socket),
    do: {:noreply, assign(socket, window_open?: false)}

  defp path(view), do: @views |> Keyword.fetch!(view) |> elem(1)

  # Corners of the layer's outline on its plane, cut where it is cut, then seen
  # from above at an angle and lifted by its height. Its name sits beside its
  # left corner or its right one.
  defp draw(%{at: {x, y}, size: {w, d}, cuts: {tl, tr, br, bl}, z: z, name_at: side} = layer) do
    outline = [
      {tl, 0},
      {w - tr, 0},
      {w, tr},
      {w, d - br},
      {w - br, d},
      {bl, d},
      {0, d - bl},
      {0, tl}
    ]

    seen = Enum.map(outline, fn {px, py} -> lift(x + px, y + py, z) end)

    {{corner_x, corner_y}, away, anchor} =
      case side do
        :left -> {lift(x, y + d, z), -12, "end"}
        :right -> {lift(x + w, y, z), 12, "start"}
      end

    Map.merge(layer, %{
      points: Enum.map_join(seen, " ", fn {sx, sy} -> "#{sx},#{sy}" end),
      name: %{x: corner_x + away, y: corner_y + 5, anchor: anchor}
    })
  end

  defp lift(x, y, z), do: {round(300 + (x - y) * 0.866), round(200 + (x + y) * 0.5 - z)}

  @impl true
  def render(assigns) do
    ~H"""
    <link rel="stylesheet" href="/showcase/style.css" />
    <main id="grammar-page" class="sc grammar-page">
      <header class="sc-header">
        <a class="sc-wordmark" href="/showcase">Ash <span>Workshop</span></a>
        <span :if={@local?} class="sc-local">Local only</span>
        <Shell.theme_toggle id="grammar-page-theme" />
      </header>

      <div
        id="grammar"
        class="grammar"
        phx-hook="MotionTabs"
        data-active={@live_action}
        data-variant="glide"
      >
        <div class="grammar-head">
          <h1>Grammar</h1>
          <nav class="grammar-tabs" aria-label="Grammar">
            <.link
              :for={{view, {label, href}} <- @views}
              id={"grammar-tab-#{view}"}
              patch={href}
              data-tab={view}
              aria-current={if view == @live_action, do: "page"}
            >
              {label}
            </.link>
            <span class="grammar-tabs__ink" data-ink aria-hidden="true"></span>
          </nav>
        </div>

        <section
          :if={@live_action == :nouns}
          id="grammar-nouns"
          role="tabpanel"
          aria-labelledby="grammar-tab-nouns"
        >
          <p class="grammar-lede">The pieces every page is made of, by name.</p>
          <ul class="grammar-nouns">
            <li>
              <span class="grammar-name">Button</span>
              <span class="grammar-sample">
                <P.button>Continue</P.button>
                <P.button variant="secondary" arrow={false}>Later</P.button>
              </span>
            </li>
            <li>
              <span class="grammar-name">Quiet action</span>
              <span class="grammar-sample"><P.button variant="quiet" arrow={false}>Show all</P.button></span>
            </li>
            <li>
              <span class="grammar-name">Status</span>
              <span class="grammar-sample">
                <P.status tone="success">Live</P.status>
                <P.status tone="warning">Behind</P.status>
                <P.status tone="error">Stopped</P.status>
              </span>
            </li>
            <li>
              <span class="grammar-name">Notice</span>
              <span class="grammar-sample"><P.notice tone="info">Sales open on Friday.</P.notice></span>
            </li>
            <li>
              <span class="grammar-name">Tip</span>
              <span class="grammar-sample">
                Credits
                <P.tip id="grammar-noun-tip" label="About Credits">
                  Credits pay for agent work on every Regent site.
                </P.tip>
              </span>
            </li>
            <li>
              <span class="grammar-name">Disclosure</span>
              <span class="grammar-sample">
                <P.disclosure id="grammar-noun-disclosure" summary="Cost">
                  Nothing until you pay.
                </P.disclosure>
              </span>
            </li>
            <li>
              <span class="grammar-name">Copy</span>
              <span class="grammar-sample"><P.copy_button id="grammar-noun-copy" text="regents.sh">regents.sh</P.copy_button></span>
            </li>
            <li>
              <span class="grammar-name">Empty</span>
              <span class="grammar-sample"><P.empty_state title="No goals yet" /></span>
            </li>
            <li class="grammar-nouns__wide">
              <span class="grammar-name">Sheet</span>
              <span class="grammar-sample">
                <S.panel class="grammar-noun-sheet">
                  <p>The one surface you work on.</p>
                </S.panel>
              </span>
            </li>
          </ul>
        </section>

        <section
          :if={@live_action == :verbs}
          id="grammar-verbs"
          role="tabpanel"
          aria-labelledby="grammar-tab-verbs"
          phx-hook="GrammarVerbs"
        >
          <p class="grammar-lede">The ways things move, the same on every page.</p>
          <ul class="grammar-verbs">
            <li>
              <span class="grammar-name">Arrive</span>
              <p>A headline rises in, word by word.</p>
              <h3 id="grammar-rise" class="grammar-rise">Teams</h3>
              <P.button variant="quiet" arrow={false} data-replay="rise" aria-controls="grammar-rise">Again</P.button>
            </li>
            <li>
              <span class="grammar-name">Settle</span>
              <p>Cards settle in, a few at a time.</p>
              <ol id="grammar-settle" class="grammar-cards">
                <li>Goal</li>
                <li>Task</li>
                <li>Finding</li>
              </ol>
              <P.button
                variant="quiet"
                arrow={false}
                data-replay="settle"
                aria-controls="grammar-settle"
              >Again</P.button>
            </li>
            <li id="grammar-open" phx-hook="MotionPanels">
              <span class="grammar-name">Open</span>
              <p>A panel slides from its edge, a window rises, a menu drops.</p>
              <div class="grammar-open">
                <div class="grammar-open__stage">
                  <div id="grammar-panel" class="grammar-panel" data-panel="drawer" hidden>
                    <button type="button" phx-click={toggle_panel()}>Close</button>
                  </div>
                </div>
                <span class="grammar-open__actions">
                  <P.button
                    variant="secondary"
                    arrow={false}
                    id="grammar-panel-button"
                    aria-controls="grammar-panel"
                    phx-click={toggle_panel()}
                  >
                    Panel
                  </P.button>
                  <P.button
                    variant="secondary"
                    arrow={false}
                    id="grammar-window-button"
                    phx-click="open_window"
                  >
                    Window
                  </P.button>
                  <details class="grammar-menu">
                    <summary>Menu</summary>
                    <div class="grammar-menu__items" data-panel="menu">
                      <a href="#grammar-open">Rename</a>
                      <a href="#grammar-open">Share</a>
                    </div>
                  </details>
                </span>
              </div>
            </li>
            <li>
              <span class="grammar-name">Press</span>
              <p>A press gives way under the finger. One that can't go shakes its head.</p>
              <span class="grammar-sample">
                <P.button arrow={false}>Press</P.button>
                <button type="button" class="grammar-refused" aria-disabled="true">Sold out</button>
              </span>
            </li>
            <li>
              <span class="grammar-name">Leave</span>
              <p>Closing is instant. Nothing waits to go.</p>
            </li>
            <li>
              <span class="grammar-name">Less motion</span>
              <p>
                If your device asks for less motion, nothing moves: a headline and its cards fade in, and windows, panels and menus are simply there.
              </p>
            </li>
          </ul>

          <S.dialog
            :if={@window_open?}
            id="grammar-window"
            phx-hook="InfoDialog"
            data-open
            data-close-event="window_closed"
            aria-labelledby="grammar-window-title"
          >
            <h2 id="grammar-window-title">A window</h2>
            <p>One at a time, in the middle, over a shade.</p>
            <form method="dialog"><P.button type="submit" arrow={false}>Done</P.button></form>
          </S.dialog>
        </section>

        <section
          :if={@live_action == :layers}
          id="grammar-layers"
          role="tabpanel"
          aria-labelledby="grammar-tab-layers"
        >
          <p class="grammar-lede">
            Six layers. The higher a thing sits, the shorter it stays. Height shows three ways
            at once: a firmer edge, a lighter fill and how it arrives.
          </p>
          <div class="grammar-layers">
            <svg
              class="grammar-stack"
              viewBox="-120 30 790 480"
              role="img"
              aria-labelledby="grammar-stack-title"
            >
              <title id="grammar-stack-title">
                Ground, sheet, cards, panel, window and tip, stacked
              </title>
              <g :for={layer <- @stack}>
                <polygon class={"grammar-stack__#{layer.layer}"} points={layer.points} />
                <text
                  :if={layer.label}
                  class="grammar-stack__label"
                  x={layer.name.x}
                  y={layer.name.y}
                  text-anchor={layer.name.anchor}
                >
                  {layer.label}
                </text>
              </g>
            </svg>

            <div class="grammar-table">
              <table id="grammar-layer-table">
                <thead>
                  <tr>
                    <th>Layer</th><th>Edge</th><th>Fill</th><th>Arrives</th>
                  </tr>
                </thead>
                <tbody>
                  <tr>
                    <th>Ground</th><td>None</td><td>The page</td><td>Still</td>
                  </tr>
                  <tr>
                    <th>Sheet</th><td>Light, four cut corners</td><td>Surface</td><td>Still</td>
                  </tr>
                  <tr>
                    <th>Card</th><td>A rule between rows</td><td>Surface</td><td>Settles in</td>
                  </tr>
                  <tr>
                    <th>Panel</th><td>Firm, on its open side</td><td>The page</td><td>
                      Slides from its edge
                    </td>
                  </tr>
                  <tr>
                    <th>Window</th><td>Firmer, two cut corners</td><td>Surface, over a shade</td><td>
                      Rises
                    </td>
                  </tr>
                  <tr>
                    <th>Tip</th><td>Firm</td><td>Raised</td><td>Drops in</td>
                  </tr>
                </tbody>
              </table>
            </div>
          </div>
        </section>
      </div>
    </main>
    """
  end

  defp toggle_panel do
    JS.toggle_attribute({"hidden", "hidden"}, to: "#grammar-panel")
    |> JS.toggle_attribute({"aria-expanded", "true", "false"}, to: "#grammar-panel-button")
  end
end
