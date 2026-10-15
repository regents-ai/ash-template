/** Lab-only feedback. Outcomes stay in LiveView; these islands only present them. */
import {animate, createScope, utils, type JSAnimation, type Scope} from "animejs"
import {createCanvasIsland, type CanvasIslandController} from "./canvas_island"
import {BASE, EASE_OUT, FAST, lastInputByPointer, play, still} from "./hooks/motion/shared"
import type {GradientRenderer} from "./feedback_gradient"

type FeedbackHook = {
  el: HTMLElement
  scope?: Scope
  release?: () => void
  sync?: () => void
  handleEvent(name: string, callback: (payload: {id: string; message: string}) => void): void
}

export const LabFeedback = {
  mounted(this: FeedbackHook) {
    const root = this.el
    let press: JSAnimation | undefined
    const scope = createScope({root, mediaQueries: {reduced: "(prefers-reduced-motion: reduce)"}})
    this.scope = scope.add(() => {
      scope.add("press", (label: HTMLElement, scale: number) => { press = animate(label, {scale: [scale, .98], duration: FAST, ease: EASE_OUT}) })
      scope.add("release", (label: HTMLElement) => {
        const scale = Number(utils.get(label, "scale")) || 1
        press?.revert()
        press = undefined
        play(label, {scale: [scale, 1], duration: FAST * .75, ease: EASE_OUT})
      })
      scope.add("confirm", (mark: HTMLElement) => play(mark, {opacity: [.45, 1], y: [3, 0], duration: BASE, ease: EASE_OUT}))
      scope.add("edge", (marks: Element[]) => play(marks, {opacity: [.45, 1], duration: BASE, ease: EASE_OUT}))
    })
    const events = new AbortController()
    const options = {signal: events.signal}
    let pressed: HTMLElement | null = null
    let validity = root.dataset.validity
    let receipt = root.dataset.receipt
    let state = root.dataset.state
    let composing = false
    const textarea = () => root.querySelector<HTMLTextAreaElement>("#flair-message")
    const clearPress = () => {
      if (pressed && !still(root)) scope.methods.release(pressed)
      pressed = null
    }
    root.addEventListener("pointerdown", event => {
      if (event.button !== 0 || !event.isPrimary || still(root)) return
      const button = event.target instanceof Element ? event.target.closest<HTMLElement>("[data-flair-press]") : null
      const label = button?.querySelector<HTMLElement>("[data-flair-label]")
      if (!label || button?.matches(":disabled, [aria-disabled='true']")) return
      const scale = Number(utils.get(label, "scale")) || 1
      scope.refresh() // Retire completed runs; repeated presses cannot accumulate timelines.
      pressed = label
      scope.methods.press(label, scale)
    }, options)
    document.addEventListener("pointerup", clearPress, options)
    document.addEventListener("pointercancel", clearPress, options)
    window.addEventListener("blur", clearPress, options)
    root.addEventListener("keydown", () => { pressed = null; scope.refresh() }, options)

    const syncDraft = () => {
      const active = Boolean(textarea()?.value.trim())
      const indicator = root.querySelector<HTMLElement>("[data-typing]")!
      indicator.dataset.active = String(active)
      root.querySelector<HTMLElement>("[data-typing-label]")!.textContent = active ? "Draft in progress" : "Ready when you are"
    }
    root.addEventListener("input", event => { if ((event.target as Element).id === "flair-message" && !composing) syncDraft() }, options)
    root.addEventListener("compositionstart", () => { composing = true }, options)
    root.addEventListener("compositionend", () => { composing = false; syncDraft() }, options)
    this.handleEvent("flair:sent", ({id, message}) => {
      if (id !== root.id) return
      const input = textarea()
      if (input?.value === message) input.value = ""
      syncDraft()
    })
    this.sync = () => {
      if (root.dataset.receipt !== receipt || root.dataset.validity !== validity) {
        scope.refresh()
        if (lastInputByPointer() && !still(root)) {
          const selector = root.dataset.receipt !== receipt ? "[data-receipt-mark]" : root.dataset.validity === "valid" ? "[data-valid-mark]" : null
          const mark = selector && root.querySelector<HTMLElement>(selector)
          if (mark) scope.methods.confirm(mark)
        }
        receipt = root.dataset.receipt
        validity = root.dataset.validity
      }
      if (root.dataset.state !== state) {
        scope.refresh()
        if (lastInputByPointer() && !still(root)) scope.methods.edge(Array.from(root.querySelectorAll(".flair-edge-skin")))
        state = root.dataset.state
      }
      syncDraft()
    }
    const observer = new MutationObserver(() => { pressed = null; scope.refresh() })
    const lab = root.closest("#motion-lab")
    if (lab) observer.observe(lab, {attributes: true, attributeFilter: ["data-motion"]})
    this.release = () => { events.abort(); observer.disconnect() }
  },
  updated(this: FeedbackHook) { this.sync?.() },
  disconnected(this: FeedbackHook) { this.scope?.refresh() },
  destroyed(this: FeedbackHook) { this.release?.(); this.scope?.revert() },
}

type GradientHook = {el: HTMLElement; controller?: CanvasIslandController; sync?: () => void; release?: () => void}
export const LabGradient = {
  mounted(this: GradientHook) {
    const root = this.el
    this.controller = createCanvasIsland<GradientRenderer>(root, {}, {
      canvasSelector: "[data-gradient-canvas]",
      readyFlag: "gradientReady",
      motionSensitive: true,
      // Drawn only when the state changes; nothing moves between changes.
      continuous: false,
      browserLoad: async (canvas, size, lost) => {
        const {createGradientRenderer} = await import("./feedback_gradient")
        return createGradientRenderer(canvas, size, lost)
      },
      interact: ({renderer, nudge, onReady}) => {
        const sync = () => { renderer()?.state(root.dataset.state ?? "ready"); nudge() }
        this.sync = sync
        onReady(sync)
        return () => { this.sync = undefined }
      },
    })
    this.controller.mount()
    const lab = root.closest("#motion-lab")
    const syncMotion = () => {
      if (still(root) || matchMedia("(forced-colors: active)").matches) this.controller?.pause()
      else this.controller?.resume()
    }
    const observer = new MutationObserver(syncMotion)
    if (lab) observer.observe(lab, {attributes: true, attributeFilter: ["data-motion"]})
    const colors = matchMedia("(forced-colors: active)")
    colors.addEventListener("change", syncMotion)
    this.release = () => { observer.disconnect(); colors.removeEventListener("change", syncMotion) }
    syncMotion()
  },
  updated(this: GradientHook) { this.sync?.() },
  disconnected(this: GradientHook) { this.controller?.pause() },
  reconnected(this: GradientHook) { if (!still(this.el) && !matchMedia("(forced-colors: active)").matches) this.controller?.resume() },
  destroyed(this: GradientHook) { this.release?.(); this.controller?.destroy() },
}
