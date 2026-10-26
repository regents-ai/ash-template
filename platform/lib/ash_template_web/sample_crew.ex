defmodule AshTemplateWeb.SampleCrew do
  @moduledoc """
  The sample agents the motion lab's agent harbour and swarm city share: three
  places an agent acts at (the inn is a chat, the forge is work and the castle
  is a proposal), six agents, and one of them acting somewhere new every few
  seconds. Nothing here reads or changes anything outside the page.
  """

  use Phoenix.Component

  alias AshTemplateWeb.NotFoundError

  # Each place and the action that sends an agent there.
  @places [
    %{id: "inn", name: "Inn", action: "Chat"},
    %{id: "forge", name: "Forge", action: "Work"},
    %{id: "castle", name: "Castle", action: "Proposal"}
  ]

  @place_ids Enum.map(@places, & &1.id)
  @places_by_id Map.new(@places, &{&1.id, &1})

  # The column of a page's list of agents that each place heads. Each agent keeps
  # its own row and stands in its place's column, so the list keeps its height
  # wherever the agents gather.
  @columns @place_ids |> Enum.with_index(1) |> Map.new()

  # The sample agents: the Key each one holds, its colour, and the place of its
  # last action.
  @crew [
    %{id: "ada", name: "Ada", key: 17, color: "#e4572e", place: "inn"},
    %{id: "basil", name: "Basil", key: 204, color: "#17bebb", place: "forge"},
    %{id: "clio", name: "Clio", key: 388, color: "#f2c14e", place: "castle"},
    %{id: "dot", name: "Dot", key: 512, color: "#7b61ff", place: "inn"},
    %{id: "ezra", name: "Ezra", key: 731, color: "#4caf50", place: "forge"},
    %{id: "fern", name: "Fern", key: 966, color: "#2e86de", place: "castle"}
  ]

  @every :timer.seconds(7)

  # How many actions an agent's card lists, newest first.
  @kept 4

  @doc "The three places, in the order the pages list them."
  def places, do: @places

  @doc "How often one agent acts, in milliseconds."
  def every, do: @every

  @doc "The place an address names, or nil for none; a place that does not exist is not found."
  def place!(nil), do: nil
  def place!(id), do: Map.get(@places_by_id, id) || raise(NotFoundError)

  @doc "The agents as they stand at `now`, each with a few earlier actions."
  def crew(now), do: Enum.with_index(@crew, &with_history(&1, &2, now))

  # A sample agent's earlier actions: its last one a little while ago, and one
  # at each other place before that.
  defp with_history(agent, index, now) do
    earlier = List.delete(@place_ids, agent.place)
    last = DateTime.add(now, -(40 + index * 70))

    actions =
      [agent.place | earlier]
      |> Enum.with_index(fn place, step ->
        %{place: place, at: DateTime.add(last, -step * 260)}
      end)

    Map.put(agent, :actions, actions)
  end

  @doc "One agent, chosen at random, does something at a different place at `now`."
  def act(crew, now) do
    agent = Enum.random(crew)
    place = @place_ids |> List.delete(agent.place) |> Enum.random()

    acted = %{
      agent
      | place: place,
        actions: Enum.take([%{place: place, at: now} | agent.actions], @kept)
    }

    Enum.map(crew, &if(&1.id == agent.id, do: acted, else: &1))
  end

  @doc "The agent an address names, if it is one of the crew."
  def agent_id(crew, id), do: if(Enum.any?(crew, &(&1.id == id)), do: id)

  @doc "The crew as a page's picture reads it: who, where, and their colour."
  def drawn(crew), do: Jason.encode!(Enum.map(crew, &Map.take(&1, [:id, :name, :place, :color])))

  @doc "What a list calls the place an agent is at."
  def place_name(place), do: Map.fetch!(@places_by_id, place).name

  @doc "The column of a page's list of agents that a place heads."
  def column(place), do: Map.fetch!(@columns, place)

  attr :agent, :map, required: true
  attr :now, DateTime, required: true

  @doc """
  An agent's card: its Key, its last action and the ones before it. It opens as
  it is rendered and closes with its X, Escape or the browser's back button.
  """
  def agent_card(assigns) do
    ~H"""
    <Regent.Structure.dialog
      id="harbour-agent"
      class="harbour-card"
      aria-labelledby="harbour-agent-title"
      phx-hook="InfoDialog"
      data-open
      data-close-event="close_agent"
    >
      <header class="harbour-card__head">
        <span class="harbour-card__sail" style={"--sail: #{@agent.color}"}></span>
        <div>
          <h2 id="harbour-agent-title">{@agent.name}</h2>
          <p>Key #{@agent.key}</p>
        </div>
        <form method="dialog">
          <button type="submit" class="harbour-card__close" aria-label="Close">
            <svg viewBox="0 0 16 16" aria-hidden="true">
              <path d="M3 3l10 10M13 3L3 13" fill="none" stroke="currentColor" stroke-width="1.5" />
            </svg>
          </button>
        </form>
      </header>
      <ol class="harbour-card__actions" aria-label="Recent actions">
        <li :for={action <- @agent.actions}>
          <span>{doing(action.place)}</span>
          <time datetime={DateTime.to_iso8601(action.at)}>{ago(action.at, @now)}</time>
        </li>
      </ol>
    </Regent.Structure.dialog>
    """
  end

  defp doing(place) do
    %{name: name, action: action} = Map.fetch!(@places_by_id, place)
    "#{action} at the #{name}"
  end

  defp ago(at, now) do
    case DateTime.diff(now, at) do
      seconds when seconds < 10 -> "Just now"
      seconds when seconds < 60 -> "#{seconds} s ago"
      seconds -> "#{div(seconds, 60)} min ago"
    end
  end
end
