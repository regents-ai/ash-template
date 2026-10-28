// The app shell's panels that the browser alone opens and closes: the right side
// bar, the section sidebar, the search dialog, with the dialog's highlight, and
// the Buy Credits dialog. Open and hidden states live
// on <html data-aside data-sidebar>, which the server first draws from the
// cookies written here (AshTemplateWeb.Plugs.Panels), so LiveView never patches
// them away. On a phone, where the side panel covers the page, it opens only when
// the person opens it on that page (<html data-aside-here>), never from the
// remembered state.

const yearInSeconds = 60 * 60 * 24 * 365

type Panel = "aside" | "sidebar"
const cookies: Record<Panel, {name: string; kept: string}> = {
  aside: {name: "ash_template_aside", kept: "open"},
  sidebar: {name: "ash_template_sidebar", kept: "hidden"},
}

// The server's value is the default for each panel; only the other one is kept.
function remember(panel: Panel, value: string) {
  const {name, kept} = cookies[panel]
  const secure = window.location.protocol === "https:" ? "; Secure" : ""
  const age = value === kept ? yearInSeconds : 0
  document.cookie = `${name}=${value}; Path=/; Max-Age=${age}; SameSite=Lax${secure}`
}

const root = () => document.documentElement
const covering = window.matchMedia("(max-width: 47.99rem)")
export const asideOpen = () =>
  root().dataset.aside === "open" && (!covering.matches || root().dataset.asideHere !== undefined)

/**
 * Wires the panels inside `shell`. Returns `sync`, to run after every LiveView
 * update, and `cleanup`.
 */
export function installShellPanels(shell: HTMLElement) {
  const aside = () => shell.querySelector<HTMLElement>("#shell-aside")
  // Whichever of the two is showing: on a phone, the account's name.
  const asideButton = () =>
    [...shell.querySelectorAll<HTMLButtonElement>("[data-aside-toggle]")].find(toggle =>
      toggle.checkVisibility())
  const search = () => shell.querySelector<HTMLDialogElement>("#shell-search")
  const credits = () => shell.querySelector<HTMLDialogElement>("#shell-credits")

  // The side panel's own button and the account name in the header both open it.
  const syncAside = () => {
    shell.querySelectorAll("[data-aside-toggle]").forEach(toggle =>
      toggle.setAttribute("aria-expanded", String(asideOpen())))
  }

  const setAside = (open: boolean) => {
    const value = open ? "open" : "closed"
    root().dataset.aside = value
    if (open) root().dataset.asideHere = ""
    else delete root().dataset.asideHere
    remember("aside", value)
    syncAside()

    // Opened, focus moves into it, so Escape closes it and returns focus to the
    // button that opened it, and what it shows is read again.
    if (!open) return
    aside()?.focus()
    aside()
      ?.querySelectorAll("[data-read-on-open]")
      .forEach(reader => reader.dispatchEvent(new CustomEvent("ash:aside-opened")))
  }

  // Focus goes to the chosen agent, or the first, and its picture scrolls into view:
  // the radio itself is hidden, so focusing it does not move the panel.
  const openPairing = () => {
    setAside(true)
    const choices = [...shell.querySelectorAll<HTMLInputElement>("#shell-pairing input[type=radio]")]
    const choice = choices.find(radio => radio.checked) ?? choices[0]
    choice?.focus()
    choice?.closest("label")?.scrollIntoView({block: "nearest"})
  }

  const setSidebar = (shown: boolean) => {
    const value = shown ? "shown" : "hidden"
    root().dataset.sidebar = value
    remember("sidebar", value)
    const next = shown ? "#shell-sidebar-button" : "#shell-sidebar-show"
    shell.querySelector<HTMLButtonElement>(next)?.focus()
  }

  // Focus stays in the search field; the arrow keys move a highlight through
  // the results and Enter opens the highlighted one. The results the server
  // last drew name their query, and a new query starts again at the top.
  const searchInput = () => search()?.querySelector<HTMLInputElement>("#shell-search-input")
  const results = () => [...shell.querySelectorAll<HTMLAnchorElement>("[data-search-result]")]
  const highlighted = () => results().find(result => result.getAttribute("aria-selected") === "true")
  const drawnQuery = () => shell.querySelector<HTMLElement>("#shell-search-results")?.dataset.query
  let highlightedQuery: string | undefined

  const highlight = (result: HTMLAnchorElement | undefined) => {
    results().forEach(other => other.setAttribute("aria-selected", String(other === result)))
    if (result) {
      searchInput()?.setAttribute("aria-activedescendant", result.id)
      result.scrollIntoView({block: "nearest"})
    } else {
      searchInput()?.removeAttribute("aria-activedescendant")
    }
  }

  const syncSearch = () => {
    if (!search()?.open) return
    const query = drawnQuery()
    if (query !== highlightedQuery || !highlighted()) highlight(results()[0])
    highlightedQuery = query
  }

  const moveHighlight = (step: number) => {
    const all = results()
    if (all.length === 0) return
    const at = all.indexOf(highlighted() as HTMLAnchorElement)
    const next = at < 0 ? (step > 0 ? 0 : all.length - 1) : (at + step + all.length) % all.length
    highlight(all[next])
  }

  const openSearch = () => {
    const dialog = search()
    if (!dialog || dialog.open) return
    dialog.showModal()
    searchInput()?.select()
    highlightedQuery = undefined
    syncSearch()
  }

  const closeSearch = () => search()?.close()

  // Opening Buy Credits reads the wallet's funds again, so Buy is held back
  // only by what the chain says now.
  const openCredits = () => {
    const dialog = credits()
    if (!dialog || dialog.open) return
    dialog.showModal()
    dialog
      .querySelectorAll("[data-refresh-funds]")
      .forEach(panel => panel.dispatchEvent(new CustomEvent("ash:refresh-funds")))
  }

  const closeCredits = () => credits()?.close()

  const onClick = (event: MouseEvent) => {
    const target = event.target instanceof Element ? event.target : null
    if (!target) return

    if (target.closest("[data-aside-toggle]")) return setAside(!asideOpen())
    // A page's own Pair New Agent button opens the panel, leaves it open, and moves
    // to the agent choice, so a press with the panel already open still lands there.
    if (target.closest("[data-aside-open]")) return openPairing()
    if (target.closest("#shell-sidebar-button")) return setSidebar(false)
    if (target.closest("#shell-sidebar-show")) return setSidebar(true)
    if (target.closest("#shell-search-button")) return openSearch()
    // The header's balance, and a page's own Buy Credits button, open the one panel.
    if (target.closest("[data-credits-open]")) return openCredits()
    if (target.closest("[data-credits-close]")) return closeCredits()
    if (target === credits()) return closeCredits()
    if (target.closest("[data-search-close], [data-search-result]")) return closeSearch()
    // A press on the dialog's own backdrop lands on the dialog itself.
    if (target === search()) return closeSearch()
    // On a phone, where the side panel covers the page, a link inside it closes it.
    if (covering.matches && target.closest("#shell-aside a")) setAside(false)
  }

  const onKeydown = (event: KeyboardEvent) => {
    if ((event.metaKey || event.ctrlKey) && event.key.toLowerCase() === "k") {
      event.preventDefault()
      openSearch()
      return
    }

    if (search()?.open && event.target === searchInput()) {
      // A search field would spend Escape on clearing itself; here it closes.
      if (event.key === "Escape") {
        event.preventDefault()
        closeSearch()
        return
      }
      if (event.key === "ArrowDown" || event.key === "ArrowUp") {
        event.preventDefault()
        moveHighlight(event.key === "ArrowDown" ? 1 : -1)
        return
      }
      // Enter before the results for what was typed arrive searches instead.
      const current = drawnQuery() === searchInput()?.value.trim()
      if (event.key === "Enter" && !event.isComposing && current && highlighted()) {
        event.preventDefault()
        highlighted()?.click()
        return
      }
    }

    if (event.key === "Escape" && asideOpen() && aside()?.contains(document.activeElement)) {
      event.preventDefault()
      setAside(false)
      asideButton()?.focus()
    }
  }

  // The shortcut's name follows the keyboard: ⌘K on Apple devices, Ctrl K elsewhere.
  const keys = shell.querySelector<HTMLElement>("[data-shell-search-keys]")
  if (keys && /Mac|iPhone|iPad/.test(navigator.platform)) keys.textContent = "⌘K"

  // The pointer moves the highlight too, so Enter and a press agree.
  const onPointerMove = (event: PointerEvent) => {
    const target = event.target instanceof Element ? event.target : null
    const result = target?.closest<HTMLAnchorElement>("[data-search-result]")
    if (result && result !== highlighted()) highlight(result)
  }

  shell.addEventListener("click", onClick)
  shell.addEventListener("pointermove", onPointerMove)
  document.addEventListener("keydown", onKeydown)
  covering.addEventListener("change", syncAside)

  // A list the page put in the sidebar marks the page it is on, as the
  // server-drawn links do.
  const sync = () => {
    syncAside()
    syncSearch()
    const destination = shell.dataset.destination
    shell.querySelectorAll<HTMLAnchorElement>("#shell-sidebar-page a[href]").forEach(link => {
      if (link.getAttribute("href") === destination) link.setAttribute("aria-current", "page")
      else link.removeAttribute("aria-current")
    })
  }

  sync()

  // A link from a page without the panel, such as /agents' Pair New Agent, arrives
  // with the panel's section in its address and opens the panel on it.
  if (window.location.hash === "#shell-pairing" && shell.querySelector("#shell-pairing"))
    setAside(true)

  return {
    sync,
    cleanup: () => {
      shell.removeEventListener("click", onClick)
      shell.removeEventListener("pointermove", onPointerMove)
      document.removeEventListener("keydown", onKeydown)
      covering.removeEventListener("change", syncAside)
    },
  }
}
