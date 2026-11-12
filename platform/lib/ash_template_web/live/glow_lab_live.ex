defmodule AshTemplateWeb.GlowLabLive do
  @moduledoc """
  The glow: a soft light behind a status row, in that status's own colour.
  Three sample agents, one running, one waiting and one done, and a segmented
  choice of which row is lit.

  The light is one GPU picture behind the rows (the `GlowLight` hook, one canvas
  island). Each time the lit row changes it lives once: it slides to the row
  while its colour turns from the last status to this one, holds, then fades to
  an ember and rests. The rows are real text above it, so with less motion asked
  for, off screen, or without the picture they are simply flat and the lit row's
  name is the one in full ink. Nothing here reads or changes anything outside the
  page.
  """

  use AshTemplateWeb, :live_view

  alias AshTemplateWeb.PublicDocuments
  alias Regent.Primitives

  @rows [
    %{
      id: "running",
      name: "Pira",
      task: "Reading the offers board",
      tone: "info",
      status: "Running"
    },
    %{
      id: "waiting",
      name: "Odo",
      task: "Needs your approval",
      tone: "warning",
      status: "Waiting"
    },
    %{id: "done", name: "Vela", task: "Weekly note sent", tone: "success", status: "Done"}
  ]

  @ids Enum.map(@rows, & &1.id)

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(PublicDocuments.page(~p"/animations/glow"))
     |> assign(rows: @rows, lit: "running")}
  end

  @impl true
  def handle_event("light", %{"value" => id}, socket) when id in @ids,
    do: {:noreply, assign(socket, lit: id)}

  @impl true
  def render(assigns) do
    ~H"""
    <main id="glow-lab" class="motion-lab motion-lab--glow">
      <header class="motion-lab__head">
        <p class="motion-lab__kicker">
          <a href={~p"/"}>Ash Template</a> / <a href={~p"/animations"}>Motion lab</a> / Glow
        </p>
        <h1>Glow</h1>
      </header>

      <Primitives.segmented
        id="glow-choice"
        label="Lit row"
        name="lit"
        event="light"
        phx-hook="MotionTravel"
        options={for row <- @rows, do: %{value: row.id, label: row.status}}
        value={@lit}
      />

      <div
        id="glow-rows"
        class="glow-lab"
        phx-hook="GlowLight"
        phx-mounted={JS.ignore_attributes(["data-glow-ready"])}
        data-glow-lit={@lit}
      >
        <div id="glow-rows-stage" class="glow-lab__stage" phx-update="ignore" aria-hidden="true">
          <canvas data-glow-canvas></canvas>
        </div>

        <ul class="glow-lab__rows" aria-label="Agents">
          <li
            :for={row <- @rows}
            id={"glow-row-#{row.id}"}
            class="glow-row"
            data-glow-row={row.id}
            data-glow-tone={row.tone}
            aria-current={row.id == @lit && "true"}
          >
            <span class="glow-row__who">
              <span class="glow-row__name">{row.name}</span>
              <span class="glow-row__task">{row.task}</span>
            </span>
            <Primitives.status tone={row.tone}>{row.status}</Primitives.status>
          </li>
        </ul>
      </div>
    </main>
    """
  end
end
