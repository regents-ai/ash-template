/**
 * The splats page's picture (`AshTemplateWeb.SplatsLabLive`): one baked scene, the robot
 * factory or the floating island (`priv/static/splats/<scene>.bin`, scene.ts), painted
 * by painter.ts on one canvas through WebGPU, turning once every thirty seconds while
 * everything in it plays its eight-second loop.
 *
 * A drag orbits the scene under the pointer, one to one: across turns it round without
 * end; up and down tilts the view over it or under it, stopping short of straight above
 * or below so it never flips. Let go, and it carries on at the speed it was let go at,
 * then eases back into its slow turn and its resting tilt. The arrow keys turn and tilt
 * it a step at a time. Held still (less motion asked for), nothing moves by itself: it
 * opens at the still picture's view and moment, and a drag or a key still moves it,
 * stopping where it is left.
 */
import {frame, init, surface} from "vgpu"

import type {IslandRenderer} from "../canvas_island"
import {TILT_LIMIT, type Grid} from "./camera.ts"
import {createPainter} from "./painter.ts"
import {loadScene, type Scene} from "./scene.ts"

/** One full turn every thirty seconds, in radians a second. */
const CRUISE = (Math.PI * 2) / 30
/** How quickly a released scene's turn eases back to the cruise (seconds). */
const SETTLE = 0.9
/** How quickly a flicked tilt slows (seconds). */
const COAST = 0.35
/** How long after a release or a key the tilt starts back to rest, and how quickly it goes. */
const RETURN_AFTER = 0.8
const RETURN = 1.2
/** How quickly a key's step settles (seconds), and how far one press turns and tilts. */
const KEY_SETTLE = 0.18
const KEY_TURN = (20 * Math.PI) / 180
const KEY_TILT = (12 * Math.PI) / 180
/** The fastest a flick sets the scene turning or tilting: once round a second, half round a second. */
const FASTEST_TURN = Math.PI * 2
const FASTEST_TILT = Math.PI
/** A frame after a long pause counts as this long, so nothing jumps. */
const LONGEST_STEP = 1 / 30

const clampTilt = (pitch: number) => Math.max(-TILT_LIMIT, Math.min(TILT_LIMIT, pitch))
const ease = (dt: number, over: number) => 1 - Math.exp(-dt / over)

export type SplatRenderer = IslandRenderer & {
  /** The scene it draws, for a GIF of it (gif.ts). */
  readonly scene: Scene
  /** Holds the scene still (less motion) or lets it turn and play. */
  hold(calm: boolean): void
  /** A pointer took hold of the scene. */
  grab(): void
  /** The pointer moved this many CSS pixels across (right) and down: the scene's near edge moves with it. */
  drag(across: number, down: number): void
  /** The pointer let go, moving this many CSS pixels a second across and down. */
  release(across: number, down: number): void
  /** One arrow key: turn 1 brings the near side right, tilt 1 raises the view over the scene. */
  press(turn: -1 | 0 | 1, tilt: -1 | 0 | 1): void
}

export async function createSplatRenderer(
  canvas: HTMLCanvasElement,
  size: readonly [number, number],
  onDeviceLost: () => void,
  file: string,
): Promise<SplatRenderer> {
  // The scene downloads while the graphics card starts.
  const [started, loaded] = await Promise.allSettled([init(), loadScene(file)])
  if (started.status === "rejected") throw started.reason
  const gpu = started.value
  if (loaded.status === "rejected") {
    gpu.dispose()
    throw loaded.reason
  }
  const scene = loaded.value
  let disposed = false
  // Disposing the device resolves the same promise, so only a picture still in use reports a loss.
  void gpu.lost.then(() => {
    if (!disposed) onDeviceLost()
  })

  try {
    const {header} = scene
    const stage = surface(gpu, canvas, {autoResize: false, alphaMode: "opaque", label: "splats"})
    const painter = createPainter(gpu, scene)
    stage.resize([size[0], size[1]])
    let grid: Grid = painter.resize(size[0], size[1])
    await painter.compile(stage)

    let calm = false
    let held = false
    // How far the scene has turned from its starting yaw, its near side to the right, and the time into its loop.
    let turn = 0
    let pitch = header.camPitch
    let seconds = 0
    let turnSpeed = CRUISE
    let tiltSpeed = 0
    // Seconds since the pointer let go or a key was pressed, for the tilt's way home.
    let since = Infinity
    // Turning and tilting still owed to arrow presses, and to drags since the last frame.
    let keyedTurn = 0
    let keyedTilt = 0
    let draggedTurn = 0
    let draggedTilt = 0
    let drawn: {turn: number; pitch: number} | undefined
    let last: number | undefined
    // Radians per CSS pixel, so the scene's near edge keeps up with the pointer.
    const radians = (pixels: number) => {
      const devicePerCss = canvas.clientWidth > 0 ? canvas.width / canvas.clientWidth : 1
      const pixelsPerRadian = (grid.focal * grid.scale * header.radius * grid.zoom) / (devicePerCss * header.camDist)
      return pixels / Math.max(1, pixelsPerRadian)
    }
    // The share of a key's step owed that lands this frame.
    const settle = (owed: number, dt: number) => (Math.abs(owed) < 1e-4 ? owed : owed * ease(dt, KEY_SETTLE))

    return {
      scene,
      hold(next) {
        calm = next
        if (calm) {
          // Steps still settling land at once, as a step does when held still.
          draggedTurn += keyedTurn
          draggedTilt += keyedTilt
          keyedTurn = 0
          keyedTilt = 0
          turnSpeed = 0
          tiltSpeed = 0
        } else if (!held) turnSpeed = CRUISE
      },
      grab() {
        held = true
        turnSpeed = 0
        tiltSpeed = 0
      },
      drag(across, down) {
        draggedTurn += radians(across)
        draggedTilt += radians(down)
      },
      release(across, down) {
        held = false
        since = 0
        turnSpeed = calm ? 0 : Math.max(-FASTEST_TURN, Math.min(FASTEST_TURN, radians(across)))
        tiltSpeed = calm ? 0 : Math.max(-FASTEST_TILT, Math.min(FASTEST_TILT, radians(down)))
      },
      press(turnStep, tiltStep) {
        since = 0
        if (calm) {
          draggedTurn += turnStep * KEY_TURN
          draggedTilt += tiltStep * KEY_TILT
        } else {
          keyedTurn += turnStep * KEY_TURN
          keyedTilt += tiltStep * KEY_TILT
        }
      },
      resize(width, height) {
        stage.resize([width, height])
        grid = painter.resize(width, height)
        drawn = undefined
      },
      step() {
        const now = performance.now() / 1000
        const dt = last === undefined ? 0 : Math.min(now - last, LONGEST_STEP)
        last = now
        turn += draggedTurn
        pitch = clampTilt(pitch + draggedTilt)
        draggedTurn = 0
        draggedTilt = 0
        if (!calm) {
          seconds = (seconds + dt) % header.loop
          since += dt
          turnSpeed += ((held ? 0 : CRUISE) - turnSpeed) * ease(dt, SETTLE)
          tiltSpeed *= 1 - ease(dt, COAST)
          const turnStep = settle(keyedTurn, dt)
          const tiltStep = settle(keyedTilt, dt)
          keyedTurn -= turnStep
          keyedTilt -= tiltStep
          turn += turnSpeed * dt + turnStep
          pitch += tiltSpeed * dt + tiltStep
          if (!held) pitch += (header.camPitch - pitch) * ease(dt, RETURN) * Math.min(1, Math.max(0, (since - RETURN_AFTER) / RETURN_AFTER))
          const clamped = clampTilt(pitch)
          if (clamped !== pitch) tiltSpeed = 0
          pitch = clamped
        }
        return !calm || drawn?.turn !== turn || drawn.pitch !== pitch
      },
      present() {
        drawn = {turn, pitch}
        frame(gpu, f => painter.encode(f, {yaw: header.camYaw - turn, pitch, seconds}, stage))
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
    gpu.dispose()
    throw error
  }
}
