defmodule AshTemplateWeb.Components.ValueCards do
  @moduledoc """
  Value cards: a row of cards, one for each thing a product does.

  A card is dark in both themes. From the top: a square panel of small coloured
  glyphs that moves and follows a mouse, drawn on the GPU by the `ValueCard`
  hook (`assets/js/hooks/value_card.ts`); the feature's name in the card's
  colour beside its place in the row; one line saying what the feature is for;
  a sentence; and, under a dashed rule, what the card does.

  A still frame of the same panel (`priv/static/images/value-cards/<id>.webp`,
  drawn by `npm run stills:value-cards`) is the picture until the panel has
  drawn, and stays where it cannot be: no WebGPU, no JavaScript, or a visitor
  who asked for less motion.

  Each card is a map:

    * `:id` - the panel's name, a file in `assets/js/value_cards/panels/`
    * `:name` - the feature's own name, one or two words
    * `:headline` - one line, ending with a full stop
    * `:line` - one sentence
    * `:tint` - the colour the name takes: the panel's main colour, or a
      lighter step of it where that would not read on the card
    * `:action` - two words for what the card does
    * `:href` - where the card goes. A card without one is not a link, and its
      action stands as a plain note.

  `/animations/value-cards` shows every card there is, and
  `skills/vgpu-island/references/value-cards.md` says how a site takes one.
  """

  use Phoenix.Component
  use AshTemplateWeb, :verified_routes

  alias Phoenix.LiveView.JS

  attr :id, :string, required: true
  attr :label, :string, required: true, doc: "names the row for screen readers"
  attr :cards, :list, required: true

  def value_cards(assigns) do
    assigns = assign(assigns, :count, length(assigns.cards))

    ~H"""
    <ul id={@id} class="value-cards" aria-label={@label}>
      <li
        :for={{card, number} <- Enum.with_index(@cards, 1)}
        id={"#{@id}-#{card.id}"}
        class="value-card"
        style={"--value-card-tint: #{card.tint}"}
        phx-hook="ValueCard"
        phx-mounted={JS.ignore_attributes(["data-value-card-ready"])}
        data-value-card={card.id}
      >
        <.link :if={card[:href]} navigate={card.href} class="value-card__face">
          <.face id={"#{@id}-#{card.id}"} card={card} place={place(number, @count)} />
        </.link>
        <div :if={!card[:href]} class="value-card__face">
          <.face id={"#{@id}-#{card.id}"} card={card} place={place(number, @count)} />
        </div>
      </li>
    </ul>
    """
  end

  attr :id, :string, required: true
  attr :card, :map, required: true
  attr :place, :string, default: nil

  defp face(assigns) do
    ~H"""
    <div class="value-card__panel" aria-hidden="true">
      <img
        class="value-card__still"
        src={~p"/images/value-cards/#{@card.id <> ".webp"}"}
        alt=""
        width="600"
        height="600"
        loading="lazy"
        decoding="async"
      />
      <div id={"#{@id}-stage"} class="value-card__stage" phx-update="ignore">
        <canvas data-value-card-canvas></canvas>
      </div>
    </div>
    <div class="value-card__words">
      <div class="value-card__meta">
        <p class="value-card__name">{@card.name}</p>
        <span :if={@place} class="value-card__place" aria-hidden="true">{@place}</span>
      </div>
      <p class="value-card__headline">{@card.headline}</p>
      <p class="value-card__line">{@card.line}</p>
      <p class="value-card__action">
        {@card.action}<Regent.Icons.icon name="arrow-right" class="value-card__arrow" />
      </p>
    </div>
    """
  end

  # A card's place in its row, as "01 / 03". A card alone in its row has none.
  defp place(_number, 1), do: nil
  defp place(number, count), do: "#{two(number)} / #{two(count)}"

  defp two(number), do: number |> Integer.to_string() |> String.pad_leading(2, "0")
end
