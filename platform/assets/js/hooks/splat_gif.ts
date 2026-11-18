/**
 * Download GIF for one splat scene's box (`AshTemplateWeb.Components.SplatStage.gif/1`,
 * which names the box in `data-splats-box`). A press makes a GIF of the scene the box is
 * drawing (`splats/gif.ts`, loaded on the first press) and saves it as
 * `regents-<scene>.gif`, after the box's `data-splats-scene`. Its page shows it only
 * once the scene has drawn; a press before the box has a renderer does nothing.
 *
 * While it works the button counts up in place, says so to a screen reader every
 * quarter, and a second press does nothing; a failure says so beside it. Choosing
 * another scene or leaving the page removes the control, which stops it and frees what
 * it held.
 */
import {rendererOf} from "./splat_island"

/** How long a saved GIF's address is kept for the browser to finish taking it (milliseconds). */
const SAVE_WINDOW = 60_000

const save = (bytes: Uint8Array<ArrayBuffer>, name: string) => {
  const link = document.createElement("a")
  link.href = URL.createObjectURL(new Blob([bytes], {type: "image/gif"}))
  link.download = name
  link.click()
  setTimeout(() => URL.revokeObjectURL(link.href), SAVE_WINDOW)
}

export function createSplatGif(control: HTMLElement) {
  const box = document.getElementById(control.dataset.splatsBox!)!
  const button = control.querySelector<HTMLButtonElement>("button")!
  const done = control.querySelector<HTMLElement>("[data-count]")!
  const status = control.querySelector<HTMLElement>("[role=status]")!
  const events = new AbortController()
  let making: AbortController | undefined

  const show = (state: "making" | "failed" | undefined, said: string) => {
    if (state) control.dataset.gif = state
    else delete control.dataset.gif
    button.setAttribute("aria-disabled", String(state === "making"))
    button.setAttribute("aria-busy", String(state === "making"))
    status.textContent = said
  }

  const make = async () => {
    const drawing = rendererOf(box)
    if (making || !drawing) return
    const current = new AbortController()
    making = current
    done.textContent = "0%"
    show("making", "Making the GIF")
    try {
      const {makeGif} = await import("../splats/gif")
      let quarter = 0
      const bytes = await makeGif(
        drawing.scene,
        share => {
          done.textContent = `${Math.floor(share * 100)}%`
          if (Math.floor(share * 4) > quarter && share < 1) {
            quarter = Math.floor(share * 4)
            status.textContent = `${quarter * 25}%`
          }
        },
        current.signal,
      )
      save(bytes, `regents-${box.dataset.splatsScene}.gif`)
      show(undefined, "Done")
    } catch (error) {
      if (current.signal.aborted) return
      console.warn("The GIF could not be made.", error)
      show("failed", "Could not make the GIF. Try again.")
    } finally {
      making = undefined
    }
  }

  return {
    mount() {
      button.addEventListener("click", () => void make(), {signal: events.signal})
    },
    destroy() {
      events.abort()
      making?.abort()
    },
  }
}

type SplatGifHook = {el: HTMLElement; controller?: ReturnType<typeof createSplatGif>}

export const SplatGif = {
  mounted(this: SplatGifHook) {
    this.controller = createSplatGif(this.el)
    this.controller.mount()
  },
  destroyed(this: SplatGifHook) {
    this.controller?.destroy()
    this.controller = undefined
  },
}
