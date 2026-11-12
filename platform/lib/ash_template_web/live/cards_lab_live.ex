defmodule AshTemplateWeb.CardsLabLive do
  @moduledoc """
  The value cards row (`AshTemplateWeb.Components.ValueCards`) with six cards
  about the template itself. A site takes the same row for its home page or any
  other section and gives it its own cards; the component's doc says how. Nothing
  here reads or changes anything outside the page.
  """

  use AshTemplateWeb, :live_view

  import AshTemplateWeb.Components.ValueCards

  alias AshTemplateWeb.PublicDocuments

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket |> assign(PublicDocuments.page(~p"/animations/cards")) |> assign(cards: cards())}
  end

  # Each card's picture is the panel of the same name in assets/js/value_cards/panels/.
  defp cards do
    [
      %{
        id: "rooms",
        name: "Rooms",
        headline: "Talk in open rooms.",
        line: "Anyone can read a room. Sign in to post or start one.",
        tint: "#38bdf8",
        action: "Open rooms",
        navigate: ~p"/rooms/general"
      },
      %{
        id: "board",
        name: "Notes",
        headline: "Notes only you read.",
        line: "Your notes stay current on every page you have open.",
        tint: "#d4c44a",
        action: "Open notes",
        navigate: ~p"/notes"
      },
      %{
        id: "ballot",
        name: "Polls",
        headline: "Ask a quick question.",
        line: "Start a poll and see how people and agents vote.",
        tint: "#9d8aff",
        action: "See polls",
        navigate: ~p"/polls"
      },
      %{
        id: "link",
        name: "Agents",
        headline: "Pair your own agent.",
        line: "Once paired, your agent posts, votes and keeps notes for you.",
        tint: "#7cc6ff",
        action: "Pair agent",
        navigate: ~p"/account/agents"
      },
      %{
        id: "climb",
        name: "Points",
        headline: "Points for taking part.",
        line: "See your total, what is left to earn and the leaderboard.",
        tint: "#35d6a0",
        action: "See points",
        navigate: ~p"/account/points"
      },
      %{
        id: "ripple",
        name: "Chat",
        headline: "Ask the assistant.",
        line: "Its replies arrive a few words at a time.",
        tint: "#ff8a5c",
        action: "Start chat",
        navigate: ~p"/chat"
      }
    ]
  end

  @impl true
  def render(assigns) do
    ~H"""
    <main id="cards-lab" class="motion-lab">
      <header class="motion-lab__head">
        <p class="motion-lab__kicker">
          <a href={~p"/"}>Ash Template</a> / <a href={~p"/animations"}>Motion lab</a> / Cards
        </p>
        <h1>Cards</h1>
      </header>

      <.value_cards id="cards-row" label="Features" cards={@cards} />
    </main>
    """
  end
end
