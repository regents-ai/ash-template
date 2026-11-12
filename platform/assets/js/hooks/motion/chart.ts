/**
 * The shared line chart (`Regent.Charts.line`): a rule and the words above the
 * chart follow the pointer, or Left and Right on the focused plot, from point
 * to point; when the period changes, the line morphs to its new shape. The
 * chart's table holds every point, so this reads nothing the page does not
 * show. The marks are the ones design-system's CONSUMERS.md lists.
 */
import {animate, svg} from "animejs"
import {BASE, EASE_IN_OUT, SLOW, play, still} from "./shared"
import type {Hook} from "../../hook_composition"

// The point, from 0, nearest a place across the chart (0 to 100).
export function nearest(across: number[], at: number) {
  let best = 0
  across.forEach((x, i) => { if (Math.abs(x - at) < Math.abs(across[best] - at)) best = i })
  return best
}

type Reading = {figure: string; time: string}

type ChartHook = {
  el: HTMLElement
  js(): {ignoreAttributes(el: HTMLElement, attrs: string[]): void}
  at?: number
  latest?: Reading
  lines?: (string | null)[]
  points?: number
  // The last press inside the chart was a key, such as an arrow on the period.
  byKey: boolean
  stop?: () => void
}

const points = (chart: HTMLElement) => [...chart.querySelectorAll<HTMLElement>("tr[data-chart-point]")]
const lines = (chart: HTMLElement) => [...chart.querySelectorAll<SVGPathElement>("path[data-chart-line]")]
const readout = (chart: HTMLElement, part: string) =>
  chart.querySelector<HTMLElement>(`[data-chart-readout='${part}']`)

const read = (chart: HTMLElement): Reading => ({
  figure: readout(chart, "figure")?.textContent ?? "",
  time: readout(chart, "time")?.textContent ?? "",
})

function write(chart: HTMLElement, reading: Reading) {
  const figure = readout(chart, "figure")
  const time = readout(chart, "time")
  if (figure) figure.textContent = reading.figure
  if (time) time.textContent = reading.time
}

// Shows point `index`: the rule at its place and its figure and time above.
function show(hook: ChartHook, index: number) {
  const point = points(hook.el)[index]
  if (!point) return
  if (hook.at === undefined) hook.latest = read(hook.el)
  hook.at = index
  hook.el.dataset.chartAt = String(index)
  hook.el.style.setProperty("--rg-chart-x", point.dataset.x ?? "0")
  write(hook.el, {
    figure: point.querySelector("td")?.textContent?.trim() ?? "",
    time: point.querySelector("th")?.textContent?.trim() ?? "",
  })
}

// Lets go: the rule goes and the latest figure comes back.
function release(hook: ChartHook) {
  if (hook.at === undefined) return
  hook.at = undefined
  delete hook.el.dataset.chartAt
  hook.el.style.removeProperty("--rg-chart-x")
  if (hook.latest) write(hook.el, hook.latest)
}

// The plot the pointer follows takes focus, so Left and Right step through the points.
function prepare(hook: ChartHook) {
  const plot = hook.el.querySelector<HTMLElement>("[data-chart-plot]")
  if (!plot) return
  plot.tabIndex = 0
  hook.js().ignoreAttributes(plot, ["tabindex"])
}

// A line whose points kept their count morphs to its new shape; one that
// gained or lost points fades in, as does the fill under it.
function redraw(hook: ChartHook, before: (string | null)[], count: number) {
  const same = points(hook.el).length === count
  const changed = lines(hook.el).filter((path, i) => before[i] !== path.getAttribute("d"))
  if (changed.length === 0) return
  lines(hook.el).forEach((path, i) => {
    const was = before[i]
    const now = path.getAttribute("d")
    if (!changed.includes(path)) return
    if (same && was && now) {
      const shape = document.createElementNS("http://www.w3.org/2000/svg", "path")
      shape.setAttribute("d", now)
      path.setAttribute("d", was)
      animate(path, {d: svg.morphTo(shape, 0), duration: SLOW, ease: EASE_IN_OUT})
    } else play(path, {opacity: {from: 0}, duration: BASE, ease: EASE_IN_OUT})
  })
  const fill = hook.el.querySelector(".rg-chart__fill")
  if (fill) play(fill, {opacity: {from: 0}, duration: SLOW, ease: EASE_IN_OUT})
}

/** On the chart, through `phx-hook`. */
export const MotionChart: Hook = {
  mounted(this: ChartHook) {
    const chart = this.el
    // The rule's place is this island's; a redraw from the server leaves it.
    this.js().ignoreAttributes(chart, ["style", "data-chart-at"])
    prepare(this)
    this.byKey = false

    const follow = (event: PointerEvent) => {
      const box = chart.querySelector(".rg-chart__lines")?.getBoundingClientRect()
      const inPlot = event.target instanceof Element && event.target.closest("[data-chart-plot]")
      if (!box || !inPlot) return release(this)
      const at = ((event.clientX - box.left) / box.width) * 100
      show(this, nearest(points(chart).map(point => Number(point.dataset.x)), at))
    }
    const leave = () => release(this)
    const press = () => { this.byKey = false }
    const focus = (event: FocusEvent) => {
      if (event.target instanceof Element && event.target.matches("[data-chart-plot]"))
        show(this, points(chart).length - 1)
    }
    const blur = (event: FocusEvent) => {
      if (event.target instanceof Element && event.target.matches("[data-chart-plot]")) release(this)
    }
    const key = (event: KeyboardEvent) => {
      this.byKey = true
      if (!(event.target instanceof Element) || !event.target.matches("[data-chart-plot]")) return
      const last = points(chart).length - 1
      const from = this.at ?? last
      const to = {ArrowLeft: from - 1, ArrowRight: from + 1, Home: 0, End: last}[event.key]
      if (to === undefined) return
      event.preventDefault()
      show(this, Math.min(last, Math.max(0, to)))
    }

    chart.addEventListener("pointermove", follow)
    chart.addEventListener("pointerleave", leave)
    chart.addEventListener("focusin", focus)
    chart.addEventListener("focusout", blur)
    chart.addEventListener("keydown", key)
    chart.addEventListener("pointerdown", press)
    this.stop = () => {
      chart.removeEventListener("pointermove", follow)
      chart.removeEventListener("pointerleave", leave)
      chart.removeEventListener("focusin", focus)
      chart.removeEventListener("focusout", blur)
      chart.removeEventListener("keydown", key)
      chart.removeEventListener("pointerdown", press)
    }
  },

  beforeUpdate(this: ChartHook) {
    this.lines = lines(this.el).map(path => path.getAttribute("d"))
    this.points = points(this.el).length
  },

  updated(this: ChartHook) {
    prepare(this)
    // The redraw put the server's latest figure back; keep it for letting go.
    if (this.at !== undefined) {
      const at = this.at
      this.latest = read(this.el)
      if (at < points(this.el).length) show(this, at)
      else release(this)
    }
    // A new period chosen from the keyboard is simply there.
    if (!this.byKey && !still(this.el)) redraw(this, this.lines ?? [], this.points ?? 0)
  },

  destroyed(this: ChartHook) {
    this.stop?.()
  },
}
