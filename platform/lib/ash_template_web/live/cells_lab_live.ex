defmodule AshTemplateWeb.CellsLabLive do
  @moduledoc """
  Cells: the design system's Cells meter (`Regent.Cells.meter/1`) with its moving
  picture, the `CellsMeter` hook. The cells twinkle; a run that grows comes in with a
  bright leading edge, held while the total is counted; a holder let go breaks into
  sparks and the runs after it close up.

  The sample is a made-up token's supply by holder. A visitor adds, removes and
  resizes holders, starts and stops counting, and sees the meter narrow or wide.
  Everything is held in this page's assigns; nothing here reads or changes anything
  outside it.
  """

  use AshTemplateWeb, :live_view

  alias AshTemplateWeb.PublicDocuments
  alias Regent.Cells
  alias Regent.Primitives, as: P

  # Millions of the sample token.
  @capacity 100
  # Every holder the page can show, in the order they stand in the bar, with the
  # share each starts with or comes back with.
  @holders [
    %{key: "treasury", name: "Treasury", value: 24},
    %{key: "liquidity", name: "Liquidity", value: 18},
    %{key: "team", name: "Team", value: 12},
    %{key: "community", name: "Community", value: 9},
    %{key: "rewards", name: "Rewards", value: 6},
    %{key: "reserve", name: "Reserve", value: 8}
  ]
  @keys Enum.map(@holders, & &1.key)

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(PublicDocuments.page(~p"/animations/cells"))
     |> assign(holders: Enum.take(@holders, 4), counting: false, width: "wide")}
  end

  @impl true
  def handle_event("add", _params, socket) do
    holders = socket.assigns.holders

    case Enum.find(@holders, &(not shown?(holders, &1.key))) do
      nil ->
        {:noreply, socket}

      holder ->
        added = %{holder | value: min(holder.value, left(holders))}
        {:noreply, assign(socket, holders: Enum.sort_by([added | holders], &place/1))}
    end
  end

  def handle_event("remove", %{"key" => key}, socket) when key in @keys do
    {:noreply, update(socket, :holders, &Enum.reject(&1, fn holder -> holder.key == key end))}
  end

  def handle_event("resize", %{"sizes" => sizes}, socket) when is_map(sizes) do
    {holders, _used} =
      Enum.map_reduce(socket.assigns.holders, 0, fn holder, used ->
        value = holder |> asked(sizes[holder.key]) |> min(@capacity - used)
        {%{holder | value: value}, used + value}
      end)

    {:noreply, assign(socket, holders: holders)}
  end

  def handle_event("count", _params, socket) do
    {:noreply, update(socket, :counting, &(not &1))}
  end

  def handle_event("width", %{"width" => width}, socket) when width in ~w(narrow wide) do
    {:noreply, assign(socket, width: width)}
  end

  defp shown?(holders, key), do: Enum.any?(holders, &(&1.key == key))

  # Where a holder stands in the bar.
  defp place(holder), do: Enum.find_index(@keys, &(&1 == holder.key))

  # A whole number of millions from a slider, or the holder's own value for anything else.
  defp asked(holder, size) when is_binary(size) do
    case Integer.parse(size) do
      {value, ""} when value >= 0 -> value
      _other -> holder.value
    end
  end

  defp asked(holder, _size), do: holder.value

  defp used(holders), do: holders |> Enum.map(& &1.value) |> Enum.sum()
  defp left(holders), do: @capacity - used(holders)

  defp parts(holders) do
    Enum.map(holders, &%{key: &1.key, name: &1.name, value: &1.value, amount: "#{&1.value}M"})
  end

  defp can_add?(holders), do: length(holders) < length(@holders) and left(holders) > 0

  @impl true
  def render(assigns) do
    assigns =
      assign(assigns,
        used: used(assigns.holders),
        left: left(assigns.holders),
        capacity: @capacity
      )

    ~H"""
    <main id="cells-lab" class="motion-lab motion-lab--cells">
      <header class="motion-lab__head">
        <p class="motion-lab__kicker">
          <a href={~p"/"}>Ash Template</a> / <a href={~p"/animations"}>Motion lab</a> / Cells
        </p>
        <h1>Cells</h1>
        <p class="motion-lab__lede">
          A sample token's supply by holder, in small square cells. Change a holder and the cells follow.
        </p>
      </header>

      <section class={["cells-lab__stage", "cells-lab__stage--#{@width}"]} aria-label="Meter">
        <Cells.meter
          id="cells-lab-meter"
          label="Sample token supply by holder"
          used={"#{@used}M"}
          capacity={"#{@capacity}M Sample token"}
          max={@capacity}
          parts={parts(@holders)}
          busy={@counting}
          phx-hook="CellsMeter"
          phx-mounted={JS.ignore_attributes(["data-cells-ready"])}
        >
          <:status>{if @counting, do: "Counting", else: "#{@left}M left"}</:status>
        </Cells.meter>
      </section>

      <section class="cells-lab__controls" aria-label="Controls">
        <div class="cells-lab__bar">
          <P.button variant="secondary" arrow={false} phx-click="count">
            {if @counting, do: "Stop", else: "Count"}
          </P.button>
          <P.button variant="secondary" arrow={false} phx-click="add" disabled={!can_add?(@holders)}>
            Add
          </P.button>
          <div class="cells-lab__widths" role="group" aria-label="Width">
            <P.button
              :for={{width, label} <- [{"narrow", "Narrow"}, {"wide", "Wide"}]}
              variant="secondary"
              arrow={false}
              phx-click="width"
              phx-value-width={width}
              aria-pressed={to_string(@width == width)}
            >
              {label}
            </P.button>
          </div>
        </div>

        <form id="cells-lab-sizes" class="cells-lab__holders" phx-change="resize">
          <div :for={holder <- @holders} class="cells-lab__holder">
            <label for={"cells-lab-size-#{holder.key}"}>{holder.name}</label>
            <input
              id={"cells-lab-size-#{holder.key}"}
              type="range"
              name={"sizes[#{holder.key}]"}
              min="0"
              max={holder.value + @left}
              step="1"
              value={holder.value}
              aria-valuetext={"#{holder.value} million"}
            />
            <span class="rg-figure">{holder.value}M</span>
            <P.button
              variant="quiet"
              arrow={false}
              phx-click="remove"
              phx-value-key={holder.key}
              aria-label={"Remove #{holder.name}"}
            >
              Remove
            </P.button>
          </div>
        </form>
      </section>
    </main>
    """
  end
end
