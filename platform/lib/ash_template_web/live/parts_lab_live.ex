defmodule AshTemplateWeb.PartsLabLive do
  @moduledoc """
  The shared parts the motion kit moves, each with sample data: the segmented
  control and tabs (`MotionTravel`), the breadcrumb (`MotionCrumbs`), an agent's
  activity (`MotionActivity`) and the line chart (`MotionChart`), with the
  loading, failed and empty states the activity and the chart have. The tabs and
  the breadcrumb change the page's address; the period, the steps and the rest
  live on this page alone. Nothing runs on a timer: a step arrives when Next is
  pressed.
  """

  use AshTemplateWeb, :live_view

  alias AshTemplateWeb.PublicDocuments
  alias Regent.{Agents, Charts, Primitives}

  @tabs [{"overview", "Overview"}, {"activity", "Activity"}, {"settings", "Settings"}]

  @levels [
    %{label: "Home", icon: "house"},
    %{label: "Projects", icon: "layers"},
    %{
      label: "Garden",
      icon: "sprout",
      siblings: [
        %{label: "Kitchen", href: "#parts-crumbs"},
        %{label: "Studio", href: "#parts-crumbs"}
      ]
    },
    %{label: "Photos", icon: "camera"},
    %{label: "Sunset.png", icon: "image", card: ["PNG", "2400×3000", "4.2 MB"]}
  ]

  # The deepest path, and where the page opens.
  @depth length(@levels)

  @periods [%{value: "1d", label: "1D"}, %{value: "1w", label: "1W"}, %{value: "1m", label: "1M"}]

  # Prices for each period, oldest first. A day and a week hold eight points
  # each, so the line morphs between them; a month holds twelve.
  @prices %{
    "1d" => [1204.5, 1198.25, 1210.0, 1222.75, 1215.5, 1230.0, 1226.25, 1241.0],
    "1w" => [1150.0, 1172.5, 1165.25, 1190.0, 1205.75, 1198.5, 1220.0, 1241.0],
    "1m" => [
      1020.0,
      1055.5,
      1040.25,
      1080.0,
      1102.75,
      1095.5,
      1130.0,
      1152.25,
      1148.0,
      1190.5,
      1215.0,
      1241.0
    ]
  }

  @kinds [:read, :think, :tool, :write]
  @labels [
    "Offers board",
    "Price check",
    "Order list",
    "Weekly note",
    "Room rules",
    "Reply draft"
  ]

  @impl true
  def mount(_params, _session, socket) do
    now = DateTime.utc_now(:second)

    {:ok,
     socket
     |> assign(PublicDocuments.page(~p"/animations/parts"))
     |> assign(period: "1w", now: now, steps: first_steps(now))}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    tab = if params["tab"] in Enum.map(@tabs, &elem(&1, 0)), do: params["tab"], else: "overview"

    depth =
      case Integer.parse(params["at"] || "") do
        {n, ""} when n in 2..@depth//1 -> n
        _ -> @depth
      end

    {:noreply, assign(socket, tab: tab, depth: depth)}
  end

  @impl true
  def handle_event("period", %{"value" => period}, socket) when is_map_key(@prices, period),
    do: {:noreply, assign(socket, period: period)}

  def handle_event("step", _params, socket) do
    now = DateTime.utc_now(:second)
    {:noreply, assign(socket, now: now, steps: next_step(socket.assigns.steps, now))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <main id="parts-lab" class="motion-lab motion-lab--parts">
      <header class="motion-lab__head">
        <p class="motion-lab__kicker">
          <a href={~p"/"}>Ash Template</a> / <a href={~p"/animations"}>Motion lab</a> / Parts
        </p>
        <h1>Parts</h1>
      </header>

      <div class="parts-lab">
        <section class="parts-lab__part" aria-labelledby="parts-tabs-title">
          <h2 id="parts-tabs-title">Tabs</h2>
          <Primitives.tabs
            id="parts-tabs"
            label="Sections"
            phx-hook="MotionTravel"
            tabs={
              for {value, label} <- tabs() do
                %{label: label, patch: lab_path(value, @depth), current: value == @tab}
              end
            }
          />
        </section>

        <section class="parts-lab__part" aria-labelledby="parts-crumbs-title">
          <h2 id="parts-crumbs-title">Breadcrumb</h2>
          <Primitives.breadcrumb
            id="parts-crumbs"
            phx-hook="MotionCrumbs"
            crumbs={crumbs(@tab, @depth)}
          />
        </section>

        <section class="parts-lab__part parts-lab__part--wide" aria-labelledby="parts-chart-title">
          <h2 id="parts-chart-title">Chart</h2>
          <Charts.line
            id="parts-chart"
            label="Price (USDC)"
            phx-hook="MotionChart"
            series={[%{name: "Price", points: points(@period)}]}
            fill
          >
            <:period>
              <Primitives.segmented
                id="parts-period"
                label="Period"
                name="period"
                event="period"
                phx-hook="MotionTravel"
                options={periods()}
                value={@period}
              />
            </:period>
          </Charts.line>
        </section>

        <section class="parts-lab__part parts-lab__part--wide" aria-labelledby="parts-activity-title">
          <h2 id="parts-activity-title">Activity</h2>
          <Agents.activity
            id="parts-activity"
            label="Pira's activity"
            phx-hook="MotionActivity"
            steps={@steps}
            now={@now}
          />
          <Agents.activity id="parts-activity-line" variant="line" steps={@steps} now={@now} />
          <div>
            <Primitives.button id="parts-step" phx-click="step">Next step</Primitives.button>
          </div>
        </section>

        <section class="parts-lab__part" aria-labelledby="parts-loading-title">
          <h2 id="parts-loading-title">Loading</h2>
          <Charts.line id="parts-chart-loading" label="Price (USDC)" series={:loading} />
          <Agents.activity id="parts-activity-loading" steps={:loading} now={@now} />
        </section>

        <section class="parts-lab__part" aria-labelledby="parts-failed-title">
          <h2 id="parts-failed-title">Failed</h2>
          <Charts.line id="parts-chart-failed" label="Price (USDC)" series={:unavailable} />
          <Agents.activity id="parts-activity-failed" steps={:unavailable} now={@now} />
        </section>

        <section class="parts-lab__part" aria-labelledby="parts-empty-title">
          <h2 id="parts-empty-title">Empty</h2>
          <Charts.line
            id="parts-chart-empty"
            label="Price (USDC)"
            series={[%{name: "Price", points: []}]}
          />
          <Agents.activity id="parts-activity-empty" label="Pira's activity" steps={[]} now={@now} />
        </section>
      </div>
    </main>
    """
  end

  defp tabs, do: @tabs
  defp periods, do: @periods

  defp lab_path(tab, depth), do: ~p"/animations/parts?#{[tab: tab, at: depth]}"

  # The levels down to `depth`; each level above links to itself.
  defp crumbs(tab, depth) do
    @levels
    |> Enum.take(depth)
    |> Enum.with_index(1)
    |> Enum.map(fn
      {level, ^depth} -> Map.delete(level, :siblings)
      {level, at} -> level |> Map.delete(:card) |> Map.put(:patch, lab_path(tab, at))
    end)
  end

  defp points(period) do
    prices = Map.fetch!(@prices, period)
    step = %{"1d" => 3 * 3600, "1w" => 86_400, "1m" => 3 * 86_400}[period]
    last = ~U[2026-11-12 12:00:00Z]

    prices
    |> Enum.with_index(1 - length(prices))
    |> Enum.map(fn {value, back} ->
      at = DateTime.add(last, back * step)

      %{
        at: at,
        value: value,
        figure: :erlang.float_to_binary(value, decimals: 2),
        time: Calendar.strftime(at, if(period == "1d", do: "%-d %b, %H:%M", else: "%-d %b"))
      }
    end)
  end

  defp first_steps(now) do
    [
      %{
        id: "s1",
        kind: :read,
        label: "Offers board",
        started_at: DateTime.add(now, -540),
        finished_at: DateTime.add(now, -500)
      },
      %{
        id: "s2",
        kind: :think,
        label: "Price check",
        started_at: DateTime.add(now, -500),
        finished_at: DateTime.add(now, -420)
      },
      %{
        id: "s3",
        kind: :tool,
        label: "Order list",
        started_at: DateTime.add(now, -420),
        finished_at: nil
      }
    ]
  end

  # The running step finishes and the next one starts.
  defp next_step(steps, now) do
    n = length(steps) + 1
    done = Enum.map(steps, fn step -> %{step | finished_at: step.finished_at || now} end)

    done ++
      [
        %{
          id: "s#{n}",
          kind: Enum.at(@kinds, rem(n, length(@kinds))),
          label: Enum.at(@labels, rem(n, length(@labels))),
          started_at: now,
          finished_at: nil
        }
      ]
  end
end
