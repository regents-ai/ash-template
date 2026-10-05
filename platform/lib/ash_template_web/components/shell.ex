defmodule AshTemplateWeb.Components.Shell do
  @moduledoc """
  The app shell: the top bar, the rail of sections, the open section's sidebar
  and tabs, the page, the right side bar and the bottom bar, plus the search
  dialog, the Regents apps menu, the account control and the theme switch.

  The panels' open and closed states are the browser's (`assets/js/shell_panels.ts`
  and the `ash_template_aside` and `ash_template_sidebar` cookies, read into
  `<html data-aside data-sidebar>`), so the server never stores them. A page puts its own parts
  into the sidebar and the right side bar with `<.portal>` into
  `#shell-sidebar-page` and `#shell-aside-page`.
  """

  use Phoenix.Component

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

  # The Regents Labs apps, each shown with the crown in its own pair of brand colours.
  @regents_apps [
    %{name: "Patchbay", url: "https://patchbay.help", tone: "patchbay"},
    %{name: "Autolaunch", url: "https://autolaunch.sh", tone: "autolaunch"},
    %{name: "KeyFleet", url: "https://keyfleet.ai", tone: "keyfleet"},
    %{name: "Techtree", url: "https://techtree.sh", tone: "techtree"},
    %{name: "Protocol", url: "https://regents.sh/stake", tone: "protocol"},
    %{name: "Account", url: "https://regents.sh/account", tone: "account"}
  ]

  attr :route_spec, :map, required: true
  attr :account_control, AshTemplate.AccessContext.AccountControl, required: true
  attr :shell_instance, :integer, required: true

  attr :checklist, :list,
    required: true,
    doc: "The Get started steps, each `%{id, label, path, done?}`."

  attr :unread, :integer, default: nil, doc: "Unread notifications; nil when signed out."
  attr :jobs_running, :integer, required: true
  attr :healthy, :boolean, required: true
  attr :version, :string, required: true
  attr :search, :map, required: true, doc: "`%{query, results}` for the search dialog."
  attr :assistant, :map, default: nil, doc: "The assistant box's last question and reply."
  slot :content, required: true

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
        <.link id="shell-brand" class="shell-brand" href="/">
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
          <.tool_button
            id="shell-help-button"
            label="Help"
            icon={:help}
            data-aside-part="help"
            aria-controls="shell-aside"
          />
          <.link id="shell-news-link" class="shell-tool" href="/changelog" aria-label="What's new">
            <.icon name={:news} /><span class="shell-tool__tip" aria-hidden="true">What's new</span>
          </.link>
          <.tool_button
            id="shell-assistant-button"
            label="Assistant"
            icon={:assistant}
            data-aside-part="assistant"
            aria-controls="shell-aside"
          />
          <.link
            :if={@unread}
            id="shell-bell"
            class="shell-tool"
            patch="/app/activity"
            aria-label={bell_label(@unread)}
          >
            <.icon name={:bell} />
            <span :if={@unread > 0} class="shell-tool__count" aria-hidden="true">
              {if @unread > 99, do: "99+", else: @unread}
            </span>
            <span class="shell-tool__tip" aria-hidden="true">Activity</span>
          </.link>
          <button
            id="shell-aside-button"
            class="shell-tool"
            type="button"
            aria-controls="shell-aside"
            aria-expanded="false"
            aria-label="Side panel"
            data-aside-digest={@aside_digest}
            phx-mounted={JS.ignore_attributes(["aria-expanded", "data-unseen"])}
          >
            <.icon name={:panel} />
            <span class="shell-pulse" aria-hidden="true"></span>
            <span class="shell-tool__tip" aria-hidden="true">Side panel</span>
          </button>
        </div>

        <.theme_toggle id="theme-control" />
        <div class="rl-header-links">
          <RegentLinks.header_links id="shell-token-menu" />
        </div>
        <.apps_menu />

        <.account_control account_control={@account_control} />
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

        <nav id="shell-rail" aria-label="Sections">
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
            patch="/account"
            class="shell-rail__you"
            aria-label={"Your profile, #{@account_control.label}"}
          >
            <img
              :if={@account_control.avatar_src}
              src={@account_control.avatar_src}
              referrerpolicy="no-referrer"
              width="32"
              height="32"
              alt=""
            />
            <span :if={!@account_control.avatar_src} aria-hidden="true">
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

      <aside id="shell-aside" aria-labelledby="shell-aside-title" tabindex="-1">
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

        <section class="shell-promo" aria-labelledby="shell-promo-title">
          <p class="shell-promo__kicker">New</p>
          <h3 id="shell-promo-title">Bring your agent</h3>
          <p>An agent with its own wallet can post in rooms as itself.</p>
          <a href="/docs">Read how in the documentation</a>
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
              <button
                :if={!step.done? and step.id == :sign_in}
                type="button"
                class="shell-checklist__action"
                data-account-target="sign-in"
              >
                {step.label}
              </button>
              <.link :if={!step.done? and step.id != :sign_in} patch={step.path}>
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
        <p class="shell-footer__jobs">
          {jobs_label(@jobs_running)}
        </p>
        <nav class="shell-footer__links" aria-label="Site links">
          <a :for={{label, path} <- footer_links()} href={path}>{label}</a>
        </nav>
        <p class="shell-footer__version">Version {@version}</p>
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
    </div>
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

  defp jobs_label(0), do: "No background jobs running"
  defp jobs_label(1), do: "1 background job running"
  defp jobs_label(count), do: "#{count} background jobs running"

  defp section_label(section),
    do: Enum.find_value(RouteCatalog.sections(), "Page", &(&1.id == section && &1.label))

  defp initials(label),
    do: label |> String.trim_leading("0x") |> String.slice(0, 2) |> String.upcase()

  @doc "The `data-account-target` a wallet button carries: connect once signed in, sign in before."
  def account_target(%{kind: :signed_in}), do: "connect-wallet"
  def account_target(_account_control), do: "sign-in"

  attr :account_control, AshTemplate.AccessContext.AccountControl, required: true
  attr :enabled, :boolean, default: true

  @doc """
  The account control. auth_lazy.ts drives its `data-account-target` markers;
  the component itself never authenticates anyone.
  """
  def account_control(assigns) do
    ~H"""
    <div id="account-control" class="account-control">
      <Regent.Primitives.button
        :if={@account_control.kind == :sign_in}
        type="button"
        data-account-target="sign-in"
        disabled={!@enabled}
      >
        {@account_control.label}
      </Regent.Primitives.button>
      <details :if={@account_control.kind in [:signed_in, :preview]} id="account-menu">
        <summary>
          <img
            :if={@account_control.avatar_src}
            class="account-avatar"
            src={@account_control.avatar_src}
            referrerpolicy="no-referrer"
            width="36"
            height="36"
            alt=""
          />
          <span data-account-target="profile">{@account_control.label}</span>
          <span class="shell-chevron" aria-hidden="true">⌄</span>
        </summary>
        <div class="account-menu__content shell-popover" data-panel="menu">
          <.link
            patch="/account"
            class="account-menu__row account-menu__row--account"
            data-account-menu-item="account"
          >
            <.icon name={:settings} class="account-menu__icon" /><span>Account</span>
          </.link>
          <Regent.Primitives.button
            variant="quiet"
            type="button"
            disabled={!@enabled}
            class="account-menu__row account-menu__row--danger"
            data-account-menu-item="disconnect"
            data-account-target="sign-out"
          >
            <.icon name={:logout} class="account-menu__icon" /><span>Disconnect</span>
          </Regent.Primitives.button>
        </div>
      </details>
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

  attr :id, :string, required: true
  attr :label, :string, required: true
  attr :icon, :atom, required: true
  attr :rest, :global

  defp tool_button(assigns) do
    ~H"""
    <button id={@id} class="shell-tool" type="button" aria-label={@label} {@rest}>
      <.icon name={@icon} /><span class="shell-tool__tip" aria-hidden="true">{@label}</span>
    </button>
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
      aria-label="Regents apps"
    >
      <.icon name={:apps} class="shell-icon shell-icon--apps" />
      <span class="shell-tool__tip" aria-hidden="true">Regents apps</span>
    </button>
    <nav id="shell-apps" class="shell-apps" popover aria-labelledby="shell-apps-title">
      <h2 id="shell-apps-title">Regents Labs apps</h2>
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
      <g :if={@name == :help}>
        <circle cx="12" cy="12" r="9" />
        <path d="M9.5 9.5a2.5 2.5 0 1 1 3.5 2.3c-.7.3-1 .9-1 1.7M12 17v.5" />
      </g>
      <path :if={@name == :news} d="M5 4h14v16H5zM8 8h8M8 12h8M8 16h5" />
      <path :if={@name == :page} d="M6 3h9l4 4v14H6zM14 3v5h5" />
      <path :if={@name == :action} d="M13 3 5 13h6l-1 8 8-10h-6z" />
      <g :if={@name == :assistant}>
        <path d="M5 8h14v10H5zM12 4v4M9 13v1M15 13v1" /><path d="M2 12v3M22 12v3" />
      </g>
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
