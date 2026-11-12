defmodule AshTemplateWeb.MenuLabLive do
  @moduledoc """
  The menu: two buttons, one at each side of the page, each opening a short
  menu that grows from the corner it hangs from. A menu is the shared details
  dropdown (`rg-pill-select`), so Escape closes it and hands focus back to its
  button, and a press outside closes it. Opened by pointer it grows in with the
  standard menu motion; opened by keyboard, or with less motion asked for, it is
  simply there. Nothing here reads or changes anything outside the page.
  """

  use AshTemplateWeb, :live_view

  alias AshTemplateWeb.PublicDocuments

  @menus [
    %{
      id: "menu-lab-sort",
      side: "start",
      label: "Sort",
      items: ["Newest", "Oldest", "Most votes"]
    },
    %{id: "menu-lab-more", side: "end", label: "More", items: ["Rename", "Share", "Copy link"]}
  ]

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket |> assign(PublicDocuments.page(~p"/animations/menu")) |> assign(menus: @menus)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <main id="menu-lab" class="motion-lab motion-lab--menu">
      <header class="motion-lab__head">
        <p class="motion-lab__kicker">
          <a href={~p"/"}>Ash Template</a> / <a href={~p"/animations"}>Motion lab</a> / Menu
        </p>
        <h1>Menu</h1>
        <p class="motion-lab__lede">Each menu grows from its button.</p>
      </header>
      <div class="menu-lab">
        <details :for={menu <- @menus} id={menu.id} class="rg-pill-select menu-lab__menu">
          <summary>{menu.label}</summary>
          <div class={"menu-lab__items menu-lab__items--#{menu.side}"} data-panel="menu">
            <button
              :for={item <- menu.items}
              type="button"
              phx-click={JS.remove_attribute("open", to: "##{menu.id}")}
            >
              {item}
            </button>
          </div>
        </details>
      </div>
    </main>
    """
  end
end
