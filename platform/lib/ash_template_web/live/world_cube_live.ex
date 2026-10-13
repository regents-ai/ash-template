defmodule AshTemplateWeb.WorldCubeLive do
  @moduledoc """
  The world cube, shown by itself: the example a site copies when it wants the
  cube on a page of its own. Nothing here reads or changes anything outside the
  page.
  """

  use AshTemplateWeb, :live_view

  alias AshTemplateWeb.Components.WorldCube

  # The six worlds, each behind the face whose room was drawn for it.
  @worlds [
    %{
      face: 0,
      name: "Autolaunch",
      line: "Where agents launch. Back one early, at auction.",
      href: "https://autolaunch.sh"
    },
    %{
      face: 5,
      name: "Keyfleet",
      line: "Where personal agents form lasting groups.",
      href: "https://keyfleet.ai"
    },
    %{
      face: 2,
      name: "Patchbay",
      line: "Where agents using websites ask, answer and share what worked.",
      href: "https://patchbay.help"
    },
    %{
      face: 1,
      name: "Techtree",
      line: "Open research, grown one branch at a time.",
      href: "https://techtree.sh"
    },
    %{
      face: 4,
      name: "Regents staking",
      line: "Stake REGENT and share in what the lab earns.",
      href: "https://regents.sh/stake"
    },
    %{
      face: 3,
      name: "Regents on X",
      line: "News from the lab, as it happens.",
      href: "https://x.com/regents_sh"
    }
  ]

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(AshTemplateWeb.PublicDocuments.page("/animations/cube"))
     |> assign(worlds: @worlds)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <main id="world-cube-lab" class="world-cube-lab">
      <header class="world-cube-lab__head">
        <p class="world-cube-lab__kicker">
          <a href={~p"/"}>Ash Template</a> / <a href={~p"/animations"}>Motion lab</a> / World cube
        </p>
        <h1>World cube</h1>
        <p>Six rooms in one cube. Turn it, rest on a side to bring it closer, click to step in.</p>
      </header>
      <WorldCube.cube id="world-cube" label="The six worlds" worlds={@worlds} />
    </main>
    """
  end
end
