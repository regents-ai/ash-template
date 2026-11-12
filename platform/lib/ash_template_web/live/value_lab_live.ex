defmodule AshTemplateWeb.ValueLabLive do
  @moduledoc """
  The value card: one figure on a card whose surface lights where the pointer or
  a finger is. Three cards with sample figures, then the same card loading, empty
  and failed.

  Every card on the page sits on one GPU picture (the `ValueLight` hook, one
  canvas island behind the whole grid): it paints the cards' surface and edges,
  lit round the pointer, brighter the faster the pointer moves, and a touch makes
  the light breathe once. The figures are real text above it, so the page reads
  the same without the picture, with less motion asked for, or off screen, where
  the cards keep their flat surface and plain edge. Nothing here reads or changes
  anything outside the page.
  """

  use AshTemplateWeb, :live_view

  alias AshTemplateWeb.PublicDocuments
  alias Regent.Primitives

  @cards [
    %{id: "value-credits", label: "Credits", value: "1,240", unit: nil, line: "Of 2,000"},
    %{id: "value-balance", label: "Balance", value: "3,482.50", unit: "USDC", line: "2 wallets"},
    %{id: "value-earnings", label: "Earnings", value: "96.20", unit: "USDC", line: "This week"}
  ]

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket |> assign(PublicDocuments.page(~p"/animations/value")) |> assign(cards: @cards)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <main id="value-lab" class="motion-lab motion-lab--value">
      <header class="motion-lab__head">
        <p class="motion-lab__kicker">
          <a href={~p"/"}>Ash Template</a> / <a href={~p"/animations"}>Motion lab</a> / Value
        </p>
        <h1>Value</h1>
      </header>

      <div
        id="value-cards"
        class="value-lab"
        phx-hook="ValueLight"
        phx-mounted={JS.ignore_attributes(["data-value-ready"])}
      >
        <div id="value-cards-stage" class="value-lab__stage" phx-update="ignore" aria-hidden="true">
          <canvas data-value-canvas></canvas>
        </div>

        <section class="value-lab__row" aria-labelledby="value-figures-title">
          <h2 id="value-figures-title" class="value-lab__title">Figures</h2>
          <article :for={card <- @cards} id={card.id} class="value-card" data-value-card>
            <h3 class="value-card__label">{card.label}</h3>
            <p class="value-card__figure">
              <Primitives.figure value={card.value} />
              <span :if={card.unit} class="value-card__unit">{card.unit}</span>
            </p>
            <p class="value-card__line">{card.line}</p>
          </article>
        </section>

        <section class="value-lab__row" aria-labelledby="value-states-title">
          <h2 id="value-states-title" class="value-lab__title">States</h2>
          <article id="value-loading" class="value-card" data-value-card>
            <h3 class="value-card__label">Credits</h3>
            <Primitives.waiting id="value-loading-figure" class="value-card__figure">
              <span></span>
            </Primitives.waiting>
            <p class="value-card__line value-card__line--held">Of 2,000</p>
          </article>
          <article id="value-empty" class="value-card" data-value-card>
            <h3 class="value-card__label">Credits</h3>
            <p class="value-card__figure"><Primitives.figure value="0" /></p>
            <p class="value-card__line">None yet</p>
          </article>
          <article id="value-failed" class="value-card" data-value-card>
            <h3 class="value-card__label">Credits</h3>
            <Primitives.waiting id="value-failed-figure" state={:error} class="value-card__figure">
              <span></span>
            </Primitives.waiting>
            <p class="value-card__line value-card__line--held">Of 2,000</p>
          </article>
        </section>
      </div>
    </main>
    """
  end
end
