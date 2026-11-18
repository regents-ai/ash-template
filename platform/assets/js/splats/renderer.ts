/**
 * The splats page's picture (`AshTemplateWeb.SplatsLabLive`): one baked scene of the
 * seven (`priv/static/splats/<scene>.bin`, scene.ts), painted
 * by painter.ts on one canvas through WebGPU, turning once every thirty seconds while
 * everything in it plays its eight-second loop.
 *
 * A drag orbits the scene under the pointer, one to one: across turns it round without
 * end; up and down tilts the view over it or under it, stopping short of straight above
 * or below so it never flips. Let go, and it carries on at the speed it was let go at,
 * then eases back into its slow turn and its resting tilt. The arrow keys turn and tilt
 * it a step at a time.
 *
 * A zoom brings the camera nearer, from the scene's own framing up to four times as near
 * (camera.ts), and the zoom stays where it is left. A pinch or a wheel zooms at the
 * pointer: the point of the scene under it stays under it, the camera looking a little
 * off the scene's own target, never further off than the scene's radius, and less the
 * nearer the zoom comes to the scene's own framing, where it looks at the target itself.
 * A step, from a button or a key, zooms on the middle of the stage and eases there. While
 * zoom keeps coming the slow turn stops; a moment after the last, it eases back in. The
 * loop plays throughout, and the tilt goes home as it does after a drag. Home eases the
 * zoom, the target and the tilt back to the opening view; the turn carries on from where
 * it is.
 *
 * Held still (less motion asked for), nothing moves by itself: it opens at the still
 * picture's view and moment, and a drag, a key, a zoom or home still moves it, landing at
 * once and stopping where it is left.
 */
import {frame, init, surface} from "vgpu"

import type {IslandRenderer} from "../canvas_island"
import {TILT_LIMIT, ZOOM_LIMIT, viewFrom, type Grid, type Vec3} from "./camera.ts"
import {createPainter} from "./painter.ts"
import {loadScene, type Scene} from "./scene.ts"

/** One full turn every thirty seconds, in radians a second. */
const CRUISE = (Math.PI * 2) / 30
/** How quickly a released scene's turn eases back to the cruise (seconds). */
const SETTLE = 0.9
/** How quickly a flicked tilt slows (seconds). */
const COAST = 0.35
/** How long after a release or a key the tilt starts back to rest, and how quickly it goes; and how long after the last zoom the turn starts back. */
const RETURN_AFTER = 0.8
const RETURN = 1.2
/** How quickly a key's step or a zoom's step settles (seconds), and how far one press turns, tilts and zooms. */
const KEY_SETTLE = 0.18
const KEY_TURN = (20 * Math.PI) / 180
const KEY_TILT = (12 * Math.PI) / 180
const KEY_ZOOM = Math.SQRT2
/** The fastest a flick sets the scene turning or tilting: once round a second, half round a second. */
const FASTEST_TURN = Math.PI * 2
const FASTEST_TILT = Math.PI
/** A frame after a long pause counts as this long, so nothing jumps. */
const LONGEST_STEP = 1 / 30

const ORIGIN: Vec3 = [0, 0, 0]

const clampTilt = (pitch: number) => Math.max(-TILT_LIMIT, Math.min(TILT_LIMIT, pitch))
// A zoom within a millionth of either end is that end, so the steps there and back land on it.
const clampZoom = (zoom: number) => (zoom < 1 + 1e-6 ? 1 : zoom > ZOOM_LIMIT - 1e-6 ? ZOOM_LIMIT : zoom)
const ease = (dt: number, over: number) => 1 - Math.exp(-dt / over)

/** The three zoom controls: one step nearer, one step farther, and back to the opening view. */
export type ZoomAction = "in" | "out" | "home"

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
  /**
   * A pinch or a wheel: zooms by `by` (over 1 nearer, under 1 farther) at the point of the
   * stage `across` and `down` from its top left, each a share of its width and height, so
   * the point of the scene under it stays there. Lands at once and takes over from any
   * step still easing.
   */
  zoomAt(by: number, across: number, down: number): void
  /** A zoom button or key: one step nearer or farther on the middle of the stage, or home to the opening view. Eased, or at once when held still. */
  zoom(action: ZoomAction): void
  /**
   * True for each zoom action that has nothing left to do once every step owed has
   * landed: in at the nearest zoom, out at the scene's own framing, home at the opening
   * view (held still, that includes the resting tilt; otherwise the tilt goes home by itself).
   */
  limits(): Readonly<Record<ZoomAction, boolean>>
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
    let box = size
    stage.resize([box[0], box[1]])
    let zoomed = 1
    let grid: Grid = painter.resize(box[0], box[1], zoomed)
    await painter.compile(stage)

    let calm = false
    let held = false
    // How far the scene has turned from its starting yaw, its near side to the right, and the time into its loop.
    let turn = 0
    let pitch = header.camPitch
    let seconds = 0
    let turnSpeed = CRUISE
    let tiltSpeed = 0
    // Seconds since the pointer let go or a key was pressed, for the tilt's way home, and since the last zoom, for the turn's.
    let since = Infinity
    let zoomedAgo = Infinity
    // Turning and tilting still owed to arrow presses, and to drags since the last frame.
    let keyedTurn = 0
    let keyedTilt = 0
    let draggedTurn = 0
    let draggedTilt = 0
    // The zoom a step or home is easing to, and how far the camera looks off the scene's own target, in world units, and where that is easing to.
    let zoomGoal = zoomed
    let aim = ORIGIN
    let aimGoal = ORIGIN
    let drawn: {turn: number; pitch: number; zoomed: number; aim: Vec3} | undefined
    let last: number | undefined
    // Radians per CSS pixel, so the scene's near edge keeps up with the pointer.
    const radians = (pixels: number) => {
      const devicePerCss = canvas.clientWidth > 0 ? canvas.width / canvas.clientWidth : 1
      const pixelsPerRadian = (grid.focal * grid.scale * header.radius * grid.zoom) / (devicePerCss * header.camDist)
      return pixels / Math.max(1, pixelsPerRadian)
    }
    // The share of a key's step owed that lands this frame.
    const settle = (owed: number, dt: number) => (Math.abs(owed) < 1e-4 ? owed : owed * ease(dt, KEY_SETTLE))
    const fit = () => {
      grid = painter.resize(box[0], box[1], zoomed)
    }
    const target = (): Vec3 => {
      const [x, y, z] = header.camTarget
      return [x + aim[0], y + aim[1], z + aim[2]]
    }
    // No further off the scene's own target than its radius, less the nearer the zoom is to the scene's own framing.
    const within = (offset: Vec3, zoom: number): Vec3 => {
      const most = header.radius * (1 - 1 / zoom)
      const length = Math.hypot(...offset)
      return length <= most ? offset : [offset[0] * (most / length), offset[1] * (most / length), offset[2] * (most / length)]
    }
    // The point of the stage `across` and `down` (shares of its width and height) in the plane through the target
    // square to the camera, as world units along the camera's right and up from the target (FORMAT.md 5.2 undone).
    const onPlane = (across: number, down: number) => {
      const pixelsPerUnit = (grid.focal * grid.scale * grid.zoom) / header.camDist
      return [
        (across * box[0] - (grid.columns * grid.scale) / 2) / pixelsPerUnit,
        ((grid.rows * grid.scale) / 2 - down * box[1]) / pixelsPerUnit,
      ] as const
    }
    // Zooming stops the turn until a moment after the last of it.
    const zooming = () => {
      turnSpeed = 0
      zoomedAgo = 0
    }

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
      zoomAt(by, across, down) {
        zooming()
        const next = clampZoom(zoomed * by)
        if (next !== zoomed) {
          const {right, up} = viewFrom(header, header.camYaw - turn, pitch, grid.zoom, target())
          const [x0, y0] = onPlane(across, down)
          zoomed = next
          fit()
          const [x1, y1] = onPlane(across, down)
          // The target moves across the camera's view by what the point under the pointer would have moved.
          const [dx, dy] = [x0 - x1, y0 - y1]
          aim = within([aim[0] + right[0] * dx + up[0] * dy, aim[1] + right[1] * dx + up[1] * dy, aim[2] + right[2] * dx + up[2] * dy], zoomed)
        }
        zoomGoal = zoomed
        aimGoal = aim
      },
      zoom(action) {
        zooming()
        if (action === "home") {
          zoomGoal = 1
          aimGoal = ORIGIN
          tiltSpeed = 0
          // The tilt comes home with the zoom, as a key's step does, and its own way home waits till it has.
          if (calm) {
            pitch = header.camPitch
            draggedTilt = 0
          } else {
            keyedTilt = header.camPitch - pitch - draggedTilt
            since = 0
          }
          return
        }
        zoomGoal = clampZoom(zoomGoal * KEY_ZOOM ** (action === "in" ? 1 : -1))
        aimGoal = within(aimGoal, zoomGoal)
      },
      limits() {
        const opening = zoomGoal === 1 && (!calm || Math.abs(clampTilt(pitch + draggedTilt) - header.camPitch) < 1e-9)
        return {in: zoomGoal === ZOOM_LIMIT, out: zoomGoal === 1, home: opening}
      },
      resize(width, height) {
        box = [width, height]
        stage.resize([width, height])
        fit()
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
        // A zoom's step and the way home ease there, the zoom by the same share each frame however far it goes.
        const share = calm ? 1 : ease(dt, KEY_SETTLE)
        if (zoomed !== zoomGoal) {
          zoomed = calm || Math.abs(Math.log(zoomGoal / zoomed)) < 1e-4 ? zoomGoal : zoomed * (zoomGoal / zoomed) ** share
          fit()
        }
        if (aim !== aimGoal) {
          const [x, y, z] = aim
          const [gx, gy, gz] = aimGoal
          const next = within([x + (gx - x) * share, y + (gy - y) * share, z + (gz - z) * share], zoomed)
          aim = calm || Math.hypot(next[0] - gx, next[1] - gy, next[2] - gz) < 1e-5 ? aimGoal : next
        }
        if (!calm) {
          seconds = (seconds + dt) % header.loop
          since += dt
          zoomedAgo += dt
          turnSpeed += ((held || zoomedAgo < RETURN_AFTER ? 0 : CRUISE) - turnSpeed) * ease(dt, SETTLE)
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
        return !calm || drawn?.turn !== turn || drawn.pitch !== pitch || drawn.zoomed !== zoomed || drawn.aim !== aim
      },
      present() {
        drawn = {turn, pitch, zoomed, aim}
        const moment = {yaw: header.camYaw - turn, pitch, target: target(), seconds}
        frame(gpu, f => painter.encode(f, moment, stage))
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
