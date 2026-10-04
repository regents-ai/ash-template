import type {Hook} from "../hook_composition"

type ConversationHook = Hook & {
  el: HTMLElement
  handleEvent(event: string, callback: (payload: unknown) => void): void
  observer?: MutationObserver
  keydown?: (event: KeyboardEvent) => void
  submitted?: () => void
  pointerdown?: (event: PointerEvent) => void
}

// A message from the same person within five minutes of their last one sits
// under that one's name and picture.
const GROUP_SECONDS = 5 * 60

/**
 * One conversation: a chat room's, or a chat with the assistant. Marks each
 * message that continues the one before it (`data-continued`, kept through
 * patches by the message's `JS.ignore_attributes`), sends the message box with
 * Enter (Shift+Enter, and Enter on a touch screen, start a new line), shows the
 * newest message after a send, puts the cursor at the end of a message chosen
 * for editing once its text is in the box, and closes a message's menu on
 * Escape or a press anywhere else.
 */
export const Conversation: Hook = {
  mounted(this: ConversationHook) {
    const list = this.el.querySelector<HTMLElement>("[data-conversation-messages]")
    if (list) {
      group(list)
      this.observer = new MutationObserver(() => group(list))
      this.observer.observe(list, {childList: true})
    }

    this.keydown = event => {
      if (event.key === "Escape") closeMenus(this.el, null, true)
      const box = event.target
      if (!(box instanceof HTMLTextAreaElement) || !box.form || !this.el.contains(box)) return
      if (event.key !== "Enter" || event.shiftKey || event.isComposing) return
      if (window.matchMedia("(pointer: coarse)").matches) return
      event.preventDefault()
      box.form.requestSubmit()
    }
    this.el.addEventListener("keydown", this.keydown)

    // The newest message is at the bottom, which is where the list rests.
    this.submitted = () => {
      const scroller = this.el.querySelector<HTMLElement>("[data-conversation-scroller]")
      scroller?.scrollTo({top: scroller.scrollHeight})
    }
    this.el.addEventListener("submit", this.submitted)

    this.pointerdown = event => closeMenus(this.el, event.target as Node | null, false)
    document.addEventListener("pointerdown", this.pointerdown)

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
    if (this.pointerdown) document.removeEventListener("pointerdown", this.pointerdown)
  },
}

export function group(list: HTMLElement): void {
  let previous: HTMLElement | null = null
  for (const message of list.querySelectorAll<HTMLElement>(":scope > [data-author]")) {
    message.toggleAttribute("data-continued", continues(previous, message))
    previous = message
  }
}

// Closes every open message menu except the one `inside` falls in; on Escape,
// focus goes back to the menu's own button.
function closeMenus(root: HTMLElement, inside: Node | null, refocus: boolean): void {
  for (const menu of root.querySelectorAll<HTMLDetailsElement>("details.rooms-menu[open]")) {
    if (inside && menu.contains(inside)) continue
    menu.open = false
    if (refocus) menu.querySelector("summary")?.focus()
  }
}

function continues(previous: HTMLElement | null, message: HTMLElement): boolean {
  if (!previous || previous.dataset.author !== message.dataset.author) return false
  return Number(message.dataset.at) - Number(previous.dataset.at) < GROUP_SECONDS
}
