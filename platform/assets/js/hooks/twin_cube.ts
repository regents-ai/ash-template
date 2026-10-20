import {animate, createScope, stagger, type Scope} from "animejs"

type TwinCubeHook = {
  el: HTMLElement
  scope?: Scope
  onPointing?: (event: Event) => void
}

/**
 * The twin cube's page: "Human Browsing" over the world cube and "Agentic
 * WebMCP" over the code cube, shown together while the pointer is on either
 * cube. An agent reads the same lists with the site-wide `sites_tools` and
 * `siwa_help` tools.
 */
export const TwinCube = {
  mounted(this: TwinCubeHook) {
    const labels = this.el.querySelectorAll<HTMLElement>("[data-twin-label]")
    const still = window.matchMedia("(prefers-reduced-motion: reduce)")
    // Where nothing hovers, the stylesheet keeps both names shown.
    const hoverless = window.matchMedia("(hover: none)")
    const pointing = new Set<EventTarget>()
    let shown = false

    const scope = createScope({root: this.el})
    this.scope = scope
    scope.add(() => {
      scope.add("labels", (show: boolean) => {
        animate(labels, {
          opacity: show ? 1 : 0,
          translateY: show ? 0 : 8,
          duration: still.matches ? 0 : show ? 520 : 320,
          delay: show ? stagger(90) : 0,
          ease: show ? "outCubic" : "inCubic",
        })
      })
    })

    this.onPointing = event => {
      const {pointing: on} = (event as CustomEvent<{pointing: boolean}>).detail
      if (on) pointing.add(event.target!)
      else pointing.delete(event.target!)
      if (hoverless.matches || pointing.size > 0 === shown) return
      shown = pointing.size > 0
      this.scope!.methods.labels!(shown)
    }
    this.el.addEventListener("cube:pointing", this.onPointing)
  },
  destroyed(this: TwinCubeHook) {
    if (this.onPointing) this.el.removeEventListener("cube:pointing", this.onPointing)
    this.scope?.revert()
  },
}
