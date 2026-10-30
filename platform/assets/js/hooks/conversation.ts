import type {Hook} from "../hook_composition"

type ConversationHook = Hook & {
  el: HTMLElement
  handleEvent(event: string, callback: (payload: unknown) => void): void
  observer?: MutationObserver
  keydown?: (event: KeyboardEvent) => void
  submitted?: () => void
  toggled?: (event: Event) => void
  pressed?: (event: Event) => void
  clicked?: () => void
  held?: Held
  back?: number | false
  pressing?: boolean
}

// The message whose menu is open, how far below the top of the list it is kept and
// where it last was, how far the reader's scrolling has moved the message since,
// and the list's scroll as last set or seen here. `stays` once the menu is closed by
// anything but a press or key: the reader scrolling its button away, or the page
// taking it off. `done` once the menu has closed or left the page; `closed` then
// hears how far the reader moved the message, or false when the list stays.
type Held = {
  message: HTMLElement
  menu: HTMLElement
  scroller: HTMLElement
  top: number
  at: number
  moved: number
  scrolled: number
  stays: boolean
  done: boolean
  closed: (moved: number | false) => void
  watch: IntersectionObserver
  resize: ResizeObserver
  scroll: () => void
}

// A message from the same person within five minutes of their last one sits
// under that one's name and picture.
const GROUP_SECONDS = 5 * 60

const presses = ["pointerdown", "pointerup", "keydown", "pointercancel", "contextmenu"]
const toggles = ["beforetoggle", "toggle"]

// A tip's words open while a mouse rests on its "i" and close when it leaves; they
// hold no choice to press, so a tip is not a menu here.
const openMenu = ":popover-open:not([role=tooltip])"

/**
 * One conversation: a chat room's, or a chat with the assistant. Marks each
 * message that continues the one before it (`data-continued`, kept through
 * patches by the message's `JS.ignore_attributes`), sends the message box with
 * Enter (Shift+Enter, and Enter on a touch screen, start a new line), shows the
 * newest message after a send, puts the cursor at the end of a message chosen
 * for editing once its text is in the box. A message's menu is the browser's
 * own pop-up, which closes itself on Escape or a press anywhere else. While it
 * is open, new messages arriving below leave its message where it is, so a
 * press lands on the choice the reader sees; once the reader scrolls the menu's
 * button out of the list, the menu closes. When the reader has closed the menus,
 * with a key or a press whose click has landed, the list goes back to the newest
 * message if it rested there before; closed any other way, it stays where it is.
 */
export const Conversation: Hook = {
  mounted(this: ConversationHook) {
    const list = this.el.querySelector<HTMLElement>("[data-conversation-messages]")
    const scroller = this.el.querySelector<HTMLElement>("[data-conversation-scroller]")
    if (list) {
      group(list)
      this.observer = new MutationObserver(() => group(list))
      this.observer.observe(list, {childList: true})
    }

    // `back`: false unless the list rested on its newest message when the first
    // menu opened (Chrome can leave it a pixel off after a hand scroll), and then
    // how far the reader has scrolled open menus' messages since; a phone settling
    // after a hand scroll moves one a few pixels, the reader's own scroll further.
    // A press closes a menu before its click lands, as when it opens another
    // message's menu, so while one is under way the list stays put. A press or key
    // that starts with no menu open leaves nothing to go back for. A choice closes
    // its menu before the menu's toggle event is heard, so the menu is let go first.
    const settle = () => {
      if (!scroller || this.pressing || scroller.querySelector(openMenu)) return
      if (this.held?.done === false) return release(this.held)
      if (typeof this.back === "number" && Math.abs(this.back) < 16) scroller.scrollTo({top: 0})
      this.back = undefined
    }
    const closed = (moved: number | false) => {
      if (moved === false) this.back = false
      else if (typeof this.back === "number") this.back += moved
      settle()
    }

    // A menu's message is held from just before the menu opens, so nothing arriving
    // in between moves it, and let go once it has closed. Neither event bubbles, so
    // both are heard on their way down. Any other pop-up opening while a menu is open,
    // such as a tip under a resting mouse, closes the menu with no press, and one a
    // press opens, such as a tip tapped on a phone, is what the reader turned to; either
    // way the list stays where it is.
    this.toggled = event => {
      const {target: menu, newState} = event as ToggleEvent
      if (!scroller || !(menu instanceof HTMLElement) || !menu.hasAttribute("popover")) return
      const message = this.el.contains(menu) && !menu.matches("[role=tooltip]") && menu.closest<HTMLElement>("[data-author]")
      if (!message) {
        if (event.type === "beforetoggle" && newState === "open" && (this.pressing || scroller.querySelector(openMenu))) this.back = false
        return
      }
      if (event.type === "beforetoggle" && newState === "open") {
        // Report's reasons open from inside the menu, which stays open.
        if (this.held?.done === false && this.held.message === message) return
        if (this.held) release(this.held)
        this.back ??= scroller.scrollTop > -2 && 0
        this.held = held(message, menu, scroller, closed)
      } else if (event.type === "toggle" && newState === "closed") {
        if (this.held?.message === message && !message.querySelector(openMenu)) release(this.held)
        settle()
      }
    }
    for (const type of toggles) document.addEventListener(type, this.toggled, {capture: true})

    // A press anywhere on the page closes a menu, and its click can land outside
    // the room, on what the press started and ended over; a press that turns into
    // a scroll or a context menu has no click, nor has one with another button. A
    // mouse's click, when there is one, comes as it lets go. A finger's or a pen's
    // comes a moment later and may be moved onto a button nearby, so the list waits
    // for it; a tap that has none, such as one on a disabled button or, on an
    // iPhone, on plain words, leaves the list where it is until the reader next
    // presses or uses a key.
    const ended = () =>
      setTimeout(() => {
        this.pressing = false
        settle()
      })
    this.pressed = event => {
      if (event.type === "pointerup") {
        if ((event as PointerEvent).pointerType === "mouse") ended()
        return
      }
      const start = event.type === "pointerdown" || event.type === "keydown"
      if (start && !scroller?.querySelector(openMenu)) this.back = undefined
      this.pressing = event.type === "pointerdown" && (event as PointerEvent).button === 0
      if (!this.pressing) settle()
    }
    // A button opens its menu once the click has been heard everywhere.
    this.clicked = ended
    for (const type of presses) document.addEventListener(type, this.pressed, {capture: true})
    document.addEventListener("click", this.clicked, {capture: true})

    this.keydown = event => {
      const box = event.target
      if (!(box instanceof HTMLTextAreaElement) || !box.form || !this.el.contains(box)) return
      if (event.key !== "Enter" || event.shiftKey || event.isComposing) return
      if (window.matchMedia("(pointer: coarse)").matches) return
      event.preventDefault()
      // Enter is Send, so it waits whenever Send does: while sending, and while the
      // page has no live connection (AshTemplateWeb.LiveConnection).
      if (box.form.querySelector("button[type=submit]")?.matches(":disabled")) return
      box.form.requestSubmit()
    }
    this.el.addEventListener("keydown", this.keydown)

    // The newest message is at the bottom, which is where the list rests: at 0, the
    // one place Chrome keeps the bottom in view as a message arrives. A pixel off,
    // as asking for the full height can leave a phone, it holds the messages above
    // in place and the one just sent lands out of view. An open menu would do the
    // same, keeping its message in place.
    this.submitted = () => {
      scroller?.querySelectorAll<HTMLElement>(openMenu).forEach(menu => menu.hidePopover())
      scroller?.scrollTo({top: 0})
    }
    this.el.addEventListener("submit", this.submitted)

    // Sent after the page holds the message's text, so focusing cannot keep the
    // box from receiving it.
    this.handleEvent("conversation:edit", () => {
      const box = this.el.querySelector<HTMLTextAreaElement>("form textarea")
      if (!box) return
      box.focus()
      box.setSelectionRange(box.value.length, box.value.length)
    })
  },

  destroyed(this: ConversationHook) {
    this.observer?.disconnect()
    if (this.keydown) this.el.removeEventListener("keydown", this.keydown)
    if (this.submitted) this.el.removeEventListener("submit", this.submitted)
    for (const type of toggles) if (this.toggled) document.removeEventListener(type, this.toggled, {capture: true})
    for (const type of presses) if (this.pressed) document.removeEventListener(type, this.pressed, {capture: true})
    if (this.clicked) document.removeEventListener("click", this.clicked, {capture: true})
    if (this.held) release(this.held)
  },
}

// Starts keeping `message` in place while its menu is open: whatever changes the
// list's height (a message arriving, a like or an edit on another) is undone by
// scrolling as much, before the browser draws it. The menu hangs from its button,
// so it closes once the button leaves the list, even with the rest of a tall
// message still in view. A scroll is the reader's when it isn't the one set here,
// and moves the place the message is kept to as far as the reader moved it. Chrome
// keeps what is in view in place as the list changes, scrolling as much, so there
// the reader moved the message as far as it moved; Safari does not, so a message
// arriving may have moved it too, and the reader moved it as far as the scroll.
function held(message: HTMLElement, menu: HTMLElement, scroller: HTMLElement, closed: (moved: number | false) => void): Held {
  const watch = new IntersectionObserver(
    entries => {
      if (!menu.isConnected) return gone(state)
      if (entries.at(-1)!.isIntersecting) return
      state.stays = true
      message.querySelectorAll<HTMLElement>(openMenu).forEach(menu => menu.hidePopover())
    },
    {root: scroller},
  )
  const resize = new ResizeObserver(() => hold(state))
  const top = offset(message, scroller)
  const state: Held = {
    message,
    menu,
    scroller,
    top,
    at: top,
    moved: 0,
    scrolled: scroller.scrollTop,
    stays: false,
    done: false,
    closed,
    watch,
    resize,
    scroll: () => {
      if (!menu.isConnected) return gone(state)
      if (scroller.scrollTop === state.scrolled) return
      const at = offset(message, scroller)
      const moved = getComputedStyle(scroller).overflowAnchor === "auto" ? at - state.at : state.scrolled - scroller.scrollTop
      state.scrolled = scroller.scrollTop
      state.moved += moved
      state.top += moved
      state.at = at
    },
  }
  // The menu hangs from its button.
  const button = message.querySelector<HTMLElement>(`[popovertarget="${menu.id}"]`)
  if (button) watch.observe(button)
  scroller.addEventListener("scroll", state.scroll, {passive: true})
  resize.observe(message.parentElement!)
  resize.observe(scroller)
  return state
}

// A menu gone from the page, with its message or alone, is let go. The message's
// place is measured from the top of the list, which a phone resizes as its address
// bar comes and goes, so a resize of the list itself is undone too. A scroll lands
// on whole screen pixels, so the message is kept to its place, not to where the
// last scroll left it, unless the list could scroll no further; the reader's next
// scroll is measured from where it left the message.
function hold(state: Held): void {
  if (!state.menu.isConnected) return gone(state)
  state.scroller.scrollTop += offset(state.message, state.scroller) - state.top
  state.scrolled = state.scroller.scrollTop
  state.at = offset(state.message, state.scroller)
  if (Math.abs(state.at - state.top) >= 1) state.top = state.at
}

const offset = (message: HTMLElement, scroller: HTMLElement) =>
  message.getBoundingClientRect().top - scroller.getBoundingClientRect().top

// A scroll the reader made just before is counted though its event hasn't come.
function release(state: Held): void {
  if (state.done) return
  if (state.menu.isConnected) state.scroll()
  state.done = true
  state.watch.disconnect()
  state.resize.disconnect()
  state.scroller.removeEventListener("scroll", state.scroll)
  state.closed(!state.stays && state.moved)
}

function gone(state: Held): void {
  state.stays = true
  release(state)
}

export function group(list: HTMLElement): void {
  let previous: HTMLElement | null = null
  for (const message of list.querySelectorAll<HTMLElement>(":scope > [data-author]")) {
    message.toggleAttribute("data-continued", continues(previous, message))
    previous = message
  }
}

function continues(previous: HTMLElement | null, message: HTMLElement): boolean {
  if (!previous || previous.dataset.author !== message.dataset.author) return false
  return Number(message.dataset.at) - Number(previous.dataset.at) < GROUP_SECONDS
}
