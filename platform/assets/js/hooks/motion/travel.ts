/**
 * The shared segmented control and link tabs (`Regent.Primitives.segmented` and
 * `tabs`, both marked `data-travel`): the mark on the chosen one travels to the
 * new choice. The design system slides the segmented indicator in CSS and draws
 * the tab's bar still; this moves both the way design-system's CONSUMERS.md
 * describes, and hands them back to the stylesheet when they arrive. A choice
 * made from the keyboard, or with less motion asked for, is simply there.
 */
import {animate, spring, utils, type JSAnimation} from "animejs"
import {EASE_IN_OUT, FAST, SLOW, byPointer, lastInputByPointer, still} from "./shared"
import type {Hook} from "../../hook_composition"

// The leading edge springs as the design system names it; the trailing edge
// sets off half a fast step later, so the indicator stretches towards the new
// cell before it lets go of the old one.
export const TRAVEL = {ease: spring({bounce: 0.15, duration: 300}), trail: FAST / 2}

const START = "--rg-travel-start"
const END = "--rg-travel-end"

// The cell, from 0, that a point `x` px from the control's start falls in.
export const cellAt = (x: number, width: number, cells: number) =>
  Math.min(cells - 1, Math.max(0, Math.floor((x / width) * cells)))

// Which edge leads and where each lands, in cells: going forward the end
// leads, going back the start does.
export function edges(from: number, to: number) {
  const start = {edge: START, at: to}
  const end = {edge: END, at: to + 1}
  return to > from ? {lead: end, trail: start} : {lead: start, trail: end}
}

type TravelHook = {
  el: HTMLElement
  js(): {ignoreAttributes(el: HTMLElement, attrs: string[]): void}
  stop?: () => void
  arrive?: () => void
}

/**
 * On a segmented control or a row of link tabs, through `phx-hook`. Both are
 * the design system's own markup; this needs nothing else from the page.
 */
export const MotionTravel: Hook = {
  mounted(this: TravelHook) {
    const indicator = this.el.querySelector<HTMLElement>("[data-travel-indicator]")
    if (indicator) this.stop = segmented(this, indicator)
    else {
      const tabs = linkTabs(this)
      this.arrive = tabs.arrive
      this.stop = tabs.stop
      tabs.arrive()
    }
  },

  updated(this: TravelHook) {
    this.arrive?.()
  },

  destroyed(this: TravelHook) {
    this.stop?.()
  },
}

function segmented(hook: TravelHook, indicator: HTMLElement) {
  const control = hook.el
  const inputs = () => [...control.querySelectorAll<HTMLInputElement>("input[type='radio']")]
  const checked = () => inputs().findIndex(input => input.checked)
  const rtl = getComputedStyle(control).direction === "rtl"
  const cellUnder = (event: PointerEvent) => {
    const box = control.getBoundingClientRect()
    return cellAt(rtl ? box.right - event.clientX : event.clientX - box.left, box.width, inputs().length)
  }

  // The indicator's place and the control's mark are this island's while it
  // moves them, so a redraw from the server leaves them be.
  hook.js().ignoreAttributes(indicator, ["style"])
  hook.js().ignoreAttributes(control, ["data-travel"])

  let shown = checked()
  let pressed: number | null = null
  let moving: JSAnimation | null = null

  // Back to the stylesheet, which already puts the indicator on the checked cell.
  const rest = () => {
    moving = null
    shown = checked()
    indicator.style.removeProperty(START)
    indicator.style.removeProperty(END)
    control.dataset.travel = ""
  }
  const settle = () => { if (moving === null || moving.completed) rest() }

  const go = (to: number) => {
    if (to === shown) return
    const from = shown
    shown = to
    if (control.dataset.travel !== "kit") utils.set(indicator, {[START]: from, [END]: from + 1})
    control.dataset.travel = "kit"
    const {lead, trail} = edges(from, to)
    animate(indicator, {[lead.edge]: lead.at, ease: TRAVEL.ease})
    const run: JSAnimation = animate(indicator, {
      [trail.edge]: trail.at,
      ease: TRAVEL.ease,
      delay: TRAVEL.trail,
      onComplete: () => { if (moving === run && pressed === null && shown === checked()) rest() },
    })
    moving = run
  }

  const down = (event: PointerEvent) => {
    if (!event.isPrimary || event.button !== 0 || still(control)) return
    pressed = cellUnder(event)
  }
  // A press dragged across the cells carries the indicator with it.
  const move = (event: PointerEvent) => {
    if (pressed !== null) go(cellUnder(event))
  }
  // Let go over another cell, that cell is chosen; the browser would not
  // choose it, because the press began on a different one.
  const up = (event: PointerEvent) => {
    if (pressed === null) return
    const from = pressed
    pressed = null
    const over = control.contains(event.target as Node) ? cellUnder(event) : checked()
    if (over !== from && over !== checked()) inputs()[over].click()
    else go(checked())
    settle()
  }
  const cancel = () => {
    if (pressed === null) return
    pressed = null
    go(checked())
    settle()
  }
  const change = () => {
    if (!lastInputByPointer() || still(control)) return rest()
    go(checked())
    if (pressed === null) settle()
  }

  const doc = control.ownerDocument
  control.addEventListener("pointerdown", down)
  control.addEventListener("pointermove", move)
  control.addEventListener("change", change)
  doc.addEventListener("pointerup", up, true)
  doc.addEventListener("pointercancel", cancel, true)
  return () => {
    control.removeEventListener("pointerdown", down)
    control.removeEventListener("pointermove", move)
    control.removeEventListener("change", change)
    doc.removeEventListener("pointerup", up, true)
    doc.removeEventListener("pointercancel", cancel, true)
    utils.remove(indicator)
  }
}

// Where the bar was when a tab was pressed, by row, kept until the new page or
// patch arrives: a live navigation draws a new row, so the hook that left is
// not the one that arrives.
const pressedTabs = new Map<string, {href: string; left: number; width: number}>()

const current = (row: HTMLElement) => row.querySelector<HTMLElement>("a[aria-current='page']")

function linkTabs(hook: TravelHook) {
  const row = hook.el
  // Empty until the first arrival, which scrolls the current tab into view.
  let shown: string | null = null

  // Scrolls the row, never the page, so the tab is in view.
  const reveal = (tab: HTMLElement) => {
    const box = row.getBoundingClientRect()
    const place = tab.getBoundingClientRect()
    const room = parseFloat(getComputedStyle(row).columnGap) || 0
    if (place.left < box.left) row.scrollLeft -= box.left - place.left + room
    else if (place.right > box.right) row.scrollLeft += place.right - box.right + room
  }

  const press = (event: MouseEvent) => {
    const tab = event.target instanceof Element ? event.target.closest<HTMLElement>("a[href]") : null
    const was = current(row)
    if (!tab || !was || tab === was || !byPointer(event)) return
    const box = row.getBoundingClientRect()
    const place = was.getBoundingClientRect()
    pressedTabs.set(row.id, {href: tab.getAttribute("href") ?? "", left: place.left - box.left, width: place.width})
  }

  const arrive = () => {
    const tab = current(row)
    const href = tab?.getAttribute("href") ?? null
    const was = pressedTabs.get(row.id)
    pressedTabs.delete(row.id)
    if (!tab || href === shown) return
    shown = href
    reveal(tab)
    if (!was || was.href !== href || still(row)) return

    const box = row.getBoundingClientRect()
    const place = tab.getBoundingClientRect()
    utils.set(tab, {"--rg-travel-x": `${was.left - (place.left - box.left)}px`, "--rg-travel-scale": was.width / place.width})
    animate(tab, {
      "--rg-travel-x": "0px",
      "--rg-travel-scale": 1,
      duration: SLOW,
      ease: EASE_IN_OUT,
      onComplete: () => {
        tab.style.removeProperty("--rg-travel-x")
        tab.style.removeProperty("--rg-travel-scale")
      },
    })
  }

  row.addEventListener("click", press, true)
  return {arrive, stop: () => row.removeEventListener("click", press, true)}
}
