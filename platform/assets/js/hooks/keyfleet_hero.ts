/**
 * The Keyfleet hero in the motion lab: the hex field behind the hero and the
 * Club's map, with the tiles nearest a mouse standing up out of it, the turn
 * of the next Key's card, and the lab's replay of the entrance. Every one
 * only presents; the page is complete and readable before any of it loads.
 */
import {animate, createAnimatable, createScope, type AnimatableObject, type Scope} from "animejs"
import {createCanvasIsland, type CanvasIslandController} from "../canvas_island"
import {EASE_IN_OUT, EASE_OUT, still} from "./motion/shared"
import type {FieldRenderer, Rgb, Tile} from "../keyfleet_hero/renderer"

/** Any colour the page can state, as the three 0..1 sRGB channels a shader takes. */
const swatch = document.createElement("canvas").getContext("2d", {willReadFrequently: true})!

const tone = (root: HTMLElement, property: string): Rgb => {
  const probe = root.ownerDocument.createElement("span")
  probe.hidden = true
  probe.style.color = `var(${property})`
  root.append(probe)
  const color = getComputedStyle(probe).color
  probe.remove()
  swatch.clearRect(0, 0, 1, 1)
  swatch.fillStyle = color
  swatch.fillRect(0, 0, 1, 1)
  const [red = 0, green = 0, blue = 0] = swatch.getImageData(0, 0, 1, 1).data
  return [red / 255, green / 255, blue / 255]
}

/** Calls `retone` whenever the page's light or dark changes. */
const watchTheme = (retone: () => void) => {
  const scheme = matchMedia("(prefers-color-scheme: dark)")
  const observer = new MutationObserver(retone)
  observer.observe(document.documentElement, {attributes: true, attributeFilter: ["data-theme"]})
  scheme.addEventListener("change", retone)
  return () => {
    observer.disconnect()
    scheme.removeEventListener("change", retone)
  }
}

/** A number the stylesheet states in a custom property. */
const measure = (el: HTMLElement, property: string) => parseFloat(getComputedStyle(el).getPropertyValue(property)) || 0

/** Where a pointer stands across an element's box, 0..1 on each axis. */
const across = (event: PointerEvent, box: DOMRect): [number, number] => [
  (event.clientX - box.left) / box.width,
  (event.clientY - box.top) / box.height,
]

const finePointer = () => matchMedia("(hover: hover) and (pointer: fine)").matches

type IslandHook = {el: HTMLElement; controller?: CanvasIslandController}

/** How many tiles apart the marks of a wake are laid, and the most one move may lay. */
const WAKE_SPACING = 0.5
const WAKE_MARKS_PER_MOVE = 12

/** How many of the tiles nearest a mouse stand raised. */
const RAISED = 5
/** How high the tile under a mouse stands, in tiles. */
const LIFT = 0.4
/** How long a tile takes to stand up, and to sink back. */
const STAND = 300
/** How long a risen tile's border takes to fade. */
const SHINE = 2000

/**
 * How far apart the field's rows are, in tiles. The tiles' centres lie on two
 * grids: whole tiles across on every row, and half a tile across, half a row
 * down, between them.
 */
const ROW = Math.sqrt(3)

/** The `count` tiles whose centres are nearest x, y (in tiles across the field), nearest first. */
const nearest = (x: number, y: number, count: number) => {
  const column = Math.floor(x)
  const down = Math.floor(y / ROW)
  const centres: {x: number; y: number; away: number}[] = []
  for (let k = column - 1; k <= column + 2; k += 1) {
    for (let m = down - 1; m <= down + 2; m += 1) {
      for (const [cx, cy] of [[k, m * ROW], [k + 0.5, (m + 0.5) * ROW]] as const) {
        centres.push({x: cx, y: cy, away: Math.hypot(cx - x, cy - y)})
      }
    }
  }
  return centres.sort((a, b) => a.away - b.away).slice(0, count)
}

/**
 * How high a tile `away` tiles from the mouse stands: the one under it
 * highest, the others lower the further off they are.
 */
const heightAt = (away: number, nearestFirst: boolean) =>
  nearestFirst ? 1 : Math.min(0.7, Math.max(0.25, 0.95 - 0.45 * away))

/** A raised tile and the height it is on its way to. */
type Standing = Tile & {key: string; to: number}

/**
 * The hex field. `data-field-cell` is the distance between neighbouring tiles
 * in CSS pixels. Anywhere in the element marked `data-field-scope`, the five
 * tiles nearest a mouse stand up out of the field, the one under it highest,
 * and follow it as it moves, each rising and sinking in 0.3 seconds. A tile
 * that rises wears a glossy border that fades over 2 seconds, from full again
 * each time it rises. A mouse
 * also lights the tiles near it, and a mouse or a finger leaves a wake of lit
 * tiles that fades behind it; scrolling under a resting mouse moves all of it
 * to the tiles passing beneath. A press or a tap sends a ring out across the
 * tiles. Inside a hero, pointing at the Key's card lights the tiles around it.
 * Nothing moves unless someone does, and the field is still again shortly
 * after. Less motion keeps the picture and drops the raised tiles, their
 * borders, the pointer's light, the wake and the ring.
 */
export const KeyfleetField = {
  mounted(this: IslandHook) {
    const root = this.el
    const scope = root.closest<HTMLElement>("[data-field-scope]") ?? root
    const buy = scope.querySelector<HTMLElement>("[data-key-preview]")
    const card = buy?.querySelector<HTMLElement>("[data-key-card]")
    const cell = Number(root.dataset.fieldCell ?? 40)

    this.controller = createCanvasIsland<FieldRenderer>(root, {}, {
      canvasSelector: "[data-field-canvas]",
      readyFlag: "fieldReady",
      motionSensitive: false,
      continuous: false,
      browserLoad: async (canvas, size, lost) => {
        const {createFieldRenderer} = await import("../keyfleet_hero/renderer")
        return createFieldRenderer(canvas, size, lost, cell)
      },
      interact: ({canvas, renderer, nudge, onReady}) => {
        const retone = () => {
          const ground = tone(root, "--color-bg")
          const light = 0.2126 * ground[0] + 0.7152 * ground[1] + 0.0722 * ground[2] > 0.5
          renderer()?.tones(
            tone(root, "--kf-field-line"),
            tone(root, "--kf-field-light"),
            ground,
            tone(root, "--kf-field-deep"),
            tone(root, "--kf-field-shine"),
            light ? 0.18 : 0.32,
          )
          nudge()
        }
        // The fade toward the field's edges, as the stylesheet states it for this layout.
        const refade = () => {
          renderer()?.fade(
            measure(root, "--kf-fade-x"),
            measure(root, "--kf-fade-y"),
            measure(root, "--kf-fade-width"),
            measure(root, "--kf-fade-height"),
            measure(root, "--kf-fade-from"),
            measure(root, "--kf-fade-to"),
          )
          nudge()
        }
        // The Key's light is centred on the card wherever the layout has put it.
        const aim = () => {
          if (!card) return
          const field = canvas().getBoundingClientRect()
          const box = card.getBoundingClientRect()
          renderer()?.key(
            (box.left + box.width / 2 - field.left) / field.width,
            (box.top + box.height / 2 - field.top) / field.height,
            Math.max(box.width, box.height) * 0.95,
          )
        }
        let hovering = false
        const preview = () => {
          aim()
          renderer()?.lit(hovering)
          nudge()
        }

        // The raised tiles, by where they sit, until each has sunk back and
        // stopped shining. The field reads their heights and borders once a
        // frame; it hears of the list itself only when tiles come or go.
        const standing = new Map<string, Standing>()
        const draw = () => {
          for (const [key, tile] of standing) if (tile.h === 0 && tile.to === 0 && tile.shine === 0) standing.delete(key)
          renderer()?.stand([...standing.values()], cell * LIFT)
          nudge()
        }
        const motion = createScope({root})
        motion.add(() => {
          // A new height takes over from the one a tile is still moving to, from wherever it got to.
          motion.add("stand", (tile: Standing, to: number, duration: number) => {
            animate(tile, {
              h: to,
              duration,
              ease: to > tile.h ? EASE_OUT : EASE_IN_OUT,
              onUpdate: nudge,
              onComplete: draw,
            })
          })
          // The border starts bright and fades evenly to nothing.
          motion.add("shine", (tile: Standing, from: number, duration: number) => {
            animate(tile, {shine: [from, 0], duration, ease: "linear", onUpdate: nudge, onComplete: draw})
          })
        })
        const stand = (tile: Standing, to: number) => {
          if (Math.abs(tile.to - to) < 0.02) return
          if (tile.to === 0 && to > 0) motion.methods.shine!(tile, 1, SHINE)
          tile.to = to
          motion.methods.stand!(tile, to, STAND)
        }
        // The tiles nearest the mouse stand; every other tile sinks.
        const follow = (clientX: number, clientY: number) => {
          const box = canvas().getBoundingClientRect()
          const near = nearest((clientX - box.left) / cell, (clientY - box.top) / cell, RAISED)
          const keys = new Set<string>()
          let added = false
          near.forEach((centre, rank) => {
            const key = `${centre.x * 2},${Math.round((centre.y * 2) / ROW)}`
            keys.add(key)
            let tile = standing.get(key)
            if (!tile) {
              tile = {key, x: centre.x * cell, y: centre.y * cell, h: 0, to: 0, shine: 0}
              standing.set(key, tile)
              added = true
            }
            stand(tile, heightAt(centre.away, rank === 0))
          })
          for (const tile of standing.values()) if (!keys.has(tile.key)) stand(tile, 0)
          if (added) draw()
        }
        const sink = () => {
          for (const tile of standing.values()) stand(tile, 0)
        }
        // Less motion: the raised tiles are back in the field at once, and dark.
        const flatten = () => {
          for (const tile of standing.values()) {
            tile.to = 0
            motion.methods.stand!(tile, 0, 0)
            motion.methods.shine!(tile, 0, 0)
          }
        }

        onReady(() => {
          retone()
          refade()
          aim()
          renderer()?.lit(hovering)
          draw()
        })

        // The last place the wake reached, in CSS pixels across the canvas, so a
        // fast move or a scroll still leaves an unbroken line of tiles.
        let trail: [number, number] | undefined
        let mouse: [number, number] | undefined
        const leave = (clientX: number, clientY: number) => {
          const field = renderer()
          if (!field) return
          const box = canvas().getBoundingClientRect()
          const to: [number, number] = [clientX - box.left, clientY - box.top]
          const from = trail ?? to
          const spacing = cell * WAKE_SPACING
          const gap = Math.hypot(to[0] - from[0], to[1] - from[1])
          if (trail && gap < spacing) return
          const count = Math.min(WAKE_MARKS_PER_MOVE, Math.max(1, Math.round(gap / spacing)))
          for (let i = 1; i <= count; i += 1) {
            const t = i / count
            field.wake((from[0] + (to[0] - from[0]) * t) / box.width, (from[1] + (to[1] - from[1]) * t) / box.height)
          }
          trail = to
        }

        const onMove = (event: PointerEvent) => {
          if (!event.isPrimary || event.pointerType === "touch") return
          if (still(root)) {
            if (standing.size > 0) flatten()
            return
          }
          const [x, y] = across(event, canvas().getBoundingClientRect())
          renderer()?.point(x, y)
          mouse = [event.clientX, event.clientY]
          follow(event.clientX, event.clientY)
          leave(event.clientX, event.clientY)
          nudge()
        }
        const onLeave = (event: PointerEvent) => {
          if (event.pointerType === "touch") return
          mouse = undefined
          trail = undefined
          sink()
          renderer()?.rest()
          nudge()
        }
        const onPress = (event: PointerEvent) => {
          if (!event.isPrimary || still(root)) return
          const [x, y] = across(event, canvas().getBoundingClientRect())
          renderer()?.ring(x, y)
          nudge()
        }
        const onTouch = (event: TouchEvent) => {
          const touch = event.touches[0]
          if (!touch || still(root)) return
          leave(touch.clientX, touch.clientY)
          nudge()
        }
        const onLift = () => { trail = undefined }
        // The page moves under a resting mouse, so the raised tiles and the
        // pointer's light move to the tiles now beneath it, and the wake follows.
        const onScroll = () => {
          if (!mouse || still(root)) return
          const box = canvas().getBoundingClientRect()
          renderer()?.point((mouse[0] - box.left) / box.width, (mouse[1] - box.top) / box.height)
          follow(mouse[0], mouse[1])
          leave(mouse[0], mouse[1])
          nudge()
        }
        const onEnter = () => { hovering = true; preview() }
        const onExit = () => { hovering = false; preview() }

        const events = new AbortController()
        const options = {signal: events.signal, passive: true}
        scope.addEventListener("pointermove", onMove, options)
        scope.addEventListener("pointerleave", onLeave, options)
        scope.addEventListener("pointerdown", onPress, options)
        scope.addEventListener("touchstart", onTouch, options)
        scope.addEventListener("touchmove", onTouch, options)
        scope.addEventListener("touchend", onLift, options)
        scope.addEventListener("touchcancel", onLift, options)
        window.addEventListener("scroll", onScroll, options)
        if (finePointer()) {
          card?.addEventListener("pointerenter", onEnter, options)
          card?.addEventListener("pointerleave", onExit, options)
        }
        const forget = watchTheme(retone)
        const resized = new ResizeObserver(() => {
          refade()
          aim()
          nudge()
        })
        resized.observe(root)
        if (card) resized.observe(card)

        return () => {
          events.abort()
          forget()
          resized.disconnect()
          motion.revert()
        }
      },
    })
    this.controller.mount()
  },
  disconnected(this: IslandHook) { this.controller?.pause() },
  reconnected(this: IslandHook) { this.controller?.resume() },
  destroyed(this: IslandHook) {
    this.controller?.destroy()
    this.controller = undefined
  },
}

type KeyCardHook = {el: HTMLElement; scope?: Scope; release?: () => void}

/**
 * The next Key's card. Under a mouse it turns a little toward the pointer and
 * settles flat when the pointer leaves. A finger, a keyboard or less motion
 * gets the card as it is.
 */
export const KeyfleetKeyCard = {
  mounted(this: KeyCardHook) {
    const root = this.el
    const tilt = root.querySelector<HTMLElement>("[data-key-tilt]")!
    let turn: AnimatableObject | undefined

    const scope = createScope({root, mediaQueries: {reduced: "(prefers-reduced-motion: reduce)"}})
    this.scope = scope.add(() => {
      if (scope.matches.reduced || !finePointer()) return
      turn = createAnimatable(tilt, {rotateX: 0, rotateY: 0, duration: 420, ease: EASE_OUT})
      return () => { turn = undefined }
    })

    const onTurn = (event: PointerEvent) => {
      if (!turn || !event.isPrimary || still(root)) return
      const [x, y] = across(event, root.getBoundingClientRect())
      turn.rotateY((x - 0.5) * 9)
      turn.rotateX((0.5 - y) * 7)
    }
    const onSettle = () => {
      turn?.rotateX(0)
      turn?.rotateY(0)
    }
    root.addEventListener("pointermove", onTurn, {passive: true})
    root.addEventListener("pointerleave", onSettle, {passive: true})
    this.release = () => {
      root.removeEventListener("pointermove", onTurn)
      root.removeEventListener("pointerleave", onSettle)
    }
  },
  destroyed(this: KeyCardHook) {
    this.release?.()
    this.scope?.revert()
  },
}

/**
 * The lab's "Replay entrance". The entrance itself plays from the stylesheet
 * as the page first paints; this takes the attribute that starts it away and
 * puts it back, so the browser plays it once more.
 */
export const KeyfleetReplay = {
  mounted(this: {el: HTMLElement; release?: () => void}) {
    const root = this.el
    const replay = () => {
      root.removeAttribute("data-enter")
      void root.offsetWidth
      root.setAttribute("data-enter", "")
    }
    root.addEventListener("kf:replay", replay)
    this.release = () => root.removeEventListener("kf:replay", replay)
  },
  destroyed(this: {release?: () => void}) { this.release?.() },
}
