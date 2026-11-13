import {deny} from "./hooks/motion/press"
import {byPointer, fadeIn, still} from "./hooks/motion/shared"

type Outcome = "copied" | "selected" | "failed"

const WORDS: Record<Outcome, string> = {copied: "Copied", selected: "Selected", failed: "Couldn't copy"}
const SHOWN_MS = 1600

const timers = new WeakMap<HTMLElement, number>()

/**
 * Every `Regent.Primitives.copy_button` on every page, LiveView or not, from one
 * listener on the document. A press copies the button's `data-copy-text`, the
 * text of the element `data-copy-target` names, or the page at `data-copy-url`,
 * fetched only when pressed because it is long. Then for a moment the button
 * says "Copied", or "Couldn't copy" with a shake when the browser refuses, and
 * its polite status says the same for screen readers. When the browser refuses
 * and there is a target, the target's text is selected for the person to copy
 * themselves and the button says "Selected". "Copied" and "Selected" fade in
 * when a mouse or finger asked for them; from a key, and with less motion
 * asked for, they are simply there. The button tells LiveView to leave
 * `data-copy-state` alone, so a redraw meanwhile keeps the answer on screen.
 */
export function installCopyButtons() {
  document.addEventListener("click", event => {
    const button = event.target instanceof Element ? event.target.closest("button.rg-copy") : null
    if (button instanceof HTMLButtonElement) void copy(button, byPointer(event))
  })
}

async function copy(button: HTMLButtonElement, pointer: boolean) {
  const targetId = button.dataset.copyTarget
  const target = targetId ? document.getElementById(targetId) : null
  let outcome: Outcome = "copied"
  try {
    const url = button.dataset.copyUrl
    if (url) await navigator.clipboard.write([new ClipboardItem({"text/plain": fetched(url)})])
    else await navigator.clipboard.writeText(target ? textOf(target) : (button.dataset.copyText ?? ""))
  } catch {
    outcome = target ? select(target) : "failed"
  }
  if (!button.isConnected) return

  const changed = button.dataset.copyState !== outcome
  answer(button, outcome)
  if (outcome === "failed") deny(button)
  else if (changed && pointer && !still(button)) settle(button, outcome)
  window.clearTimeout(timers.get(button))
  timers.set(button, window.setTimeout(() => answer(button, undefined), SHOWN_MS))
}

// Handed to the clipboard unfinished: a browser only allows a write begun by the
// press itself, and the fetch finishes after it.
async function fetched(url: string): Promise<Blob> {
  const response = await fetch(url)
  if (!response.ok) throw new Error(`${url} answered ${response.status}`)
  return new Blob([await response.text()], {type: "text/plain"})
}

function textOf(target: HTMLElement): string {
  return target instanceof HTMLInputElement || target instanceof HTMLTextAreaElement
    ? target.value
    : (target.textContent ?? "")
}

// A field selects its own text; anything else, like a prompt shown on the page,
// is selected as a range.
function select(target: HTMLElement): Outcome {
  if (target instanceof HTMLInputElement || target instanceof HTMLTextAreaElement) {
    target.focus()
    target.select()
    return "selected"
  }

  const selection = document.getSelection()
  if (!selection) return "failed"
  const range = document.createRange()
  range.selectNodeContents(target)
  selection.removeAllRanges()
  selection.addRange(range)
  return "selected"
}

// The words variant only: a copy icon's tick stays a plain swap.
function settle(button: HTMLButtonElement, outcome: Outcome) {
  const word = button.querySelector(`.rg-copy__words > .rg-copy__${outcome}`)
  if (word) fadeIn(word)
}

function answer(button: HTMLButtonElement, outcome: Outcome | undefined) {
  if (outcome) button.dataset.copyState = outcome
  else delete button.dataset.copyState
  const status = document.getElementById(button.dataset.copyStatus ?? "")
  if (status) status.textContent = outcome ? WORDS[outcome] : ""
}
