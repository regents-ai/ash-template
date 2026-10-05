// The app shell's panels that the browser alone opens and closes: the right side
// bar, the section sidebar and the search dialog, with the dialog's highlight. Open and hidden states live
// on <html data-aside data-sidebar>, which the server first draws from the
// cookies written here (AshTemplateWeb.Plugs.Panels), so LiveView never patches
// them away.

const yearInSeconds = 60 * 60 * 24 * 365
const seenKey = "ash_template_aside_seen"

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

function seenDigest(): string | null {
  try {
    return window.localStorage.getItem(seenKey)
  } catch {
    return null
  }
}

function markSeen(digest: string) {
  try {
    window.localStorage.setItem(seenKey, digest)
  } catch {
    // Without storage the light simply pulses again on the next page.
  }
}

const root = () => document.documentElement
export const asideOpen = () => root().dataset.aside === "open"

/**
 * Wires the panels inside `shell`. Returns `sync`, to run after every LiveView
 * update, and `cleanup`.
 */
export function installShellPanels(shell: HTMLElement) {
  const aside = () => shell.querySelector<HTMLElement>("#shell-aside")
  const asideButton = () => shell.querySelector<HTMLButtonElement>("#shell-aside-button")
  const search = () => shell.querySelector<HTMLDialogElement>("#shell-search")
  const phone = () => window.matchMedia("(max-width: 47.99rem)").matches

  // The light pulses while the panel is closed and holds something the person
  // has not opened it to see; opening it, or having it open, marks it seen.
  const syncPulse = () => {
    const button = asideButton()
    const digest = button?.dataset.asideDigest
    if (!button || !digest) return
    if (asideOpen()) markSeen(digest)
    button.dataset.unseen = String(!asideOpen() && seenDigest() !== digest)
  }

  const syncAside = () => {
    const open = asideOpen()
    shell
      .querySelectorAll<HTMLButtonElement>("#shell-aside-button, [data-aside-part]")
      .forEach(button => button.setAttribute("aria-expanded", String(open)))
    syncPulse()
  }

  const setAside = (open: boolean, part?: string) => {
    const value = open ? "open" : "closed"
    root().dataset.aside = value
    remember("aside", value)
    syncAside()

    if (open && part) {
      const section = shell.querySelector<HTMLElement>(`#shell-aside-${part}`)
      section?.scrollIntoView({block: "start"})
      const heading = section?.querySelector<HTMLElement>("h3")
      if (heading) {
        heading.tabIndex = -1
        heading.focus({preventScroll: true})
      }
    } else if (open && phone()) {
      aside()?.focus()
    }
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

  const onClick = (event: MouseEvent) => {
    const target = event.target instanceof Element ? event.target : null
    if (!target) return

    const part = target.closest<HTMLElement>("[data-aside-part]")
    if (part) return setAside(true, part.dataset.asidePart)
    if (target.closest("#shell-aside-button")) return setAside(!asideOpen())
    if (target.closest("[data-aside-close]")) {
      setAside(false)
      return asideButton()?.focus()
    }
    if (target.closest("#shell-sidebar-button")) return setSidebar(false)
    if (target.closest("#shell-sidebar-show")) return setSidebar(true)
    if (target.closest("#shell-search-button")) return openSearch()
    if (target.closest("[data-search-close], [data-search-result]")) return closeSearch()
    // A press on the dialog's own backdrop lands on the dialog itself.
    if (target === search()) return closeSearch()
    // On a phone the side bar covers the page, so a page link inside it closes it.
    if (phone() && target.closest("#shell-aside a")) setAside(false)
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

  return {
    sync,
    cleanup: () => {
      shell.removeEventListener("click", onClick)
      shell.removeEventListener("pointermove", onPointerMove)
      document.removeEventListener("keydown", onKeydown)
    },
  }
}
