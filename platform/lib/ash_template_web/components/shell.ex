defmodule AshTemplateWeb.Components.Shell do
  @moduledoc "The app shell: header, sidebar, account control and theme switch."

  use Phoenix.Component

  alias AshTemplateWeb.Components.RegentLinks

  attr :route_spec, :map, required: true
  attr :account_control, AshTemplate.AccessContext.AccountControl, required: true
  attr :shell_instance, :integer, required: true
  slot :content, required: true

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
          aria-controls="shell-sidebar"
          aria-expanded="false"
        >
          Menu
        </Regent.Primitives.button>

        <span class="shell-spacer" />
        <.theme_toggle id="theme-control" />
        <div class="rl-header-links">
          <RegentLinks.header_links id="shell-token-menu" />
        </div>

        <.account_control account_control={@account_control} />
      </header>

      <nav
        id="shell-sidebar"
        data-panel="drawer"
        aria-label="Context navigation"
        tabindex="-1"
      >
        <Regent.Primitives.button
          variant="quiet"
          type="button"
          class="shell-menu-close"
          data-shell-menu-close
        >
          Close navigation
        </Regent.Primitives.button>
        <ul>
          <li :for={target <- @route_spec.sidebar_model.targets}>
            <.sidebar_target target={target} route_spec={@route_spec} />
          </li>
        </ul>
      </nav>

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
        <main id="route-content">
          {render_slot(@content)}
        </main>
      </div>
    </div>
    """
  end

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
      <details :if={@account_control.kind == :signed_in} id="account-menu">
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
            <.account_menu_icon name={:settings} /><span>Account</span>
          </.link>
          <Regent.Primitives.button
            variant="quiet"
            type="button"
            disabled={!@enabled}
            class="account-menu__row account-menu__row--danger"
            data-account-menu-item="disconnect"
            data-account-target="sign-out"
          >
            <.account_menu_icon name={:logout} /><span>Disconnect</span>
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

  attr :target, :map, required: true
  attr :route_spec, :map, required: true

  defp sidebar_target(assigns) do
    ~H"""
    <.link
      patch={@target.path}
      aria-current={if @route_spec.destination == @target.path, do: "page"}
    >
      {@target.label}
    </.link>
    """
  end

  attr :name, :atom, required: true

  defp account_menu_icon(assigns) do
    ~H"""
    <svg
      class="account-menu__icon"
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      stroke-width="1.8"
      stroke-linecap="square"
      stroke-linejoin="miter"
      aria-hidden="true"
    >
      <g :if={@name == :settings}>
        <circle cx="12" cy="12" r="3" />
        <path d="M12 2v3M12 19v3M2 12h3M19 12h3M4.9 4.9 7 7M17 17l2.1 2.1M19.1 4.9 17 7M7 17l-2.1 2.1" />
      </g>
      <g :if={@name == :logout}>
        <path d="M10 4H4v16h6M14 8l4 4-4 4M8 12h10" />
      </g>
    </svg>
    """
  end
end
