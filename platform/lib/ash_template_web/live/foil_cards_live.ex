defmodule AshTemplateWeb.FoilCardsLive do
  @moduledoc """
  Five foil cards side by side, one for each site: the example a site copies
  when it wants the shared foil on a card of its own. Each card shows one thing
  the foil can be asked for. Nothing here reads or changes anything outside the
  page.
  """

  use AshTemplateWeb, :live_view

  # `:look` is the foil's own attributes, as the `HolographicCard` hook reads them.
  @cards [
    %{
      id: "regents",
      name: "Regents",
      line: "Stake REGENT and share in what the lab earns.",
      note: "Standard",
      look: %{}
    },
    %{
      id: "autolaunch",
      name: "Autolaunch",
      line: "Agents launch here. Back one early, at auction.",
      note: "Brighter light",
      look: %{"data-holo-shine" => "1.6"}
    },
    %{
      id: "patchbay",
      name: "Patchbay",
      line: "Agents using websites ask, answer and share what worked.",
      note: "Plain face",
      look: %{"data-holo-crown" => "false"}
    },
    %{
      id: "techtree",
      name: "Techtree",
      line: "Open research, grown one branch at a time.",
      note: "Softer light",
      look: %{"data-holo-shine" => "0.6"}
    },
    %{
      id: "keyfleet",
      name: "Keyfleet",
      line: "Personal agents form lasting groups.",
      note: "Brightest light",
      look: %{"data-holo-shine" => "2"}
    }
  ]

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(AshTemplateWeb.PublicDocuments.page("/animations/foil"))
     |> assign(cards: @cards)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <main id="foil-cards-lab" class="motion-lab">
      <header class="motion-lab__head">
        <p class="motion-lab__kicker">
          <a href={~p"/"}>Ash Template</a> / <a href={~p"/animations"}>Motion lab</a> / Foil cards
        </p>
        <h1>Foil cards</h1>
        <p class="motion-lab__lede">
          One foil, five cards. Move the pointer across a card to light it.
        </p>
      </header>
      <ul class="foil-cards">
        <li :for={card <- @cards}>
          <Regent.HolographicCard.card
            id={"foil-card-#{card.id}"}
            class="foil-card"
            phx-hook="HolographicCard"
            {card.look}
          >
            <p class="foil-card__note">{card.note}</p>
            <div class="foil-card__words">
              <h2>{card.name}</h2>
              <p>{card.line}</p>
            </div>
          </Regent.HolographicCard.card>
        </li>
      </ul>
    </main>
    """
  end
end
