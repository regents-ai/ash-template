defmodule AshTemplateWeb.Components.Shell do
  @moduledoc """
  The app shell: the top bar, the rail of sections, the open section's sidebar
  and tabs, the page, the right side bar and the bottom bar, plus the search
  dialog, the list of tools agents see, the Regents Products menu, the account
  control and the theme switch.

  The panels' open and closed states are the browser's (`assets/js/shell_panels.ts`
  and the `ash_template_aside` and `ash_template_sidebar` cookies, read into
  `<html data-aside data-sidebar>`), so the server never stores them. A page puts its own parts
  into the sidebar and the right side bar with `<.portal>` into
  `#shell-sidebar-page` and `#shell-aside-page`.

  The right side bar and its button are there only for someone signed in, so a
  page signed out has nothing beside the Sign in button. A page's part for the
  side bar is likewise drawn only for someone signed in.
  """

  use Phoenix.Component
  use AshTemplateWeb, :verified_routes

  alias AshTemplateWeb.Components.AgentTools
  alias AshTemplateWeb.Components.RegentLinks
  alias AshTemplateWeb.RouteCatalog
  alias Phoenix.LiveView.JS

  @help [
    {"Documentation", "/docs"},
    {"Agent guide", "/llms.txt"},
    {"What's new", "/changelog"},
    {"Contact", "/contact"}
  ]

  @footer_links [
    {"Help", "/docs"},
    {"API", "/openapi.json"},
    {"What's new", "/changelog"},
    {"For agents", "/llms.txt"},
    {"Privacy", "/privacy"},
    {"Terms", "/terms"}
  ]

  # The Regents Products, each shown with the crown in its own pair of brand colours.
  @regents_apps [
    %{name: "Patchbay", url: "https://patchbay.help", tone: "patchbay"},
    %{name: "Autolaunch", url: "https://autolaunch.sh", tone: "autolaunch"},
    %{name: "Keyfleet", url: "https://keyfleet.ai", tone: "keyfleet"},
    %{name: "Techtree", url: "https://techtree.sh", tone: "techtree"},
    %{name: "$REGENT Staking", url: "https://regents.sh/stake", tone: "protocol"},
    %{name: "Account", url: "https://regents.sh/account", tone: "account"}
  ]

  attr :route_spec, :map, required: true
  attr :account_control, AshTemplate.AccessContext.AccountControl, required: true
  attr :shell_instance, :integer, required: true

  attr :checklist, :list,
    required: true,
    doc: "The Get started steps, each `%{id, label, path, done?}`."

  attr :unread, :integer, default: nil, doc: "Unread notifications; nil when signed out."

  attr :credits, :map,
    default: nil,
    doc: "The account's Credits reading (`state` and `value`); nil when signed out."

  attr :healthy, :boolean, required: true
  attr :search, :map, required: true, doc: "`%{query, results}` for the search dialog."
  attr :assistant, :map, default: nil, doc: "The assistant box's last question and reply."
  attr :assistant_refused?, :boolean, default: false, doc: "The last question was not sent."
  slot :content, required: true
  slot :credits_panel, doc: "The Buy Credits panel, opened from the header's balance."

  def shell(assigns) do
    assigns = assign(assigns, :aside_digest, aside_digest(assigns.checklist))

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
            <img
              :for={tone <- ~w(light dark)}
              class={"shell-brand__mark-#{tone}"}
              src={"/images/brand/mark-flat-#{tone}.svg"}
              alt=""
            />
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
          <.icon name={:search} />
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
            <.icon name={:bell} />
            <span :if={@unread > 0} class="shell-tool__count" aria-hidden="true">
              {if @unread > 99, do: "99+", else: @unread}
            </span>
            <span class="shell-tool__tip" aria-hidden="true">Activity</span>
          </.link>
        </div>

        <.apps_menu />

        <button
          :if={@credits}
          id="shell-credits-button"
          class="shell-credits"
          type="button"
          aria-haspopup="dialog"
          aria-controls="shell-credits"
          aria-label={credits_label(@credits)}
          data-credits-open
          phx-hook="MotionCount"
          data-variant="flash"
        >
          <.credits_amount amount={@credits} />
        </button>

        <.account_control account_control={@account_control} />

        <button
          :if={@account_control.kind in [:signed_in, :preview]}
          id="shell-aside-button"
          class="shell-tool"
          type="button"
          aria-controls="shell-aside"
          aria-expanded="false"
          aria-label="Side panel"
          data-aside-toggle
          data-aside-digest={@aside_digest}
          phx-mounted={JS.ignore_attributes(["aria-expanded", "data-unseen"])}
        >
          <.icon name={:panel} />
          <span class="shell-pulse" aria-hidden="true"></span>
          <span class="shell-tool__tip" aria-hidden="true">Side panel</span>
        </button>
      </header>

      <div id="shell-drawer" data-panel="drawer" tabindex="-1">
        <Regent.Primitives.button
          variant="quiet"
          type="button"
          class="shell-menu-close"
          data-shell-menu-close
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
                <.icon name={section.icon} />
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
              <.icon name={:collapse} />
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
          <.icon name={:expand} />
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

      <aside
        :if={@account_control.kind in [:signed_in, :preview]}
        id="shell-aside"
        aria-labelledby="shell-aside-title"
        tabindex="-1"
      >
        <div class="shell-aside__head">
          <h2 id="shell-aside-title">For you</h2>
          <button
            class="shell-tool"
            type="button"
            aria-controls="shell-aside"
            aria-label="Close the side panel"
            data-aside-close
          >
            <.icon name={:close} />
          </button>
        </div>

        <section id="shell-account" class="shell-account" aria-label="Your account">
          <p class="shell-account__name">
            <.account_name id="shell-account-picture" account_control={@account_control} />
          </p>
          <div class="shell-account__actions">
            <.link patch={~p"/account"} class="rg-button rg-button--secondary">Account</.link>
            <Regent.Primitives.button
              variant="secondary"
              type="button"
              data-account-target="sign-out"
            >
              Sign out
            </Regent.Primitives.button>
          </div>
        </section>

        <section class="shell-promo" aria-labelledby="shell-promo-title">
          <p class="shell-promo__kicker">New</p>
          <h3 id="shell-promo-title">Pair your agent</h3>
          <.link navigate="/start">How it works</.link>
        </section>

        <section id="shell-checklist" aria-labelledby="shell-checklist-title">
          <h3 id="shell-checklist-title">Get started</h3>
          <p class="shell-checklist__count">
            {Enum.count(@checklist, & &1.done?)} of {length(@checklist)} done
          </p>
          <ol>
            <li :for={step <- @checklist} data-done={to_string(step.done?)}>
              <span class="shell-checklist__mark" aria-hidden="true">
                {if step.done?, do: "✓", else: ""}
              </span>
              <span :if={step.done?}>{step.label}<span class="visually-hidden">, done</span></span>
              <.link :if={!step.done?} patch={step.path}>
                {step.label}
              </.link>
            </li>
          </ol>
        </section>

        <div id="shell-aside-page"></div>

        <section id="shell-aside-assistant" aria-labelledby="shell-assistant-title">
          <h3 id="shell-assistant-title">Assistant</h3>
          <form
            :if={@account_control.kind == :signed_in}
            id="shell-assistant-form"
            class="shell-assistant__form"
            phx-submit="assistant_ask"
          >
            <label for="shell-assistant-input" class="visually-hidden">Ask the assistant</label>
            <input
              id="shell-assistant-input"
              name="text"
              type="text"
              maxlength="4000"
              autocomplete="off"
              placeholder="Ask the assistant"
              required
            />
            <Regent.Primitives.button type="submit" variant="secondary">Ask</Regent.Primitives.button>
          </form>
          <%!-- Always one line tall, so the reply below never moves. --%>
          <p
            :if={@account_control.kind == :signed_in}
            id="shell-assistant-note"
            class="shell-assistant__note"
            aria-live="polite"
          >
            {if @assistant_refused?, do: "Not sent. Wait a moment and try again."}
          </p>
          <p :if={@account_control.kind != :signed_in} class="rg-muted">
            Sign in to ask the assistant.
          </p>
          <div :if={@assistant} class="shell-assistant__exchange" aria-live="polite">
            <p class="shell-assistant__question">{@assistant.question}</p>
            <p :if={@assistant.reply == ""} class="rg-muted">The assistant is writing…</p>
            <p :if={@assistant.reply != ""} class="shell-assistant__reply">{@assistant.reply}</p>
            <.link patch={"/chat/#{@assistant.conversation_id}"}>Open in Chat</.link>
          </div>
        </section>

        <section id="shell-aside-help" aria-labelledby="shell-help-title">
          <h3 id="shell-help-title">Help</h3>
          <ul>
            <li :for={{label, path} <- help()}><a href={path}>{label}</a></li>
          </ul>
        </section>
      </aside>

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
        <.theme_toggle id="theme-control" />
      </footer>

      <dialog
        id="shell-search"
        class="shell-search"
        aria-label="Search"
        phx-mounted={JS.ignore_attributes(["open"])}
      >
        <form id="shell-search-form" role="search" phx-change="search" phx-submit="search">
          <.icon name={:search} class="shell-icon shell-search__glass" />
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
            <.icon name={:search} />
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
                <.icon name={kind_icon(item.kind)} />
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
      </dialog>

      <dialog
        :if={@credits_panel != []}
        id="shell-credits"
        class="shell-credits-dialog"
        aria-label="Buy Credits"
        phx-mounted={JS.ignore_attributes(["open"])}
      >
        <Regent.Primitives.button
          variant="quiet"
          type="button"
          class="shell-credits-dialog__close"
          aria-label="Close"
          data-credits-close
        >
          <svg viewBox="0 0 24 24" aria-hidden="true"><path d="M6 6l12 12M18 6L6 18" /></svg>
        </Regent.Primitives.button>
        {render_slot(@credits_panel)}
      </dialog>

      <AgentTools.dialog id="shell-agent-tools" />
    </div>
    """
  end

  defp credits_label(%{state: :ready, value: balance}),
    do: RegentCredits.Amount.format(balance.available)

  defp credits_label(%{state: state}) when state in [:error, :stale], do: "Credits unavailable"
  defp credits_label(_reading), do: "Credits loading"

  attr :amount, :map, required: true

  # "12.40 Credits", whose unit a phone's header leaves out for room. Only a
  # balance just read shows; while it is read again, or when it can't be, the
  # figure is a dash. The button and the Buy Credits panel behind it are there
  # either way.
  defp credits_amount(%{amount: %{state: :ready, value: balance}} = assigns) do
    [number, unit] = String.split(RegentCredits.Amount.format(balance.available), " ", parts: 2)
    assigns = assign(assigns, number: number, unit: unit)

    ~H"""
    <span data-count>{@number}</span> <span class="shell-credits__unit">{@unit}</span>
    """
  end

  defp credits_amount(assigns) do
    ~H"""
    <span data-count>—</span> <span class="shell-credits__unit">Credits</span>
    """
  end

  # The pulsing light names what the side panel holds; when that changes while
  # the panel is closed, the light pulses until the panel is opened.
  defp aside_digest(checklist),
    do: checklist |> Enum.map(&{&1.id, &1.done?}) |> :erlang.phash2() |> Integer.to_string(36)

  defp kind_icon(:page), do: :page
  defp kind_icon(:action), do: :action
  defp kind_icon(:note), do: :notes
  defp kind_icon(:message), do: :rooms

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

  defp help, do: @help
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

  attr :panel, :boolean,
    default: true,
    doc: """
    Signed in, the name opens the side panel, which holds Account and Sign out.
    A page without the side panel (the workshop pages) shows Sign out beside the name.
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
      <button
        :if={@panel and @account_control.kind in [:signed_in, :preview]}
        id="account-chip"
        class="account-chip"
        type="button"
        aria-controls="shell-aside"
        aria-expanded="false"
        data-aside-toggle
        phx-mounted={JS.ignore_attributes(["aria-expanded"])}
      >
        <.account_name id="account-chip-picture" account_control={@account_control} />
      </button>
      <%= if !@panel and @account_control.kind in [:signed_in, :preview] do %>
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

  attr :id, :string, required: true

  @doc """
  The colour theme switch. The browser owns the press: it writes the theme
  cookie the server reads on the next render, so the control is left out of
  LiveView's patching.
  """
  def theme_toggle(assigns) do
    ~H"""
    <div id={@id} class="theme-control" phx-update="ignore">
      <Regent.ThemeToggle.button id={"#{@id}-button"} data-theme-toggle />
    </div>
    """
  end

  attr :target, :map, required: true
  attr :route_spec, :map, required: true

  defp target_link(assigns) do
    assigns = assign(assigns, :live?, RouteCatalog.live?(assigns.target))

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
      <.icon name={:apps} class="shell-icon shell-icon--apps" />
      <span class="shell-tool__tip" aria-hidden="true">Regents Products</span>
    </button>
    <nav id="shell-apps" class="shell-apps" popover aria-labelledby="shell-apps-title">
      <h2 id="shell-apps-title">Regents Products</h2>
      <ul>
        <li :for={app <- @apps}>
          <a href={app.url} target="_blank" rel="noopener">
            <span class="shell-apps__tile" data-tone={app.tone}><.crown /></span>
            <span>{app.name}</span>
          </a>
        </li>
      </ul>
    </nav>
    """
  end

  # The Regents crown: thirteen blocks, drawn in the current text colour.
  defp crown(assigns) do
    ~H"""
    <svg class="shell-apps__crown" viewBox="31 46 178 106" fill="currentColor" aria-hidden="true">
      <rect :for={{x, y} <- crown_blocks()} x={x} y={y} width="34" height="34" />
    </svg>
    """
  end

  defp nine_dots, do: for(y <- [1.5, 9.75, 18], x <- [1.5, 9.75, 18], do: {x, y})

  defp crown_blocks do
    top = for x <- [31, 103, 175], do: {x, 46}
    rows = for y <- [82, 118], x <- [31, 67, 103, 139, 175], do: {x, y}
    top ++ rows
  end

  attr :name, :atom, required: true
  attr :class, :string, default: "shell-icon"

  defp icon(assigns) do
    ~H"""
    <svg
      class={@class}
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      stroke-width="1.8"
      stroke-linecap="square"
      stroke-linejoin="miter"
      aria-hidden="true"
    >
      <path :if={@name == :home} d="M4 11 12 4l8 7M6 9.5V20h12V9.5M10 20v-6h4v6" />
      <path :if={@name == :notes} d="M6 3h9l4 4v14H6zM14 3v5h5M9 12h7M9 16h7" />
      <path :if={@name == :rooms} d="M4 5h16v11H9l-5 4zM8 9h8M8 12h5" />
      <g :if={@name == :design}>
        <path d="M4 4h7v7H4zM17.5 13l3.5 7h-7z" /><circle cx="17.5" cy="7.5" r="3.5" />
        <path d="M4 14h7v6H4z" />
      </g>
      <path
        :if={@name == :chat}
        d="M12 3l1.8 4.7L18.5 9.5l-4.7 1.8L12 16l-1.8-4.7L5.5 9.5l4.7-1.8zM18 15l.9 2.1L21 18l-2.1.9L18 21l-.9-2.1L15 18l2.1-.9z"
      />
      <g :if={@name == :settings}>
        <circle cx="12" cy="12" r="3" />
        <path d="M12 2v3M12 19v3M2 12h3M19 12h3M4.9 4.9 7 7M17 17l2.1 2.1M19.1 4.9 17 7M7 17l-2.1 2.1" />
      </g>
      <path :if={@name == :logout} d="M10 4H4v16h6M14 8l4 4-4 4M8 12h10" />
      <g :if={@name == :search}><circle cx="10.5" cy="10.5" r="6" /><path d="m15 15 5 5" /></g>
      <path :if={@name == :page} d="M6 3h9l4 4v14H6zM14 3v5h5" />
      <path :if={@name == :action} d="M13 3 5 13h6l-1 8 8-10h-6z" />
      <path :if={@name == :bell} d="M6 17V11a6 6 0 0 1 12 0v6l2 2H4zM10 21h4" />
      <path :if={@name == :panel} d="M3 4h18v16H3zM15 4v16" />
      <path :if={@name == :collapse} d="M3 4h18v16H3zM9 4v16M15 10l-2 2 2 2" />
      <path :if={@name == :expand} d="M3 4h18v16H3zM9 4v16M13 10l2 2-2 2" />
      <path :if={@name == :close} d="M6 6l12 12M18 6 6 18" />
      <g :if={@name == :apps} fill="currentColor" stroke="none">
        <rect :for={{x, y} <- nine_dots()} x={x} y={y} width="4.5" height="4.5" />
      </g>
    </svg>
    """
  end
end
