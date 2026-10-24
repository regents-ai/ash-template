/**
 * Draws one wonder with WebGPU through vgpu. Loaded only once that wonder is
 * really going to be shown. A wonder with a simulation first runs its steps
 * between two textures, then draws the picture from the newer one.
 */
import {prepareShader} from "@vgpu/wgsl/prepare"
import {effect, frame, init, surface, target, type Effect, type Frame, type Target} from "vgpu"

import type {IslandRenderer} from "../canvas_island"
import type {View, Wonder} from "./wonder"

type Steps = {
  /** The texture the picture reads: the one the last step wrote. */
  readonly field: Target
  run(current: Frame): void
}

export async function createWonderRenderer<State extends object>(
  canvas: HTMLCanvasElement,
  size: readonly [number, number],
  onDeviceLost: () => void,
  name: string,
  wonder: Wonder<State>,
  state: State,
): Promise<IslandRenderer> {
  const gpu = await init()
  let disposed = false
  // Disposing the device resolves the same promise, so only a wonder still on screen reports a loss.
  void gpu.lost.then(() => {
    if (!disposed) onDeviceLost()
  })
  try {
    const stage = surface(gpu, canvas, {autoResize: false, alphaMode: "opaque", label: `wonder-${name}`})
    stage.resize([size[0], size[1]])
    const view: View = {width: size[0], height: size[1], time: 0}
    const steps = wonder.simulation && simulate(wonder, state, view, name)
    const picture = effect(gpu, prepareShader(wonder.wgsl, `wonder_${name}.wgsl`), {
      label: `wonder-${name}.picture`,
      set: {...wonder.bindings(state, view), ...(steps && {field: steps.field})},
    })
    await picture.compile(stage)
    const began = performance.now()

    return {
      resize(width, height) {
        stage.resize([width, height])
        view.width = width
        view.height = height
      },
      step() {
        if (wonder.continuous) view.time = (performance.now() - began) / 1000
        return wonder.continuous
      },
      present() {
        picture.set(wonder.bindings(state, view))
        frame(gpu, current => {
          steps?.run(current)
          current.pass(stage, picture)
        })
      },
      settled() {
        return gpu.settled()
      },
      dispose() {
        if (disposed) return
        disposed = true
        stage.dispose()
        gpu.dispose()
      },
    }
  } catch (error) {
    disposed = true
    gpu.dispose()
    throw error
  }

  // Two passes that never swap their bindings: one reads the first texture and
  // writes the second, the other reads the second and writes the first.
  function simulate(wonder: Wonder<State>, state: State, view: View, name: string): Steps {
    const simulation = wonder.simulation!
    const [width, height] = simulation.size
    const textures = [0, 1].map(() => target(gpu, {size: [width, height], format: "rgba16float"}))
    const source = prepareShader(simulation.wgsl, `wonder_${name}_steps.wgsl`)
    const passes: Effect[] = textures.map((read, index) =>
      effect(gpu, source, {
        label: `wonder-${name}.step-${index}`,
        set: {...simulation.bindings(state, view), src: read},
      }),
    )
    return {
      field: textures[0]!,
      run(current) {
        const bindings = simulation.bindings(state, view)
        for (const pass of passes) pass.set(bindings)
        for (let step = 0; step < simulation.steps; step += 2) {
          current.pass(textures[1]!, passes[0]!)
          current.pass(textures[0]!, passes[1]!)
        }
      },
    }
  }
}
