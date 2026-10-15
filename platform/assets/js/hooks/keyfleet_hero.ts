/**
 * The Keyfleet hero in the motion lab: the hex field behind the hero and the
 * Club's map, the foil and the turn of the next Key's card, and the lab's
 * replay of the entrance. Every one only presents; the page is complete and
 * readable before any of it loads, and none of it gates the Buy button.
 */
import {createAnimatable, createScope, type AnimatableObject, type Scope} from "animejs"
import {createCanvasIsland, type CanvasIslandController} from "../canvas_island"
import {EASE_OUT, still} from "./motion/shared"
import type {FieldRenderer, FoilRenderer, Rgb} from "../keyfleet_hero/renderer"

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

/** Where a pointer stands across an element's box, 0..1 on each axis. */
const across = (event: PointerEvent, box: DOMRect): [number, number] => [
  (event.clientX - box.left) / box.width,
  (event.clientY - box.top) / box.height,
]

const finePointer = () => matchMedia("(hover: hover) and (pointer: fine)").matches

type IslandHook = {el: HTMLElement; controller?: CanvasIslandController}

/**
 * The hex field. `data-field-cell` is the distance between neighbouring tiles
 * in CSS pixels. The pointer anywhere in the element marked `data-field-scope`
 * lights the tiles near it; inside a hero, previewing the Key lights the tiles
 * around the card. Less motion keeps the picture and drops the pointer's light.
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
          renderer()?.tones(tone(root, "--kf-field-line"), tone(root, "--kf-field-light"))
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
        let focused = false
        const preview = () => {
          aim()
          renderer()?.lit(hovering || focused)
          nudge()
        }
        onReady(() => {
          retone()
          preview()
        })

        const onMove = (event: PointerEvent) => {
          if (!event.isPrimary || still(root)) return
          const [x, y] = across(event, canvas().getBoundingClientRect())
          renderer()?.point(x, y)
          nudge()
        }
        const onLeave = () => {
          renderer()?.rest()
          nudge()
        }
        const onEnter = () => { hovering = true; preview() }
        const onExit = () => { hovering = false; preview() }
        const onFocus = (event: FocusEvent) => {
          focused = (event.target as Element).matches(":focus-visible")
          preview()
        }
        const onBlur = () => { focused = false; preview() }

        const events = new AbortController()
        const options = {signal: events.signal, passive: true}
        if (finePointer()) {
          scope.addEventListener("pointermove", onMove, options)
          scope.addEventListener("pointerleave", onLeave, options)
          buy?.addEventListener("pointerenter", onEnter, options)
          buy?.addEventListener("pointerleave", onExit, options)
        }
        buy?.addEventListener("focusin", onFocus, options)
        buy?.addEventListener("focusout", onBlur, options)
        const forget = watchTheme(retone)
        const resized = new ResizeObserver(preview)
        if (card) resized.observe(card)

        return () => {
          events.abort()
          forget()
          resized.disconnect()
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

type KeyCardHook = IslandHook & {scope?: Scope; release?: () => void}

/**
 * The next Key's card. Under a mouse it turns a little toward the pointer and
 * a foil light follows it across the face; it settles flat when the pointer
 * leaves. A finger, a keyboard or less motion gets the card as it is.
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

    this.controller = createCanvasIsland<FoilRenderer>(root, {}, {
      canvasSelector: "[data-foil-canvas]",
      readyFlag: "foilReady",
      motionSensitive: true,
      continuous: false,
      browserLoad: async (canvas, size, lost) => {
        const {createFoilRenderer} = await import("../keyfleet_hero/renderer")
        return createFoilRenderer(canvas, size, lost)
      },
      interact: ({canvas, renderer, nudge, onReady}) => {
        const retone = () => {
          renderer()?.tone(tone(root, "--kf-foil-light"))
          nudge()
        }
        onReady(retone)
        if (!finePointer()) return watchTheme(retone)

        const onMove = (event: PointerEvent) => {
          if (!event.isPrimary || still(root)) return
          const [x, y] = across(event, canvas().getBoundingClientRect())
          renderer()?.point(x, y)
          nudge()
        }
        const onLeave = () => {
          renderer()?.rest()
          nudge()
        }
        const events = new AbortController()
        root.addEventListener("pointermove", onMove, {signal: events.signal, passive: true})
        root.addEventListener("pointerleave", onLeave, {signal: events.signal, passive: true})
        const forget = watchTheme(retone)
        return () => {
          events.abort()
          forget()
        }
      },
    })

    // The turn is the card's own, so it plays even where the GPU never draws.
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
    this.controller.mount()
  },
  disconnected(this: KeyCardHook) { this.controller?.pause() },
  reconnected(this: KeyCardHook) { this.controller?.resume() },
  destroyed(this: KeyCardHook) {
    this.release?.()
    this.controller?.destroy()
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
