import {CONTROL_REQUEST_EVENT, CONTROL_STATE_EVENT, type ControlOutcome} from "../auth_lazy"
import type {Hook} from "../hook_composition"

type SiwaControlHook = {
  el: HTMLElement
  handleEvent(event: string, callback: (payload: {key?: unknown}) => void): void
  pushEventTo(target: HTMLElement, event: string, payload: unknown): void
  stop?: () => void
}

// The SIWA pages (AshTemplateWeb.SiwaLive). When the page needs its control
// token traded again, the sign-in bridge the page already loaded makes the
// trade, and the page hears how it went. A new site key arrives here once and
// goes only into its box on the page.
export const SiwaControl: Hook = {
  mounted(this: SiwaControlHook) {
    const traded = (event: Event) => {
      const outcome = (event as CustomEvent<ControlOutcome>).detail
      this.pushEventTo(this.el, "traded", {outcome})
    }
    window.addEventListener(CONTROL_STATE_EVENT, traded)
    this.stop = () => window.removeEventListener(CONTROL_STATE_EVENT, traded)

    this.handleEvent("siwa-control:trade", () => {
      window.dispatchEvent(new Event(CONTROL_REQUEST_EVENT))
    })
    this.handleEvent("siwa-key:reveal", ({key}) => {
      const box = document.getElementById("siwa-key-value")
      if (box && typeof key === "string") box.textContent = key
    })
  },

  destroyed(this: SiwaControlHook) {
    this.stop?.()
  },
}
