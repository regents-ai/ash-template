/**
 * The icon sheet (`AshTemplateWeb.IconsLabLive`): one canvas island behind every
 * cell of the sheet, drawing each cell's icon in the box the page leaves for it
 * (`[data-icon-art]`). The words are the page's own text; the picture only draws.
 *
 * Every icon plays its own loop. Pointing at a cell, or focusing it from the keyboard,
 * plays its icon at full strength and quiets the others a little. With less motion
 * asked for, by the device or by a Less motion switch round the sheet, each icon holds
 * one still frame. In forced colours the picture steps aside; without WebGPU the page
 * says the drawings need a newer browser.
 */
import {createCanvasIsland} from "../canvas_island"
import type {IconCell, IconSheetRenderer, SheetScene} from "../icon_sheet/renderer"
import {watchTheme} from "../theme"
import {colourReader} from "../token_colour"
import {still} from "./motion/shared"

export function createIconSheet(root: HTMLElement) {
  const canvas = root.querySelector<HTMLCanvasElement>("[data-icons-canvas]")!
  const cells = [...root.querySelectorAll<HTMLElement>("[data-icon]")]
  const readColour = colourReader()
  let boxes: IconCell[] | undefined
  let colours: SheetScene["colours"] | undefined
  let lit: string | undefined
  let calm = still(root)
  let draw = () => {}

  const readBoxes = (): IconCell[] => {
    const origin = canvas.getBoundingClientRect()
    return cells.map(cell => {
      const art = cell.querySelector<HTMLElement>("[data-icon-art]")!.getBoundingClientRect()
      return {id: cell.dataset.icon!, x: art.left - origin.left, y: art.top - origin.top, size: Math.min(art.width, art.height)}
    })
  }

  const readColours = (): SheetScene["colours"] => {
    const style = getComputedStyle(root)
    const token = (name: string) => readColour(style.getPropertyValue(name).trim())
    return {ink: token("--color-fg"), quiet: token("--color-fg-muted"), accent: token("--brand-accent"), ground: token("--color-bg")}
  }

  const scene = (): SheetScene => ({
    width: canvas.clientWidth,
    cells: (boxes ??= readBoxes()),
    lit,
    still: calm,
    colours: (colours ??= readColours()),
  })

  const moved = () => {
    boxes = undefined
    draw()
  }

  // The cell lit as the words light it: pointed at, or focused from the keyboard.
  let litFrame: number | undefined
  const readLit = () => {
    if (litFrame !== undefined) return
    litFrame = requestAnimationFrame(() => {
      litFrame = undefined
      lit = root.querySelector<HTMLElement>("[data-icon]:is(:hover, :focus-visible)")?.dataset.icon
      draw()
    })
  }

  const syncCalm = () => {
    calm = still(root)
    draw()
  }

  const island = createCanvasIsland<IconSheetRenderer>(root, {}, {
    canvasSelector: "[data-icons-canvas]",
    readyFlag: "iconsReady",
    // Less motion still gets the drawings, each held at its still frame.
    motionSensitive: false,
    continuous: true,
    maxDevicePixelRatio: 2,
    // A whole sheet of hairlines, drawn at the screen's own density on a laptop.
    maxDrawingBufferPixels: 7_000_000,
    browserLoad: async (view, size, lost) => {
      const {createIconSheetRenderer} = await import("../icon_sheet/renderer")
      return createIconSheetRenderer(view, size, lost)
    },
    interact: island => {
      draw = island.nudge
      island.onReady(() => island.renderer()!.show(scene))
      return () => {
        draw = () => {}
      }
    },
  })

  const reduced = matchMedia("(prefers-reduced-motion: reduce)")
  const forced = matchMedia("(forced-colors: active)")
  const syncForced = () => (forced.matches ? island.pause() : island.resume())
  const calmSwitch = new MutationObserver(syncCalm)
  const resized = new ResizeObserver(moved)
  const events = new AbortController()
  let stopWatchingTheme = () => {}

  return {
    mount() {
      calmSwitch.observe(document.documentElement, {subtree: true, attributes: true, attributeFilter: ["data-motion"]})
      reduced.addEventListener("change", syncCalm, {signal: events.signal})
      forced.addEventListener("change", syncForced, {signal: events.signal})
      for (const type of ["pointerover", "pointerout", "focusin", "focusout"]) {
        root.addEventListener(type, readLit, {signal: events.signal})
      }
      resized.observe(root)
      void document.fonts.ready.then(moved)
      stopWatchingTheme = watchTheme(() => {
        colours = undefined
        draw()
      })
      island.mount()
      if (forced.matches) island.pause()
    },
    pause() {
      island.pause()
    },
    resume() {
      if (!forced.matches) island.resume()
    },
    destroy() {
      events.abort()
      if (litFrame !== undefined) cancelAnimationFrame(litFrame)
      stopWatchingTheme()
      calmSwitch.disconnect()
      resized.disconnect()
      island.destroy()
    },
  }
}

type IconSheetHook = {el: HTMLElement; controller?: ReturnType<typeof createIconSheet>}

export const IconSheet = {
  mounted(this: IconSheetHook) {
    this.controller = createIconSheet(this.el)
    this.controller.mount()
  },
  disconnected(this: IconSheetHook) {
    this.controller?.pause()
  },
  reconnected(this: IconSheetHook) {
    this.controller?.resume()
  },
  destroyed(this: IconSheetHook) {
    this.controller?.destroy()
    this.controller = undefined
  },
}
