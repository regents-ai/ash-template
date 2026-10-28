// The app shell's panels that the browser alone opens and closes: the section
// sidebar, the search dialog, with the dialog's highlight, and the Buy Credits
// dialog. Whether the sidebar shows lives on <html data-sidebar>, which the server
// first draws from the cookie written here (AshTemplateWeb.Plugs.Panels), so
// LiveView never patches it away. The account menu and the apps menu are popovers
// the browser opens and closes itself; only following a link inside one is ours.

const yearInSeconds = 60 * 60 * 24 * 365

// Shown is the server's default; only hidden is kept.
function rememberSidebar(value: "shown" | "hidden") {
  const secure = window.location.protocol === "https:" ? "; Secure" : ""
  const age = value === "hidden" ? yearInSeconds : 0
  document.cookie = `ash_template_sidebar=${value}; Path=/; Max-Age=${age}; SameSite=Lax${secure}`
}

const root = () => document.documentElement

/**
 * Brings `target`, what an address's #fragment names, into view. When it holds a
 * choice, such as the pairing box's agents, focus goes to the chosen one, or the
 * first, so the keyboard starts there. Returns whether it holds one.
 */
export function arriveAt(target: HTMLElement) {
  target.scrollIntoView()
  const choices = [...target.querySelectorAll<HTMLInputElement>("input[type=radio]")]
  const choice = choices.find(radio => radio.checked) ?? choices[0]
  // Next frame: following the link, and LiveView's patch, each move focus first.
  if (choice) requestAnimationFrame(() => choice.focus({preventScroll: true}))
  return choice !== undefined
}

/**
 * Wires the panels inside `shell`. Returns `sync`, to run after every LiveView
 * update, and `cleanup`.
 */
export function installShellPanels(shell: HTMLElement) {
  const search = () => shell.querySelector<HTMLDialogElement>("#shell-search")
  const credits = () => shell.querySelector<HTMLDialogElement>("#shell-credits")

  const setSidebar = (shown: boolean) => {
    const value = shown ? "shown" : "hidden"
    root().dataset.sidebar = value
    rememberSidebar(value)
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
    // A page change keeps an open menu open, so a link followed from one closes it.
    // A link to a #fragment of this page changes nothing LiveView sees when the
    // address already shows it, so what it names comes into view here, every press.
    const link = target.closest<HTMLAnchorElement>("a[href]")
    if (!link) return
    link.closest<HTMLElement>("[popover]")?.hidePopover()
    const named = link.hash && link.pathname === window.location.pathname
      ? document.getElementById(decodeURIComponent(link.hash.slice(1)))
      : null
    if (named) arriveAt(named)
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

  // A list the page put in the sidebar marks the page it is on, as the
  // server-drawn links do.
  const sync = () => {
    syncSearch()
    const destination = shell.dataset.destination
    shell.querySelectorAll<HTMLAnchorElement>("#shell-sidebar-page a[href]").forEach(link => {
      if (link.getAttribute("href") === destination) link.setAttribute("aria-current", "page")
      else link.removeAttribute("aria-current")
    })
  }

  sync()

  return {
    sync,
    cleanup: () => {
      shell.removeEventListener("click", onClick)
      shell.removeEventListener("pointermove", onPointerMove)
      document.removeEventListener("keydown", onKeydown)
    },
  }
}
