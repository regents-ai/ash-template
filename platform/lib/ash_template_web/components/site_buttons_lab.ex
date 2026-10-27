defmodule AshTemplateWeb.SiteButtonsLab do
  @moduledoc """
  Each site's main button as it is today beside the template's motion, in that
  site's own colours. A local study: the presses play out on this page only.
  """
  use AshTemplateWeb, :html
  alias Phoenix.LiveView.JS
  alias Regent.Primitives, as: P

  # Words, steps and context come from each site's current page. A `nil` step is
  # one the site's button does not show today.
  @sites [
    %{
      id: "regents",
      number: "01",
      domain: "regents.sh",
      label: "Stake REGENT",
      place: "Staking page · Manage your stake",
      context: "Available 1,250.00 REGENT",
      waiting: %{
        today: ["Sign tx in wallet", "Confirming"],
        motion: ["Sign tx in wallet", "Confirming"]
      },
      done: %{today: nil, motion: "Staked"},
      unavailable: %{label: "Stake REGENT", reason: "No REGENT in this wallet.", today?: false}
    },
    %{
      id: "autolaunch",
      number: "02",
      domain: "autolaunch.sh",
      label: "Create the launch",
      place: "Create page · after Review launch",
      context: "Sending from your wallet on Base",
      waiting: %{today: ["Confirm in wallet"], motion: ["Confirm in wallet"]},
      done: %{today: nil, motion: "Launch created"},
      unavailable: %{label: "Complete token details and treasury", reason: nil, today?: true}
    },
    %{
      id: "techtree",
      number: "03",
      domain: "techtree.sh",
      label: "Copy",
      place: "Home · Paste into your agent's chat",
      context: "Help me test one of my Skills on Techtree.",
      waiting: %{today: [], motion: []},
      done: %{today: "Copied", motion: "Copied"},
      unavailable: %{label: "Copy", reason: "Nothing to copy yet.", today?: false}
    },
    %{
      id: "patchbay",
      number: "04",
      domain: "patchbay.sh",
      label: "Publish post",
      place: "Home · Your post, exactly as everyone will see it",
      context: "Anyone can read what you post here, under the name you chose.",
      waiting: %{today: [], motion: ["Publishing"]},
      done: %{today: nil, motion: "Published"},
      unavailable: %{label: "Publish post", reason: "Write something first.", today?: false}
    },
    %{
      id: "keyfleet",
      number: "05",
      domain: "keyfleet.ai",
      label: "Sign in",
      place: "Header · account",
      context: "Keyfleet",
      waiting: %{today: ["Sign in"], motion: ["Sign in"]},
      done: %{today: nil, motion: "Signed in"},
      unavailable: %{
        label: "Sign in",
        reason: "Sign-in isn't available right now. Reload this page.",
        today?: true
      }
    }
  ]

  @columns [{"today", "Today"}, {"motion", "With motion"}]

  @doc "Every site and column at rest."
  def initial,
    do: for(%{id: id} <- @sites, {col, _} <- @columns, into: %{}, do: {key(id, col), "idle"})

  @doc "The site ids this study shows."
  def site_ids, do: Enum.map(@sites, & &1.id)

  @doc """
  The steps a press walks through after the button answers, each with how long
  it stays. Every press starts again from the first, however far the last got.
  """
  def steps(id, col) do
    site = Enum.find(@sites, &(&1.id == id))
    col = String.to_existing_atom(col)

    waits =
      site.waiting[col] |> Enum.with_index() |> Enum.map(fn {_, i} -> {"wait#{i}", 1_400} end)

    done = if site.done[col], do: [{"done", 1_600}], else: []
    waits ++ done
  end

  def key(id, col), do: "#{id}:#{col}"

  attr :states, :map, required: true

  def content(assigns) do
    assigns = assign(assigns, sites: @sites, columns: @columns)

    ~H"""
    <section
      id="site-buttons"
      class="sb"
      aria-label="Site buttons"
      phx-hook="LabSiteButtons"
      phx-mounted={JS.ignore_attributes("data-input")}
    >
      <article
        :for={site <- @sites}
        id={"sb-#{site.id}"}
        class="sb-site"
        data-site={site.id}
        aria-labelledby={"sb-#{site.id}-title"}
      >
        <header class="sb-site-head">
          <span class="sb-index">{site.number} / {site.domain}</span>
          <h3 id={"sb-#{site.id}-title"}>{site.label}</h3>
          <p>{site.place}</p>
        </header>
        <div class="sb-compare">
          <section
            :for={{col, heading} <- @columns}
            class={["sb-col", "sb-#{col}"]}
            aria-label={"#{site.label}, #{String.downcase(heading)}"}
          >
            <h4>{heading}</h4>
            <div class={["sb-stage", col == "motion" && "sb-stage--lit"]}>
              <div
                :if={col == "motion"}
                id={"sb-light-#{site.id}"}
                class="sb-light-island"
                phx-hook="LabSiteLight"
                phx-update="ignore"
                phx-mounted={JS.ignore_attributes("data-light-ready")}
                data-state={@states[key(site.id, col)]}
                aria-hidden="true"
              >
                <canvas data-light-canvas></canvas>
              </div>
              <.context site={site}>
                <.site_button
                  site={site}
                  col={col}
                  state={@states[key(site.id, col)]}
                  phx-click="sb_press"
                  phx-value-site={site.id}
                  phx-value-col={col}
                  aria-busy={to_string(@states[key(site.id, col)] in ~w(wait0 wait1))}
                />
              </.context>
              <p class="sb-sr" role="status">{spoken(site, col, @states[key(site.id, col)])}</p>
            </div>
            <ul class="sb-specs" inert>
              <li :for={{show, state, caption} <- specimens()} data-show={show}>
                <span class="sb-spec-name">{caption}</span>
                <.specimen site={site} col={col} show={show} state={state} />
              </li>
            </ul>
          </section>
        </div>
      </article>

      <footer class="sb-notes">
        <strong>Quiet by design.</strong>
        Every press goes through at once, a second press while one is waiting included. Keyboard presses answer without movement, and the focus ring appears straight away. Nothing loops while a button sits still, and nothing celebrates money. Less motion keeps every state readable without movement.
      </footer>
    </section>
    """
  end

  # The specimens, frozen in each state: what to show, which words, and its caption.
  defp specimens do
    [
      {"rest", "idle", "Rest"},
      {"hover", "idle", "Hover"},
      {"press", "idle", "Press"},
      {"focus", "idle", "Keyboard focus"},
      {"unavailable", "idle", "Unavailable"},
      {"waiting", "wait0", "Waiting"},
      {"done", "done", "Done"}
    ]
  end

  attr :site, :map, required: true
  attr :col, :string, required: true
  attr :show, :string, required: true
  attr :state, :string, required: true

  defp specimen(%{show: "unavailable"} = assigns) do
    assigns = assign(assigns, :unavailable, assigns.site.unavailable)

    ~H"""
    <div class="sb-spec-body">
      <.site_button site={@site} col={@col} state="idle" label={@unavailable.label} disabled />
      <span :if={@unavailable.reason} class="sb-reason">{@unavailable.reason}</span>
      <span :if={!@unavailable.today?} class="sb-spec-note">Not used on this site today</span>
    </div>
    """
  end

  defp specimen(%{show: "waiting"} = assigns) do
    ~H"""
    <div class="sb-spec-body">
      <%= if @site.waiting[String.to_existing_atom(@col)] == [] do %>
        <span class="sb-spec-note">No waiting step</span>
      <% else %>
        <.site_button site={@site} col={@col} state="wait0" data-show="waiting" aria-busy="true" />
      <% end %>
    </div>
    """
  end

  defp specimen(%{show: "done"} = assigns) do
    ~H"""
    <div class="sb-spec-body">
      <%= if @site.done[String.to_existing_atom(@col)] do %>
        <.site_button site={@site} col={@col} state="done" data-show="done" />
      <% else %>
        <span class="sb-spec-note">Shown elsewhere on the page</span>
      <% end %>
    </div>
    """
  end

  defp specimen(assigns) do
    ~H"""
    <div class="sb-spec-body">
      <.site_button site={@site} col={@col} state={@state} data-show={@show} />
    </div>
    """
  end

  attr :site, :map, required: true
  slot :inner_block, required: true

  # The few things around the button on its own page, so it sits on its own ground.
  defp context(%{site: %{id: "techtree"}} = assigns) do
    ~H"""
    <div class="sb-context sb-context--panel">
      <div class="sb-panel-head">
        <span class="sb-panel-label">Paste into your agent's chat</span>
        {render_slot(@inner_block)}
      </div>
      <p>{@site.context}</p>
    </div>
    """
  end

  defp context(%{site: %{id: "keyfleet"}} = assigns) do
    ~H"""
    <div class="sb-context sb-context--header">
      <span class="sb-brand">{@site.context}</span>
      {render_slot(@inner_block)}
    </div>
    """
  end

  defp context(%{site: %{id: "patchbay"}} = assigns) do
    ~H"""
    <div class="sb-context sb-context--preview">
      <p class="sb-preview-post">Field notes from the first week of testing.</p>
      <p>{@site.context}</p>
      {render_slot(@inner_block)}
    </div>
    """
  end

  defp context(assigns) do
    ~H"""
    <div class="sb-context sb-context--form">
      {render_slot(@inner_block)}
      <p>{@site.context}</p>
    </div>
    """
  end

  attr :site, :map, required: true
  attr :col, :string, required: true
  attr :state, :string, required: true
  attr :label, :string, default: nil
  attr :rest, :global, include: ~w(disabled)

  # The words for every step sit in one cell, so the button keeps the width of
  # its widest step and only the showing one is read out. The motion kit plays a
  # press inline, which a state change mid-press must leave in place.
  defp site_button(assigns) do
    assigns =
      assign(assigns,
        waits: assigns.site.waiting[String.to_existing_atom(assigns.col)],
        done: assigns.site.done[String.to_existing_atom(assigns.col)],
        idle: assigns.label || assigns.site.label,
        motion?: assigns.col == "motion"
      )

    ~H"""
    <P.button
      class="sb-button"
      data-state={@state}
      phx-mounted={JS.ignore_attributes("style")}
      {@rest}
    >
      <span class="sb-words">
        <span data-word="idle" aria-hidden={to_string(@state != "idle")}>{@idle}</span>
        <span
          :for={{words, i} <- Enum.with_index(@waits)}
          data-word={"wait#{i}"}
          aria-hidden={to_string(@state != "wait#{i}")}
        >
          <span :if={words != @idle or @motion?} class="sb-spinner" aria-hidden="true"></span>{words}
        </span>
        <span :if={@done} data-word="done" aria-hidden={to_string(@state != "done")}>
          <span :if={@motion?} class="sb-tick" aria-hidden="true">✓</span>{@done}
        </span>
      </span>
    </P.button>
    """
  end

  defp spoken(_site, _col, "idle"), do: ""
  defp spoken(site, col, "done"), do: site.done[String.to_existing_atom(col)]

  defp spoken(site, col, "wait" <> i),
    do: Enum.at(site.waiting[String.to_existing_atom(col)], String.to_integer(i))
end
