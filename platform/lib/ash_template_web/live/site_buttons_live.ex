defmodule AshTemplateWeb.SiteButtonsLive do
  @moduledoc """
  Each site's main button as it is today beside the template's motion, in that
  site's own colours. Every press plays out on this page only: no Ash action,
  account or outside write.
  """

  use AshTemplateWeb, :live_view

  alias AshTemplateWeb.SiteButtonsLab
  alias Regent.Primitives, as: P

  @sites SiteButtonsLab.site_ids()

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(AshTemplateWeb.PublicDocuments.page("/animations/buttons"))
     |> assign(reduced?: false, states: SiteButtonsLab.initial(), runs: %{})}
  end

  @impl true
  def handle_event("reduced", _, socket), do: {:noreply, update(socket, :reduced?, &(!&1))}

  # A press always starts its button's steps again, a press while it waits included.
  def handle_event("sb_press", %{"site" => site, "col" => col}, socket)
      when site in @sites and col in ~w(today motion) do
    key = SiteButtonsLab.key(site, col)
    {:noreply, step(socket, key, make_ref(), SiteButtonsLab.steps(site, col))}
  end

  # Only the newest press on a button moves it on; an older one's steps stop here.
  @impl true
  def handle_info({:site_button, key, run, steps}, socket) do
    if socket.assigns.runs[key] == run do
      {:noreply, step(socket, key, run, steps)}
    else
      {:noreply, socket}
    end
  end

  defp step(socket, key, run, []), do: show(socket, key, run, "idle")

  defp step(socket, key, run, [{state, ms} | rest]) do
    Process.send_after(self(), {:site_button, key, run, rest}, ms)
    show(socket, key, run, state)
  end

  defp show(socket, key, run, state) do
    socket
    |> update(:states, &Map.put(&1, key, state))
    |> update(:runs, &Map.put(&1, key, run))
  end

  @impl true
  def render(assigns) do
    ~H"""
    <main id="site-buttons-lab" class="motion-lab" data-motion={@reduced? && "reduced"}>
      <header class="motion-lab__head">
        <p class="motion-lab__kicker">
          <a href={~p"/"}>Ash Template</a> / <a href={~p"/animations"}>Motion lab</a> / Site buttons
        </p>
        <h1>Site buttons</h1>
        <p class="motion-lab__lede">
          Each site's main button, today on the left and with the template's motion on the right,
          in its own site's colours. Hover, press and tab through them. Every press plays out here
          and goes nowhere else.
        </p>
        <div class="motion-lab__row">
          <P.button variant="secondary" phx-click="reduced" aria-pressed={to_string(@reduced?)}>
            Less motion
          </P.button>
          <span class="sb-tag">Candidate · not a site default</span>
        </div>
      </header>
      <SiteButtonsLab.content states={@states} />
    </main>
    """
  end
end
