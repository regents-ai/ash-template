/** The VGPU gradient example's UV-to-color technique, rendered only when state changes.
 * https://vgpu.sh/examples/gradient — no clock, idle loop, or content under the shader.
 */
import {prepareShader} from "@vgpu/wgsl/prepare"
import {effect, frame, init, surface} from "vgpu"
import type {IslandRenderer} from "./canvas_island"
export type GradientRenderer = IslandRenderer & {state(value: string): void}
const fragment = /* wgsl */ `
struct Params { hue: vec4f, }
@group(0) @binding(0) var<uniform> params: Params;
@fragment fn fs_main(@location(0) uv: vec2f) -> @location(0) vec4f {
  let light = 1.0 - smoothstep(0.05, 0.85, distance(uv, vec2f(0.72, 0.28)));
  let fold = smoothstep(0.0, 1.0, uv.x * 0.7 + uv.y * 0.3);
  let ground = vec3f(0.086, 0.086, 0.086);
  let color = mix(ground, params.hue.rgb, fold * 0.65 + light * 0.35);
  let seam = 1.0 - smoothstep(0.001, 0.006, abs(uv.y - (0.78 - uv.x * 0.36)));
  return vec4f(mix(color, vec3f(0.898, 0.890, 0.824), seam * 0.45), 1.0);
}`
const colors: Record<string, [number, number, number, number]> = {
  ready: [.682, .792, .804, 1], working: [1, .357, .098, 1],
  confirmed: [.494, .847, .663, 1], attention: [1, .608, .561, 1],
}
export async function createGradientRenderer(canvas: HTMLCanvasElement, size: readonly [number, number], lost: () => void): Promise<GradientRenderer> {
  const gpu = await init()
  try {
    const output = surface(gpu, canvas, {autoResize: false, alphaMode: "opaque", label: "feedback-gradient"})
    output.resize(size)
    const shader = effect(gpu, prepareShader(fragment, "feedback_gradient.wgsl"), {label: "feedback-gradient.material"})
    await shader.compile(output)
    let color = colors.ready
    let disposed = false
    // Disposing the device resolves the same promise, so only a live surface reports a loss.
    void gpu.lost.then(() => { if (!disposed) lost() })
    return {
      state(value) { color = colors[value] ?? colors.ready },
      resize(width, height) { output.resize([width, height]) },
      step() { return false },
      present() { shader.set({params: {hue: color}}); frame(gpu, current => current.pass(output, shader)) },
      settled() { return gpu.settled() },
      dispose() { if (disposed) return; disposed = true; output.dispose(); gpu.dispose() },
    }
  } catch (error) { gpu.dispose(); throw error }
}
