/**
 * Things a finger can throw away: a window pulled down by its handle, the phone
 * menu swiped back to its edge, a note swiped sideways. While the finger is down
 * the thing is the finger: it follows 1:1 and resists past its open edge. When
 * the finger lifts, it is gone if it was thrown fast enough or pulled far enough,
 * and leaves at the speed it was thrown; otherwise it springs back.
 *
 * Every gesture only does what a plain control already does: a window closes as
 * Escape closes it, a menu or a note as its own `data-dismiss` control does when
 * pressed. A person on a keyboard, or an agent, uses those and nothing animates.
 * A press is never held, deferred or swallowed; only the click that ends a drag
 * is, because a drag is not a press.
 *
 * Pages join in through markup: `data-sheet-handle` on the part of a window it is
 * pulled by, `data-dismiss` on the close control of a `data-panel="drawer"` or a
 * `data-toast`.
 */
import {animate, cubicBezier, spring, utils} from "animejs"
import {still} from "./shared"

// Emil Kowalski's gesture values (animation-guide §2), in pixels and
// milliseconds throughout; the two that come in other units are converted here.
export const GESTURE = {
  // Faster than this, in px/ms, dismisses whatever the distance.
  dismissVelocity: 0.11,
  // A release speed counts only after the finger has been down this long.
  minDragMs: 100,
  // A window or menu pulled this share of its size is gone.
  sheetDismissFraction: 0.25,
  // A note pulled this far is gone.
  toastDismissPx: 30,
  // How hard a thing resists past its open edge: the share of the finger's
  // travel there that it does not follow.
  edgeFriction: {pan: 0.5, sheet: 0.85},
  // Where a release lands: the speed carried on for 0.2 seconds.
  projectionMs: 0.2 * 1000,
  // How a thrown thing leaves, seeded with the speed it was thrown at.
  release: {bounce: 0.2, duration: 500},
  // How a thing not thrown far enough goes back.
  snapBack: {duration: 300, ease: cubicBezier(0.32, 0.72, 0, 1)},
  // The pointer moves the release speed is measured over.
  velocitySamples: 5,
  // How far a pointer moves along the axis before a press becomes a drag.
  slopPx: 6,
} as const

export type Sample = {t: number; at: number}

/** Speed in px/ms over the last few moves, the release included. */
export function velocity(samples: Sample[]) {
  const recent = samples.slice(-GESTURE.velocitySamples)
  const first = recent[0]
  const last = recent.at(-1)
  if (!first || !last || last.t === first.t) return 0
  return (last.at - first.at) / (last.t - first.t)
}

/**
 * Where a thing sits for a finger `offset` from where it opened. `leaves` is
 * the way it goes when dismissed (1 or -1), or 0 when either way dismisses.
 * Toward where it leaves it follows 1:1; the other way, past its open edge, it
 * resists by `friction`.
 */
export function resist(offset: number, leaves: -1 | 0 | 1, friction: number) {
  if (leaves === 0 || offset * leaves >= 0) return offset
  return offset * (1 - friction)
}

/**
 * Whether a release dismisses: a throw faster than `dismissVelocity` toward
 * where it leaves, or a pull whose landing point (the speed carried on for
 * `projectionMs`) passes `threshold`. A throw back the other way keeps it. Before
 * `minDragMs` the speed counts as nothing, so a tap is never a throw. Answers the
 * way it leaves, or 0 to keep it.
 */
export function dismisses(
  {offset, speed, heldMs, threshold, leaves}:
    {offset: number; speed: number; heldMs: number; threshold: number; leaves: -1 | 0 | 1},
): -1 | 0 | 1 {
  const v = heldMs < GESTURE.minDragMs ? 0 : speed
  const landing = offset + v * GESTURE.projectionMs
  const way = leaves === 0 ? (Math.sign(landing) as -1 | 0 | 1) : leaves
  if (way === 0) return 0
  if (v * way >= GESTURE.dismissVelocity) return way
  if (v * way <= -GESTURE.dismissVelocity) return 0
  return landing * way >= threshold ? way : 0
}

type Kind = {
  el: HTMLElement
  axis: "x" | "y"
  leaves: -1 | 0 | 1
  friction: number
  threshold: number
  // How far it travels, along its axis from where it opened, to be gone.
  gone: (way: -1 | 1) => number
  // What follows it: the shade behind a menu, a note's own fade.
  linked: (progress: number) => void
  clean: () => void
  dismiss: () => void
}

const FIELDS = "input, textarea, select, [contenteditable]"

// How far a thing has moved from where it rests, in pixels, whatever unit it was
// moved in: a window still rising is part way through a move in percent.
function shift(el: Element, axis: "x" | "y") {
  const matrix = new DOMMatrix(getComputedStyle(el).transform)
  return axis === "x" ? matrix.m41 : matrix.m42
}

// What, if anything, a press at `target` may drag.
function kindAt(target: Element): Kind | null {
  if (target.closest(FIELDS)) return null

  const handle = target.closest("dialog[open] [data-sheet-handle]")
  const sheet = handle?.closest("dialog")
  if (sheet) {
    const rect = sheet.getBoundingClientRect()
    return {
      el: sheet,
      axis: "y",
      leaves: 1,
      friction: GESTURE.edgeFriction.sheet,
      threshold: rect.height * GESTURE.sheetDismissFraction,
      gone: () => innerHeight - (rect.top - shift(sheet, "y")),
      linked: () => {},
      clean: () => {},
      dismiss: () => sheet.requestClose(),
    }
  }

  const drawer = target.closest<HTMLElement>("[data-panel='drawer']")
  const closeDrawer = drawer?.querySelector<HTMLElement>("[data-dismiss]")
  if (drawer && closeDrawer?.checkVisibility()) {
    const rect = drawer.getBoundingClientRect()
    const shade = drawer.parentElement?.querySelector<HTMLElement>(":scope > [data-backdrop]")
    return {
      el: drawer,
      axis: "x",
      leaves: -1,
      friction: GESTURE.edgeFriction.sheet,
      threshold: rect.width * GESTURE.sheetDismissFraction,
      gone: () => rect.right - shift(drawer, "x"),
      linked: progress => { if (shade) shade.style.opacity = String(1 - progress) },
      clean: () => { if (shade) shade.style.removeProperty("opacity") },
      dismiss: () => closeDrawer.click(),
    }
  }

  const note = target.closest<HTMLElement>("[data-toast]")
  const closeNote = note?.querySelector<HTMLElement>("[data-dismiss]")
  if (note && closeNote) {
    const width = note.getBoundingClientRect().width
    return {
      el: note,
      axis: "x",
      leaves: 0,
      friction: 0,
      threshold: GESTURE.toastDismissPx,
      gone: () => width,
      linked: progress => { note.style.opacity = String(1 - progress) },
      clean: () => note.style.removeProperty("opacity"),
      dismiss: () => closeNote.click(),
    }
  }

  return null
}

const position = (kind: Kind) => shift(kind.el, kind.axis)

// What follows the thing goes as far as it has gone toward leaving.
function follow(kind: Kind, at: number) {
  const toward = kind.leaves === 0 ? Math.abs(at) : Math.max(0, at * kind.leaves)
  const way = kind.leaves === 0 ? (at < 0 ? -1 : 1) : kind.leaves
  kind.linked(Math.min(1, toward / kind.gone(way)))
}

function place(kind: Kind, at: number) {
  utils.set(kind.el, {[kind.axis]: at})
  follow(kind, at)
}

function rest(kind: Kind) {
  kind.el.style.removeProperty("transform")
  kind.clean()
}

// The finger has let go at `from`, moving at `speed` px/ms.
function release(kind: Kind, from: number, speed: number, heldMs: number) {
  const way = dismisses({offset: from, speed, heldMs, threshold: kind.threshold, leaves: kind.leaves})

  // With less motion asked for, it goes straight to where it rests.
  if (still(kind.el)) {
    rest(kind)
    if (way !== 0) kind.dismiss()
    return
  }

  if (way === 0) {
    animate(kind.el, {
      [kind.axis]: [from, 0],
      ...GESTURE.snapBack,
      onUpdate: () => follow(kind, position(kind)),
      onComplete: () => rest(kind),
    })
    return
  }

  // The spring starts at the speed the thing was thrown, as a share of the
  // distance it has left to travel each second.
  const to = kind.gone(way) * way
  const leave = spring(GESTURE.release)
  if (to !== from) leave.velocity = (speed * 1000) / (to - from)
  animate(kind.el, {
    [kind.axis]: [from, to],
    ease: leave,
    onUpdate: () => follow(kind, position(kind)),
    onComplete: () => {
      kind.dismiss()
      // A note stays where it went until the page takes it away.
      if (kind.leaves !== 0) rest(kind)
    },
  })
}

// The click a drag ends with is not a press.
function swallowClick(doc: Document) {
  const swallow = (event: Event) => {
    event.preventDefault()
    event.stopPropagation()
  }
  doc.addEventListener("click", swallow, {capture: true, once: true})
  setTimeout(() => doc.removeEventListener("click", swallow, {capture: true}), 0)
}

function grab(event: PointerEvent) {
  if (!event.isPrimary || event.button !== 0 || !(event.target instanceof Element)) return
  const kind = kindAt(event.target)
  if (kind === null) return

  const doc = kind.el.ownerDocument
  const along = (e: PointerEvent) => (kind.axis === "x" ? e.clientX : e.clientY)
  const across = (e: PointerEvent) => (kind.axis === "x" ? e.clientY : e.clientX)
  const start = along(event)
  const startAcross = across(event)
  const downAt = event.timeStamp
  let base = 0
  let dragging = false
  const samples: Sample[] = []

  const move = (e: PointerEvent) => {
    if (e.pointerId !== event.pointerId) return
    const travel = along(e) - start
    if (!dragging) {
      if (Math.abs(travel) < GESTURE.slopPx) return
      // A move mostly across the axis is a scroll or something else's drag.
      if (Math.abs(across(e) - startAcross) > Math.abs(travel)) return stop()
      dragging = true
      // A thing still moving, as it opens or from the last release, stops where
      // it is and is the finger's from here.
      base = position(kind)
      utils.remove(kind.el)
      kind.el.setPointerCapture(e.pointerId)
      doc.getSelection()?.removeAllRanges()
      doc.documentElement.toggleAttribute("data-dragging", true)
    }
    const at = resist(base + travel, kind.leaves, kind.friction)
    samples.push({t: e.timeStamp, at})
    place(kind, at)
  }

  const up = (e: PointerEvent) => {
    if (e.pointerId !== event.pointerId) return
    stop()
    if (!dragging) return
    swallowClick(doc)
    const at = position(kind)
    samples.push({t: e.timeStamp, at})
    release(kind, at, velocity(samples), e.timeStamp - downAt)
  }

  // The browser took the pointer, for a scroll or a pinch: it goes back.
  const cancel = (e: PointerEvent) => {
    if (e.pointerId !== event.pointerId) return
    stop()
    if (dragging) release(kind, position(kind), 0, 0)
  }

  function stop() {
    doc.documentElement.removeAttribute("data-dragging")
    doc.removeEventListener("pointermove", move)
    doc.removeEventListener("pointerup", up)
    doc.removeEventListener("pointercancel", cancel)
  }

  doc.addEventListener("pointermove", move)
  doc.addEventListener("pointerup", up)
  doc.addEventListener("pointercancel", cancel)
}

export function mountGestures(doc: Document) {
  doc.addEventListener("pointerdown", grab)
}
