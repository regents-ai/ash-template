/**
 * The Keyfleet hero in the motion lab: the hex field behind the hero and the
 * Club's map, the turn of the next Key's card, the raised plate the button
 * stands on, and the lab's replay of the entrance. Every one only presents; the page is complete and
 * readable before any of it loads, and none of it gates the Buy button.
 */
import {animate, createAnimatable, createScope, type AnimatableObject, type Scope} from "animejs"
import {createCanvasIsland, type CanvasIslandController} from "../canvas_island"
import {BASE, EASE_OUT, FAST, SLOW, still} from "./motion/shared"
import type {PlateRenderer} from "../keyfleet_hero/plate_renderer"
import type {FieldRenderer, Rgb} from "../keyfleet_hero/renderer"

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

/** How many tiles apart the marks of a wake are laid, and the most one move may lay. */
const WAKE_SPACING = 0.5
const WAKE_MARKS_PER_MOVE = 12

/**
 * The hex field. `data-field-cell` is the distance between neighbouring tiles
 * in CSS pixels. Anywhere in the element marked `data-field-scope`, a mouse
 * lights the tiles near it, and a mouse or a finger leaves a wake of lit tiles
 * that fades behind it; scrolling under a resting mouse draws the wake along
 * the tiles passing beneath it. A press or a tap sends a ring out across the
 * tiles. Inside a hero, previewing the Key, by pointing or by tabbing to Buy,
 * lights the tiles around the card. Nothing moves unless someone does, and
 * the field is still again shortly after. Less motion keeps the picture and
 * drops the pointer's light, the wake and the ring.
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
          if (!event.isPrimary || event.pointerType === "touch" || still(root)) return
          const [x, y] = across(event, canvas().getBoundingClientRect())
          renderer()?.point(x, y)
          mouse = [event.clientX, event.clientY]
          leave(event.clientX, event.clientY)
          nudge()
        }
        const onLeave = (event: PointerEvent) => {
          if (event.pointerType === "touch") return
          mouse = undefined
          trail = undefined
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
        // The page moves under a resting mouse, so the pointer's light moves
        // to the tiles now beneath it, and the wake follows.
        const onScroll = () => {
          if (!mouse || still(root)) return
          const box = canvas().getBoundingClientRect()
          renderer()?.point((mouse[0] - box.left) / box.width, (mouse[1] - box.top) / box.height)
          leave(mouse[0], mouse[1])
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
        scope.addEventListener("pointermove", onMove, options)
        scope.addEventListener("pointerleave", onLeave, options)
        scope.addEventListener("pointerdown", onPress, options)
        scope.addEventListener("touchstart", onTouch, options)
        scope.addEventListener("touchmove", onTouch, options)
        scope.addEventListener("touchend", onLift, options)
        scope.addEventListener("touchcancel", onLift, options)
        window.addEventListener("scroll", onScroll, options)
        if (finePointer()) {
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

/** How high the plate's tiles stand, in CSS pixels: at rest, previewed and pressed. */
const LIFT = {rest: 5, up: 7, down: 2}
/** How much higher the group of tiles under the words stands once raised, in CSS pixels. */
const GROUP_LIFT = 10
/** How long the tiles take to rise as the plate first appears, and after a replay. */
const RISE = 520

type PlateMove = {lift?: number; rise?: number; glow?: number; up?: number}

/**
 * The plate "Buy Agent Fleet Access Key" stands on. Once the GPU's picture has
 * landed, its tiles rise from the left. Pointing at the Key's card or the
 * plate, or tabbing to the button, raises the group of tiles under the words
 * higher than the rest, from the middle out, their faces turning dark, and
 * the words ride up on them in light ink. Pressing pushes the tiles down. A
 * finger has nothing to point with, so for a finger the group stands raised
 * from the start. The button is off, so none of this does anything but answer
 * the hand. Less motion sets each height without moving. Without WebGPU the
 * stylesheet's flat plate is what shows.
 */
export const KeyfleetPlate = {
  mounted(this: IslandHook) {
    const root = this.el
    const hero = root.closest<HTMLElement>("[data-field-scope]")
    const buy = root.closest<HTMLElement>("[data-key-preview]") ?? root
    const content = root.querySelector<HTMLElement>("[data-plate-content]")!
    const button = root.querySelector<HTMLElement>("button")!
    const words = [...content.children] as HTMLElement[]
    const cell = Number(root.dataset.plateCell ?? 20)
    const state = {lift: LIFT.rest, rise: 0, glow: 0, up: 0}
    let risen = false

    this.controller = createCanvasIsland<PlateRenderer>(root, {}, {
      canvasSelector: "[data-plate-canvas]",
      readyFlag: "plateReady",
      motionSensitive: false,
      continuous: false,
      browserLoad: async (canvas, size, lost) => {
        const {createPlateRenderer} = await import("../keyfleet_hero/plate_renderer")
        return createPlateRenderer(canvas, size, lost, cell)
      },
      interact: ({canvas, renderer, nudge, onReady}) => {
        // The words stand on the tiles, so they rise as far as the tiles under them do.
        const push = () => {
          const plate = renderer()
          plate?.raise(state.lift, state.rise, state.glow)
          plate?.group(GROUP_LIFT, state.up)
          content.style.setProperty("--kf-plate-lift", `${-(state.lift * state.rise + GROUP_LIFT * state.up)}px`)
          content.style.setProperty("--kf-plate-raised", `${state.up}`)
          nudge()
        }
        // The plate's box inside the canvas, half a tile in from each side so
        // the tiles' jagged edge lands on the box itself, and the box the
        // words cover, a little over half a tile out, for the group under
        // them. Offsets, so the hero's entrance and the words' own lift,
        // which move everything together, do not count.
        const place = () => {
          const stage = canvas().parentElement!
          const inset = cell * 0.5
          const left = -stage.offsetLeft
          const top = -stage.offsetTop
          const frame = content.getBoundingClientRect()
          const boxes = words.map(word => word.getBoundingClientRect())
          const x = left + content.offsetLeft - frame.left
          const y = top + content.offsetTop - frame.top
          renderer()?.slab(
            [left + inset, top + inset, left + root.offsetWidth - inset, top + root.offsetHeight - inset],
            [
              x + Math.min(...boxes.map(box => box.left)) - cell * 0.6,
              y + Math.min(...boxes.map(box => box.top)) - cell * 0.4,
              x + Math.max(...boxes.map(box => box.right)) + cell * 0.6,
              y + Math.max(...boxes.map(box => box.bottom)) + cell * 0.4,
            ],
          )
          nudge()
        }
        const retone = () => {
          const [red, green, blue] = tone(root, "--color-bg")
          const light = 0.2126 * red + 0.7152 * green + 0.0722 * blue > 0.5
          renderer()?.tones(
            tone(root, "--kf-plate-face"),
            tone(root, "--kf-plate-side"),
            tone(root, "--kf-plate-deep"),
            light ? 0.22 : 0.45,
          )
          nudge()
        }

        const scope = createScope({root})
        scope.add(() => {
          scope.add("move", (to: PlateMove, duration: number, delay = 0) => {
            if (still(root)) {
              Object.assign(state, to)
              push()
              return
            }
            animate(state, {...to, duration, delay, ease: EASE_OUT, onUpdate: push})
          })
        })
        const move = (to: PlateMove, duration: number, delay = 0) => scope.methods.move!(to, duration, delay)

        const pointing = finePointer()
        let hovering = false
        let focused = false
        let pressed = false
        const raised = () => !pointing || hovering || focused
        const settle = (duration: number) => {
          const previewed = hovering || focused
          move(
            {lift: pressed ? LIFT.down : previewed ? LIFT.up : LIFT.rest, glow: previewed ? 1 : 0, up: raised() ? 1 : 0},
            duration,
          )
        }
        const rise = (delay: number) => {
          state.rise = 0
          state.up = 0
          push()
          move({rise: 1, up: raised() ? 1 : 0}, RISE, delay)
        }

        onReady(() => {
          retone()
          place()
          if (risen) {
            push()
            return
          }
          risen = true
          rise(0)
        })

        const onEnter = () => { hovering = true; settle(SLOW) }
        const onExit = () => { hovering = false; pressed = false; settle(BASE) }
        const onDown = (event: PointerEvent) => {
          if (!event.isPrimary) return
          pressed = true
          settle(FAST)
        }
        const onUp = () => {
          if (!pressed) return
          pressed = false
          settle(BASE)
        }
        // A key press answers at once.
        const onFocus = () => {
          focused = button.matches(":focus-visible")
          settle(0)
        }
        const onBlur = () => { focused = false; settle(0) }
        // The lab's replay plays the hero's entrance, which waits 180 ms for the Key.
        const onReplay = () => rise(180)

        const events = new AbortController()
        const options = {signal: events.signal, passive: true}
        if (pointing) {
          buy.addEventListener("pointerenter", onEnter, options)
          buy.addEventListener("pointerleave", onExit, options)
        }
        root.addEventListener("pointerdown", onDown, options)
        root.addEventListener("pointerup", onUp, options)
        root.addEventListener("pointercancel", onUp, options)
        button.addEventListener("focus", onFocus, options)
        button.addEventListener("blur", onBlur, options)
        hero?.addEventListener("kf:replay", onReplay, options)
        const forget = watchTheme(retone)
        const resized = new ResizeObserver(place)
        resized.observe(root)

        return () => {
          events.abort()
          forget()
          resized.disconnect()
          scope.revert()
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
