/**
 * The Cells meter's moving picture (`Regent.Cells.meter/1` from the design system),
 * drawn on the meter's own canvas behind its runs. The canvas is the bar and, above
 * it, `--rg-cells-headroom` of room that only the sparks rise into; the hook reads
 * that room once and draws the cells that far down. Put on the meter's root, it reads
 * everything from the page the meter draws: each part's key, start, share and
 * colour, whether the total is being counted, the measures of the cells and the
 * theme's colours. When the page changes them the picture moves from what it shows
 * to what the page now says (cells_meter/picture.ts).
 *
 * Once a frame has really drawn, the root carries `data-cells-ready="true"` and the
 * design system's CSS hides the still cells under it. With less motion asked for,
 * by the device or by a Less motion switch round the meter, in forced colours or
 * without WebGPU, the picture never starts and the still cells are the meter.
 */
import {createCanvasIsland} from "../canvas_island"
import type {CellsMeterRenderer} from "../cells_meter/renderer"
import type {MeterScene, Part} from "../cells_meter/picture"
import {watchTheme} from "../theme"
import {colourReader, type Rgb} from "../token_colour"
import {still} from "./motion/shared"

type Page = Omit<MeterScene, "width" | "headroom" | "lit">

export function createCellsMeter(root: HTMLElement) {
  const canvas = root.querySelector<HTMLCanvasElement>("[data-cells-canvas]")!
  const headroom = parseFloat(getComputedStyle(root).getPropertyValue("--rg-cells-headroom"))
  const readColour = colourReader()
  let page: Page | undefined
  let width = canvas.getBoundingClientRect().width
  let lit: ReadonlySet<string> = new Set()
  let draw = () => {}

  const readPage = (): Page => {
    const style = getComputedStyle(root)
    const measure = (name: string) => parseFloat(style.getPropertyValue(name))
    const parts = [...root.querySelectorAll<HTMLElement>("[data-cells-key]")].map(
      (part): Part => ({
        key: part.dataset.cellsKey!,
        start: Number(part.style.getPropertyValue("--rg-cells-start")),
        share: Number(part.style.getPropertyValue("--rg-cells-share")),
        colour: readColour(getComputedStyle(part).getPropertyValue("--rg-cells-color").trim()),
      }),
    )
    // The dim cells are see-through: their colour over black and over white gives its opacity.
    const dimCss = style.getPropertyValue("--rg-cells-dim").trim()
    const overBlack = readColour(dimCss, [0, 0, 0])
    const overWhite = readColour(dimCss, [1, 1, 1])
    const dimAlpha = 1 - (overWhite[0] - overBlack[0] + overWhite[1] - overBlack[1] + overWhite[2] - overBlack[2]) / 3
    const dim: Rgb = dimAlpha > 0 ? [overBlack[0] / dimAlpha, overBlack[1] / dimAlpha, overBlack[2] / dimAlpha] : [0, 0, 0]
    return {
      grid: {cell: measure("--rg-cells-cell"), gap: measure("--rg-cells-gap"), rows: measure("--rg-cells-rows")},
      parts,
      counting: root.dataset.cellsState === "counting",
      dim,
      dimAlpha,
      fg: readColour(style.getPropertyValue("--color-fg").trim()),
    }
  }

  const scene = (): MeterScene => {
    page ??= readPage()
    return {...page, width, headroom, lit}
  }

  const changed = () => {
    page = undefined
    draw()
  }

  // The parts lit as the still meter lights them: pointed at, or focused from the keyboard.
  let litFrame: number | undefined
  const readLit = () => {
    if (litFrame !== undefined) return
    litFrame = requestAnimationFrame(() => {
      litFrame = undefined
      lit = new Set(
        [...root.querySelectorAll<HTMLElement>("[data-cells-key]:is(:hover, :focus-visible)")].map(part => part.dataset.cellsKey!),
      )
      draw()
    })
  }

  const island = createCanvasIsland<CellsMeterRenderer>(root, {}, {
    canvasSelector: "[data-cells-canvas]",
    readyFlag: "cellsReady",
    motionSensitive: true,
    // The cells twinkle for as long as the meter is on screen.
    continuous: true,
    // Cells three CSS pixels square, on the same pixels as the still ones.
    maxDevicePixelRatio: 3,
    browserLoad: async (view, size, lost) => {
      const {createCellsMeterRenderer} = await import("../cells_meter/renderer")
      return createCellsMeterRenderer(view, size, lost)
    },
    interact: island => {
      draw = island.nudge
      island.onReady(() => island.renderer()!.show(scene))
      return () => {
        draw = () => {}
      }
    },
  })

  const reduced = window.matchMedia("(prefers-reduced-motion: reduce)")
  const forced = window.matchMedia("(forced-colors: active)")
  // A page's own Less motion switch (`data-motion="reduced"` round it) and forced
  // colours leave the still cells, as the device setting does. Letting the picture
  // go takes the ready flag away, so the still cells come back.
  let drawing = false
  const syncMotion = () => {
    const wanted = !still(root) && !forced.matches
    if (wanted === drawing) return
    drawing = wanted
    if (wanted) island.mount()
    else island.destroy()
  }
  const calm = new MutationObserver(syncMotion)
  const patched = new MutationObserver(changed)
  const resized = new ResizeObserver(([entry]) => {
    width = entry!.contentRect.width
    draw()
  })
  const events = new AbortController()
  let stopWatchingTheme = () => {}

  return {
    mount() {
      patched.observe(root, {
        subtree: true,
        childList: true,
        attributes: true,
        attributeFilter: ["style", "data-cells-key", "data-cells-state"],
      })
      calm.observe(document.documentElement, {subtree: true, attributes: true, attributeFilter: ["data-motion"]})
      for (const query of [reduced, forced]) query.addEventListener("change", syncMotion, {signal: events.signal})
      for (const type of ["pointerover", "pointerout", "focusin", "focusout"]) {
        root.addEventListener(type, readLit, {signal: events.signal})
      }
      resized.observe(canvas)
      stopWatchingTheme = watchTheme(changed)
      syncMotion()
    },
    pause() {
      island.pause()
    },
    resume() {
      island.resume()
    },
    destroy() {
      events.abort()
      if (litFrame !== undefined) cancelAnimationFrame(litFrame)
      stopWatchingTheme()
      calm.disconnect()
      patched.disconnect()
      resized.disconnect()
      island.destroy()
    },
  }
}

type CellsMeterHook = {el: HTMLElement; controller?: ReturnType<typeof createCellsMeter>}

export const CellsMeter = {
  mounted(this: CellsMeterHook) {
    this.controller = createCellsMeter(this.el)
    this.controller.mount()
  },
  disconnected(this: CellsMeterHook) {
    this.controller?.pause()
  },
  reconnected(this: CellsMeterHook) {
    this.controller?.resume()
  },
  destroyed(this: CellsMeterHook) {
    this.controller?.destroy()
    this.controller = undefined
  },
}
