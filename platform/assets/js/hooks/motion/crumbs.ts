/**
 * The shared breadcrumb (`Regent.Primitives.breadcrumb`): when the path
 * changes, the new page showing rises into place and the levels that left fade
 * out where they stood. The old page showing, now a level above, only turns
 * muted, which the stylesheet does. Its menus and its card grow from their
 * buttons through the kit's menu motion (`motion.ts`).
 */
import {animate, utils} from "animejs"
import {EASE_IN, EASE_OUT, FAST, SLOW, byPointer, play, still} from "./shared"
import type {Hook} from "../../hook_composition"

type Crumb = {name: string; ghost: HTMLElement; left: number; top: number}
type Path = {here: string; crumbs: Crumb[]}

const crumbs = (list: HTMLElement) => [...list.querySelectorAll<HTMLElement>(":scope > li[data-crumb]")]
const here = (list: HTMLElement) => list.querySelector<HTMLElement>(":scope > li[data-place='here']")

// The path as it stands, with a copy of each level to fade out if it leaves.
// A copy carries no ids, menu buttons or crumb marks, so it never stands in
// for a real level while it fades.
function record(list: HTMLElement): Path {
  return {
    here: here(list)?.dataset.crumb ?? "",
    crumbs: crumbs(list).map(li => {
      const ghost = li.cloneNode(true) as HTMLElement
      ghost.removeAttribute("data-crumb")
      ghost.removeAttribute("data-place")
      for (const el of ghost.querySelectorAll("[id], [popovertarget]")) {
        el.removeAttribute("id")
        el.removeAttribute("popovertarget")
      }
      const place = li.getBoundingClientRect()
      return {name: li.dataset.crumb ?? "", ghost, left: place.left, top: place.top}
    }),
  }
}

// What changed between two paths: the new page showing and the levels that left.
export function compare(before: {here: string; names: string[]}, after: {here: string; names: string[]}) {
  return {
    rises: before.here !== after.here,
    left: before.names.filter(name => !after.names.includes(name)),
  }
}

// The design system's rise is 4px: half its smallest space step.
const rise = (el: HTMLElement) => parseFloat(getComputedStyle(el).getPropertyValue("--space-1")) / 2

function arrive(list: HTMLElement, before: Path) {
  const after = {here: here(list)?.dataset.crumb ?? "", names: crumbs(list).map(li => li.dataset.crumb ?? "")}
  const change = compare({here: before.here, names: before.crumbs.map(crumb => crumb.name)}, after)

  const shown = here(list)
  if (change.rises && shown)
    play(shown, {y: {from: rise(list)}, opacity: {from: 0}, duration: SLOW, ease: EASE_OUT})

  for (const crumb of before.crumbs.filter(crumb => change.left.includes(crumb.name))) {
    const {ghost} = crumb
    ghost.setAttribute("aria-hidden", "true")
    ghost.inert = true
    list.append(ghost)
    utils.set(ghost, {position: "absolute", left: 0, top: 0, margin: 0, pointerEvents: "none"})
    const origin = ghost.getBoundingClientRect()
    utils.set(ghost, {x: crumb.left - origin.left, y: crumb.top - origin.top})
    animate(ghost, {opacity: 0, duration: FAST, ease: EASE_IN, onComplete: () => ghost.remove()})
  }
}

// The path when a level was pressed by pointer, by breadcrumb, kept until the
// next path arrives: a patch redraws this breadcrumb, a live navigation draws a
// new one, so the hook that arrives may not be the one that was pressed. A
// level chosen from the keyboard leaves no path, so nothing moves.
const pressedPaths = new Map<string, Path>()

type CrumbsHook = {el: HTMLElement; stop?: () => void}

const listOf = (hook: CrumbsHook) => hook.el.querySelector<HTMLElement>("[data-crumbs]")

function settle(hook: CrumbsHook) {
  const list = listOf(hook)
  const was = pressedPaths.get(hook.el.id)
  if (!list || !was) return
  const now = here(list)?.dataset.crumb
  // A patch that left the path as it was, such as another part of the page
  // changing, waits for the path to change.
  if (now === was.here && crumbs(list).length === was.crumbs.length) return
  pressedPaths.delete(hook.el.id)
  if (!still(list)) arrive(list, was)
}

/** On the breadcrumb, through `phx-hook`. */
export const MotionCrumbs: Hook = {
  mounted(this: CrumbsHook) {
    settle(this)
    const press = (event: MouseEvent) => {
      const list = listOf(this)
      if (list && byPointer(event) && event.target instanceof Element && event.target.closest("a[href]"))
        pressedPaths.set(this.el.id, record(list))
    }
    this.el.addEventListener("click", press, true)
    this.stop = () => this.el.removeEventListener("click", press, true)
  },

  updated(this: CrumbsHook) {
    settle(this)
  },

  destroyed(this: CrumbsHook) {
    this.stop?.()
  },
}
