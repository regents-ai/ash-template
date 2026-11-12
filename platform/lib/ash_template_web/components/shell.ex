defmodule AshTemplateWeb.Components.Shell do
  @moduledoc """
  The app shell: the top bar, the rail of sections, the open section's sidebar
  and tabs, the page and the bottom bar, plus the search dialog, the list of tools
  agents see, the Regents Products menu, the account control and its menu, and the
  theme switch.

  Whether the sidebar shows is the browser's (`assets/js/shell_panels.ts` and the
  `ash_template_sidebar` cookie, read into `<html data-sidebar>`), so the server
  never stores it. A page puts its own parts into the sidebar with `<.portal>` into
  `#shell-sidebar-page`.

  Signed in, the account's picture and name at the top right open the account menu
  (`Regent.Account.menu`), the same on every page: the person's picture, name and
  wallet, the agents paired with the account (the `agents` slot), Pair New Agent,
  the theme switch, Manage Account and Sign out. Pair New Agent opens the pairing
  window (the `pairing_panel` slot) over the page; the agents are on the Agents
  page, and everything else about the account is on the Account page. Signed out,
  with no account menu, the theme switch sits in the bottom bar instead.
  """

  use Phoenix.Component
  use AshTemplateWeb, :verified_routes

  alias AshTemplateWeb.Components.AgentTools
  alias AshTemplateWeb.Components.RegentLinks
  alias AshTemplateWeb.RouteCatalog
  alias Phoenix.LiveView.JS

  @footer_links [
    {"Help", "/docs"},
    {"API", "/openapi.json"},
    {"Changelog", "/changelog"},
    {"For agents", "/llms.txt"},
    {"Privacy", "/privacy"},
    {"Terms", "/terms"}
  ]

  # The Regents Products, each shown with the crown and its name.
  @regents_apps [
    %{name: "Patchbay", url: "https://patchbay.help"},
    %{name: "Autolaunch", url: "https://autolaunch.sh"},
    %{name: "Techtree", url: "https://techtree.sh"},
    %{name: "Keyfleet", url: "https://keyfleet.ai"},
    %{name: "$REGENT Staking", url: "https://regents.sh/stake"}
  ]

  @doc "The Regents Products, in the order every menu of them lists them."
  def regents_products, do: @regents_apps

  attr :route_spec, :map, required: true
  attr :account_control, AshTemplate.AccessContext.AccountControl, required: true
  attr :shell_instance, :integer, required: true

  attr :unread, :integer, default: nil, doc: "Unread notifications; nil when signed out."

  attr :healthy, :boolean, required: true
  attr :search, :map, required: true, doc: "`%{query, results}` for the search dialog."
  slot :content, required: true

  # Required, so a page that draws the shell without one of these does not compile:
  # signed in, it would show a menu without agents or a Pair New Agent that opens
  # nothing. A caller leaves one out for someone signed out with `:if`.
  slot :agents, required: true, doc: "The agents paired with the account, in the account menu."

  slot :pairing_panel,
    required: true,
    doc: "The pairing window's box, opened by every Pair New Agent."

  def shell(assigns) do
    ~H"""
    <div
      id="app-shell"
      class="rg-sheet rg-frame"
      phx-hook="ShellBehavior"
      data-app={@route_spec.app_id}
      data-variant={AshTemplateWeb.Motion.standard("tabs")}
      data-background={@route_spec.background_slot}
      data-menu-open="false"
      data-route-id={@route_spec.route_id}
      data-destination={@route_spec.destination}
      data-shell-instance={@shell_instance}
    >
      <a class="shell-skip" href="#route-content">Skip to content</a>
      <header id="shell-header">
        <.link id="shell-brand" class="shell-brand" href="/" aria-label="Ash Template home">
          <span class="shell-brand__mark" aria-hidden="true">
            <img class="shell-brand__mark-light" src={~p"/images/brand/mark-flat-light.svg"} alt="" />
            <img class="shell-brand__mark-dark" src={~p"/images/brand/mark-flat-dark.svg"} alt="" />
          </span>
          <span class="shell-brand__name">Ash Template</span>
        </.link>

        <Regent.Primitives.button
          variant="quiet"
          id="mobile-menu-button"
          class="mobile-menu-button"
          type="button"
          aria-controls="shell-drawer"
          aria-expanded="false"
        >
          Menu
        </Regent.Primitives.button>

        <button
          id="shell-search-button"
          class="shell-search-button"
          type="button"
          aria-haspopup="dialog"
          aria-controls="shell-search"
          aria-label="Search"
          aria-keyshortcuts="Meta+K Control+K"
        >
          <Regent.Icons.icon name="search" class="shell-icon" />
          <span class="shell-search-button__label">Search</span>
          <kbd
            id="shell-search-keys"
            class="shell-search-button__keys"
            phx-update="ignore"
            data-shell-search-keys
          >
            Ctrl K
          </kbd>
        </button>

        <span class="shell-spacer" />

        <div class="shell-tools">
          <.link
            :if={@unread}
            id="shell-bell"
            class="shell-tool"
            patch={~p"/app/activity"}
            aria-label={bell_label(@unread)}
          >
            <Regent.Icons.icon name="bell" class="shell-icon" />
            <span :if={@unread > 0} class="shell-tool__count" aria-hidden="true">
              {if @unread > 99, do: "99+", else: @unread}
            </span>
            <span class="shell-tool__tip" aria-hidden="true">Activity</span>
          </.link>
        </div>

        <.apps_menu />

        <.account_control account_control={@account_control} />

        <Regent.Account.menu
          :if={@account_control.kind in [:signed_in, :preview]}
          id="account-menu"
          name={@account_control.label}
          wallet={@account_control.wallet}
          ens_name={@account_control.ens_name}
          manage_href={~p"/account"}
          pair_window="shell-pairing"
        >
          <:picture>
            <.account_picture
              id="account-menu-picture"
              squares={@account_control.squares}
              picture={@account_control.picture}
              size={40}
            />
          </:picture>
          <:agents>{render_slot(@agents)}</:agents>
          <:theme>
            <span class="shell-theme-label" aria-hidden="true">Light theme</span>
            <.theme_toggle id="account-menu-theme" />
          </:theme>
        </Regent.Account.menu>
      </header>

      <div id="shell-drawer" data-panel="drawer" tabindex="-1">
        <Regent.Primitives.button
          variant="quiet"
          type="button"
          class="shell-menu-close"
          data-shell-menu-close
          data-dismiss
        >
          Close navigation
        </Regent.Primitives.button>

        <nav id="shell-rail" aria-label="Sections" data-shell-nav>
          <ul>
            <li :for={section <- RouteCatalog.sections()}>
              <.link
                patch={section.path}
                class="shell-rail__section"
                aria-label={section.label}
                aria-current={@route_spec.section == section.id && "page"}
              >
                <Regent.Icons.icon name={section.icon} class="shell-icon" />
                <span class="shell-rail__label">{section.label}</span>
                <span class="shell-tool__tip" aria-hidden="true">{section.label}</span>
              </.link>
            </li>
          </ul>
          <.link
            :if={@account_control.kind in [:signed_in, :preview]}
            patch={~p"/account"}
            class="shell-rail__you"
            aria-label={"Your profile, #{@account_control.label}"}
          >
            <.account_picture
              id="shell-rail-picture"
              squares={@account_control.squares}
              picture={@account_control.picture}
              size={32}
            />
            <span :if={!@account_control.squares} aria-hidden="true">
              {initials(@account_control.label)}
            </span>
          </.link>
        </nav>

        <nav id="shell-sidebar" aria-labelledby="shell-sidebar-title">
          <div class="shell-sidebar__head">
            <h2 id="shell-sidebar-title">{@route_spec.sidebar_model.title}</h2>
            <button
              id="shell-sidebar-button"
              class="shell-tool"
              type="button"
              aria-controls="shell-sidebar"
              aria-label="Hide this list"
            >
              <Regent.Icons.icon name="panel-left-close" class="shell-icon" />
            </button>
          </div>
          <ul :if={@route_spec.sidebar_model.targets != []}>
            <li :for={target <- @route_spec.sidebar_model.targets}>
              <.target_link target={target} route_spec={@route_spec} />
            </li>
          </ul>
          <div id="shell-sidebar-page"></div>
        </nav>
      </div>

      <Regent.Primitives.button
        variant="quiet"
        type="button"
        class="shell-menu-scrim"
        data-shell-menu-scrim
        data-backdrop
        aria-label="Close navigation"
        hidden
      ></Regent.Primitives.button>

      <div id="app-shell-scroller" tabindex="-1">
        <button
          id="shell-sidebar-show"
          class="shell-sidebar-show"
          type="button"
          aria-controls="shell-sidebar"
        >
          <Regent.Icons.icon name="panel-left-open" class="shell-icon" />
          <span>Show {@route_spec.sidebar_model.title}</span>
        </button>
        <nav
          :if={@route_spec.tabs != []}
          id="shell-tabs"
          class="shell-tabs"
          data-shell-nav
          aria-label={"#{section_label(@route_spec.section)} views"}
        >
          <.link
            :for={tab <- @route_spec.tabs}
            patch={tab.path}
            aria-current={@route_spec.route_id == tab.route_id && "page"}
          >
            {tab.label}
          </.link>
        </nav>
        <main id="route-content">
          {render_slot(@content)}
        </main>
      </div>

      <footer id="shell-footer">
        <p class="shell-footer__status" data-healthy={to_string(@healthy)}>
          <span class="shell-footer__dot" aria-hidden="true"></span>
          {if @healthy, do: "All systems working", else: "Some things aren’t answering"}
        </p>
        <AgentTools.button id="shell-agent-tools-button" dialog="shell-agent-tools" />
        <nav class="shell-footer__links" aria-label="Site links">
          <a :for={{label, path} <- footer_links()} href={path}>{label}</a>
        </nav>
        <div class="shell-footer__brand rl-header-links">
          <RegentLinks.header_links id="shell-token-menu" />
        </div>
        <.theme_toggle
          :if={@account_control.kind not in [:signed_in, :preview]}
          id="shell-footer-theme-control"
          class="shell-footer-theme"
        />
      </footer>

      <Regent.Structure.dialog
        id="shell-search"
        class="shell-search"
        aria-label="Search"
        phx-mounted={JS.ignore_attributes(["open", "data-settled"])}
      >
        <form id="shell-search-form" role="search" phx-change="search" phx-submit="search">
          <Regent.Icons.icon name="search" class="shell-icon shell-search__glass" />
          <input
            id="shell-search-input"
            name="q"
            type="search"
            value={@search.query}
            role="combobox"
            aria-label="Search"
            aria-expanded="true"
            aria-controls="shell-search-results"
            aria-autocomplete="list"
            autocomplete="off"
            spellcheck="false"
            maxlength="100"
            phx-debounce="150"
            phx-mounted={JS.ignore_attributes(["aria-activedescendant"])}
            placeholder="Search pages, actions, notes and messages"
          />
          <button type="button" class="shell-search__close" data-search-close>
            <kbd class="shell-search__esc">Esc</kbd>
            <span class="shell-search__close-word">Close</span>
          </button>
        </form>
        <div
          id="shell-search-results"
          role="listbox"
          aria-label="Results"
          data-query={@search.query}
        >
          <div :if={@search.query != "" and @search.results == []} class="shell-search__empty">
            <Regent.Icons.icon name="search" class="shell-icon" />
            <p><strong>No results for “{@search.query}”</strong></p>
            <p>Try a page name, a note title or words from a room message.</p>
          </div>
          <section
            :for={{{group, items}, g} <- Enum.with_index(@search.results)}
            role="group"
            aria-labelledby={"shell-search-group-#{g}"}
          >
            <h3 id={"shell-search-group-#{g}"}>
              {group} <span class="shell-search__count">{length(items)}</span>
            </h3>
            <.link
              :for={{item, i} <- Enum.with_index(items)}
              id={"shell-search-result-#{g}-#{i}"}
              patch={item.live? && item.path}
              href={!item.live? && item.path}
              role="option"
              aria-selected="false"
              data-search-result
              phx-mounted={JS.ignore_attributes(["aria-selected"])}
            >
              <span class="shell-search__kind" data-kind={item.kind}>
                <Regent.Icons.icon name={kind_icon(item.kind)} class="shell-icon" />
              </span>
              <span class="shell-search__text">
                <span class="shell-search__label">{marked(item.label, @search.query)}</span>
                <span :if={item[:detail]} class="shell-search__detail">
                  {marked(item.detail, @search.query)}
                </span>
              </span>
              <kbd class="shell-search__enter" aria-hidden="true">↵</kbd>
            </.link>
          </section>
        </div>
        <p id="shell-search-status" class="visually-hidden" aria-live="polite">
          {result_count(@search)}
        </p>
        <footer class="shell-search__footer" aria-hidden="true">
          <span><kbd>↑</kbd><kbd>↓</kbd> Move</span>
          <span><kbd>↵</kbd> Open</span>
          <span><kbd>Esc</kbd> Close</span>
        </footer>
      </Regent.Structure.dialog>

      <Regent.Structure.dialog
        :if={@pairing_panel != []}
        id="shell-pairing"
        class="shell-pairing-dialog"
        aria-labelledby="shell-pairing-title"
        phx-mounted={JS.ignore_attributes(["open", "data-settled"])}
      >
        <Regent.Primitives.button
          variant="quiet"
          type="button"
          class="shell-dialog-close"
          aria-label="Close"
          data-pair-close
        >
          <Regent.Icons.icon name="x" />
        </Regent.Primitives.button>
        <h2 id="shell-pairing-title" data-sheet-handle>Pair New Agent</h2>
        {render_slot(@pairing_panel)}
      </Regent.Structure.dialog>

      <AgentTools.dialog id="shell-agent-tools" />
    </div>
    """
  end

  defp kind_icon(:page), do: "file"
  defp kind_icon(:action), do: "zap"
  defp kind_icon(:note), do: "file-text"
  defp kind_icon(:message), do: "message-square-text"

  defp result_count(%{query: ""}), do: ""

  defp result_count(%{results: results}) do
    case results |> Enum.map(fn {_group, items} -> length(items) end) |> Enum.sum() do
      0 -> "No results"
      1 -> "1 result"
      count -> "#{count} results"
    end
  end

  # The first place the query appears in `text` is marked.
  defp marked(text, ""), do: text

  defp marked(text, query) do
    case Regex.split(~r/#{Regex.escape(query)}/iu, text, parts: 2, include_captures: true) do
      [before, match, rest] ->
        {:safe, [escape(before), "<mark>", escape(match), "</mark>", escape(rest)]}

      [_unmatched] ->
        text
    end
  end

  defp escape(text), do: Phoenix.HTML.Engine.html_escape(text)

  defp footer_links, do: @footer_links

  defp bell_label(0), do: "Activity, nothing new"
  defp bell_label(1), do: "Activity, 1 new"
  defp bell_label(unread), do: "Activity, #{unread} new"

  defp section_label(section),
    do: Enum.find_value(RouteCatalog.sections(), "Page", &(&1.id == section && &1.label))

  defp initials(label),
    do: label |> String.trim_leading("0x") |> String.slice(0, 2) |> String.upcase()

  @doc "The `data-account-target` a wallet button carries: connect once signed in, sign in before."
  def account_target(%{kind: :signed_in}), do: "connect-wallet"
  def account_target(_account_control), do: "sign-in"

  attr :account_control, AshTemplate.AccessContext.AccountControl, required: true
  attr :enabled, :boolean, default: true

  attr :menu, :boolean,
    default: true,
    doc: """
    Signed in, the name opens the account menu, which holds Account and Sign out.
    A page without the menu (the workshop pages) shows Sign out beside the name.
    """

  @doc """
  The account control. auth_lazy.ts drives its `data-account-target` markers;
  the component itself never authenticates anyone.
  """
  def account_control(assigns) do
    ~H"""
    <div id="account-control" class="account-control" data-account-wallet={@account_control.wallet}>
      <Regent.Primitives.button
        :if={@account_control.kind == :sign_in}
        type="button"
        data-account-target="sign-in"
        disabled={!@enabled}
      >
        {@account_control.label}
      </Regent.Primitives.button>
      <Regent.Primitives.button
        :if={@menu and @account_control.kind in [:signed_in, :preview]}
        id="account-chip"
        class="account-chip"
        arrow={false}
        popovertarget="account-menu"
      >
        <.account_name id="account-chip-picture" account_control={@account_control} />
      </Regent.Primitives.button>
      <%= if !@menu and @account_control.kind in [:signed_in, :preview] do %>
        <span class="account-chip">
          <.account_name id="account-name-picture" account_control={@account_control} />
        </span>
        <Regent.Primitives.button
          variant="quiet"
          type="button"
          disabled={!@enabled}
          data-account-target="sign-out"
        >
          Sign out
        </Regent.Primitives.button>
      <% end %>
      <p
        id="account-auth-status"
        class="account-auth-status"
        role="status"
        aria-live="polite"
        aria-atomic="true"
        phx-update="ignore"
        hidden
      >
      </p>
    </div>
    """
  end

  attr :id, :string, required: true
  attr :account_control, AshTemplate.AccessContext.AccountControl, required: true

  # The account's picture and name. The `profile` marker tells the browser the
  # page was drawn for a signed-in account; the workshop's sample account has none.
  defp account_name(assigns) do
    ~H"""
    <.account_picture
      id={@id}
      class="account-avatar"
      squares={@account_control.squares}
      picture={@account_control.picture}
      size={36}
    />
    <span
      class="account-name"
      data-account-target={@account_control.kind == :signed_in && "profile"}
    >
      {@account_control.label}
    </span>
    """
  end

  attr :id, :string, required: true
  attr :squares, :string, required: true, doc: "`AshTemplate.PublicIdentity.squares/1`"
  attr :picture, :string, required: true, doc: "`AshTemplate.PublicIdentity.picture/1`"
  attr :size, :integer, required: true
  attr :class, :string, default: nil

  @doc """
  An account's picture, wherever it is shown. The squares drawn from its wallet are there as soon
  as the page is; its ENS picture, which arrives from another website, lies
  over them and takes their place once it has arrived (`AccountPicture` in
  `assets/js/hooks/account_picture.ts`). A changed picture is a new element,
  so the squares show again while it arrives. Nothing is drawn for an account
  with no wallet.
  """
  def account_picture(assigns) do
    ~H"""
    <span
      :if={@squares}
      id={"#{@id}-#{:erlang.phash2(@picture)}"}
      class={["account-picture", @class]}
      phx-hook={@picture && "AccountPicture"}
    >
      <img src={@squares} width={@size} height={@size} alt="" />
      <img
        :if={@picture}
        src={@picture}
        referrerpolicy="no-referrer"
        width={@size}
        height={@size}
        alt=""
      />
    </span>
    """
  end

  # The theme switch's two pictures, row by row from the top: "#" is a block. Both
  # have as many blocks, so every block of the moon flies to exactly one of the
  # sun, and both keep their outer ring clear, where a block would sit under the
  # glass's bevel and smear. The still face draws them, and the browser reads
  # them from there.
  @theme_moon [
    ".............",
    "....##.......",
    "...##.....#..",
    "..##.........",
    ".###.........",
    ".###.....#...",
    ".###.........",
    ".#####.......",
    ".######......",
    "..#########..",
    "...#######...",
    "....#####....",
    "............."
  ]

  @theme_sun [
    ".............",
    ".#....#....#.",
    "..#.......#..",
    ".....###.....",
    "....#####....",
    "...#######...",
    ".#.#######.#.",
    "...#######...",
    "....#####....",
    ".....###.....",
    "..#.......#..",
    ".#....#....#.",
    "............."
  ]

  block_count = fn rows ->
    rows |> Enum.join() |> String.graphemes() |> Enum.count(&(&1 == "#"))
  end

  if block_count.(@theme_moon) != block_count.(@theme_sun) do
    raise ArgumentError, "the theme switch's moon and sun need as many blocks"
  end

  for rows <- [@theme_moon, @theme_sun] do
    if Enum.any?(rows, &(String.length(&1) != length(rows))) do
      raise ArgumentError, "the theme switch's pictures are square"
    end

    ring = [hd(rows), List.last(rows) | Enum.map(rows, &(String.first(&1) <> String.last(&1)))]

    if Enum.any?(ring, &String.contains?(&1, "#")) do
      raise ArgumentError, "the theme switch's pictures keep their outer ring clear"
    end
  end

  attr :id, :string, required: true
  attr :class, :any, default: nil

  @doc """
  The light and dark theme switch: a button with the role of a switch, on for
  the light theme, with a knob that slides from night on the left to day on the
  right. A press, Enter or Space turns it, and the knob can be dragged; it
  settles on the nearer side when let go.

  The server draws a still face: a flat square track and knob with the moon or
  the sun, each a picture of tiny square blocks, placed for the theme showing. Once
  the browser has drawn a first frame of the glass knob, with the same blocks
  behind it and its light, on the canvas inside (`assets/js/hooks/theme_switch.ts`,
  `assets/js/theme_switch/`), that picture takes over. Without WebGPU, with Less
  motion on or in forced colours the still face stays, and it is a whole working
  switch on its own.

  The browser owns the press: it writes the theme cookie the server reads on
  the next render, so the switch is left out of LiveView's patching, and the
  attributes the browser writes on it are kept.
  """
  def theme_toggle(assigns) do
    assigns = assign(assigns, moon: @theme_moon, sun: @theme_sun)

    ~H"""
    <div
      id={@id}
      class={["theme-switch", @class]}
      phx-hook="ThemeSwitch"
      phx-update="ignore"
      phx-mounted={JS.ignore_attributes(["data-theme-switch-ready", "style"])}
      data-theme-switch
    >
      <button
        id={"#{@id}-button"}
        class="theme-switch__button"
        type="button"
        role="switch"
        aria-checked="false"
        aria-label="Light theme"
      >
        <span class="theme-switch__still" aria-hidden="true">
          <span class="theme-switch__track" data-theme-switch-track>
            <span class="theme-switch__knob" data-theme-switch-knob>
              <.theme_blocks rows={@moon} class="theme-switch__moon" />
              <.theme_blocks rows={@sun} class="theme-switch__sun" />
            </span>
          </span>
        </span>
        <canvas class="theme-switch__canvas" data-theme-switch-canvas aria-hidden="true"></canvas>
      </button>
    </div>
    """
  end

  attr :rows, :list, required: true
  attr :class, :string, required: true

  # One of the switch's pictures, a block for each "#", one unit square apiece
  # with a hairline between neighbours.
  defp theme_blocks(assigns) do
    assigns = assign(assigns, size: length(assigns.rows), blocks: blocks(assigns.rows))

    ~H"""
    <svg
      class={@class}
      viewBox={"0 0 #{@size} #{@size}"}
      shape-rendering="crispEdges"
      aria-hidden="true"
    >
      <g transform="translate(0.06 0.06)">
        <rect :for={{x, y} <- @blocks} x={x} y={y} width="0.88" height="0.88" />
      </g>
    </svg>
    """
  end

  defp blocks(rows) do
    for {row, y} <- Enum.with_index(rows),
        {"#", x} <- Enum.with_index(String.graphemes(row)),
        do: {x, y}
  end

  attr :target, :map, required: true
  attr :route_spec, :map, required: true

  defp target_link(assigns) do
    assigns = assign(assigns, :live?, RouteCatalog.live_path?(assigns.target.path))

    ~H"""
    <.link
      patch={@live? && @target.path}
      href={!@live? && @target.path}
      aria-current={@route_spec.destination == @target.path && "page"}
    >
      {@target.label}
    </.link>
    """
  end

  # The browser opens and closes the panel itself (`popover`), so it closes on
  # Escape or a press anywhere else, and a page update never shuts it.
  defp apps_menu(assigns) do
    assigns = assign(assigns, :apps, @regents_apps)

    ~H"""
    <button
      id="shell-apps-button"
      class="shell-tool"
      type="button"
      popovertarget="shell-apps"
      aria-label="Regents Products"
    >
      <Regent.Icons.icon name="grip" class="shell-icon shell-icon--apps" />
      <span class="shell-tool__tip" aria-hidden="true">Regents Products</span>
    </button>
    <nav id="shell-apps" class="shell-apps" popover aria-labelledby="shell-apps-title">
      <h2 id="shell-apps-title">Regents Products</h2>
      <ul>
        <li :for={app <- @apps}>
          <a href={app.url} target="_blank" rel="noopener">
            <span class="shell-apps__tile"><.crown /></span>
            <span>{app.name}</span>
          </a>
        </li>
      </ul>
    </nav>
    """
  end

  # The Regents crown: thirteen blocks, drawn in the current text colour.
  def crown(assigns) do
    ~H"""
    <svg class="shell-apps__crown" viewBox="31 46 178 106" fill="currentColor" aria-hidden="true">
      <rect :for={{x, y} <- crown_blocks()} x={x} y={y} width="34" height="34" />
    </svg>
    """
  end

  defp crown_blocks do
    top = for x <- [31, 103, 175], do: {x, 46}
    rows = for y <- [82, 118], x <- [31, 67, 103, 139, 175], do: {x, y}
    top ++ rows
  end
end
