import type {Hook} from "../hook_composition"
import {deny} from "./motion/press"

type Outcome = "copied" | "failed"

const WORDS: Record<Outcome, string> = {copied: "Copied", failed: "Couldn't copy"}
const SHOWN_MS = 1600

type CopyTextHook = Hook & {
  el: HTMLElement
  outcome?: Outcome
  timer?: number
  onClick?: () => void
}

/**
 * The copy button from `Regent.Primitives.copy_button`. A press copies its
 * `data-copy-text`, then for a moment the button says "Copied", or "Couldn't
 * copy" with a shake when the browser refuses, and its polite status says the
 * same for screen readers. The page may redraw the button meanwhile, or
 * reconnect, so the answer is put back after every redraw until its moment is
 * over.
 */
export const CopyText: Hook = {
  mounted(this: CopyTextHook) {
    this.onClick = () => void copy(this)
    this.el.addEventListener("click", this.onClick)
  },

  updated(this: CopyTextHook) {
    show(this)
  },

  destroyed(this: CopyTextHook) {
    window.clearTimeout(this.timer)
    if (this.onClick) this.el.removeEventListener("click", this.onClick)
  },
}

async function copy(hook: CopyTextHook) {
  let outcome: Outcome = "copied"
  try {
    await navigator.clipboard.writeText(hook.el.dataset.copyText ?? "")
  } catch {
    outcome = "failed"
  }
  if (!hook.el.isConnected) return

  answer(hook, outcome)
  if (outcome === "failed") deny(hook.el)
  window.clearTimeout(hook.timer)
  hook.timer = window.setTimeout(() => answer(hook, undefined), SHOWN_MS)
}

function answer(hook: CopyTextHook, outcome: Outcome | undefined) {
  hook.outcome = outcome
  show(hook)
  const status = document.getElementById(hook.el.dataset.copyStatus ?? "")
  if (status) status.textContent = outcome ? WORDS[outcome] : ""
}

function show(hook: CopyTextHook) {
  if (hook.outcome) hook.el.dataset.copyState = hook.outcome
  else delete hook.el.dataset.copyState
}
