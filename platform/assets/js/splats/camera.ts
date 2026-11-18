/**
 * The camera and the art-pixel grid of a baked scene (studio/FORMAT.md 5.1 and 5.2),
 * shared by the painter, the page's renderer, the GIF and the stills.
 *
 * The camera's zoom s is the person's zoom, from 1 (the scene's own framing) up to
 * ZOOM_LIMIT, times the stage's own fit, which steps the camera back on a stage narrower
 * than three by two. The eye stands camDist / s from the target, and the art pixels
 * follow s as FORMAT.md 5.2 says: a zoom past 1 makes each art pixel bigger on the
 * screen as well as nearer, so a scene seen close is still drawn as pixel art. The
 * target is the scene's own (camTarget) unless the person has zoomed in somewhere else
 * (renderer.ts).
 */
import type {Header} from "./scene.ts"

export type Vec3 = readonly [number, number, number]

/** The shape the scenes are framed for, three wide by two high. A narrower stage steps the camera back so the scene still fits across it. */
const FRAMED = 3 / 2

/** The steepest the view tilts over or under the scene, a little short of straight above or below. */
export const TILT_LIMIT = (86 * Math.PI) / 180

/**
 * The nearest the person may zoom: the eye a quarter of the scene's own distance from
 * the target. Both scenes still read as pixel art there; one step nearer (√2), the eye
 * is in among the bushes and the picture is a wall of leaves.
 */
export const ZOOM_LIMIT = 4

export type Grid = {
  /** The camera's zoom s: the person's zoom times the stage's fit (less than 1 on a stage narrower than three by two). */
  readonly zoom: number
  /** Screen pixels to a side of an art pixel (q). */
  readonly scale: number
  readonly columns: number
  readonly rows: number
  /** The focal length in art pixels (F). */
  readonly focal: number
}

/** The art-pixel grid for a stage this many screen pixels wide and high, zoomed in this far by the person (1 is the scene's own framing). */
export function gridFor(header: Header, width: number, height: number, zoom: number): Grid {
  const s = zoom * Math.min(1, width / height / FRAMED)
  const detail = header.detail * s ** (s > 1 ? 1 / 2 : 1 / 4)
  const span = 2 * Math.tan(header.fov / 2)
  const scale = Math.min(18, Math.max(1, Math.round(height / (span * detail * (header.camDist / s)))))
  const rows = Math.ceil(height / scale)
  return {zoom: s, scale, columns: Math.ceil(width / scale), rows, focal: rows / span}
}

export type View = {
  readonly eye: Vec3
  /** The camera's right, up and back axes (i, j, k). */
  readonly right: Vec3
  readonly up: Vec3
  readonly back: Vec3
  /** The eye's distance from the target (d). */
  readonly distance: number
}

/** The camera at this yaw and pitch, looking at `target` from the scene's distance over the camera's zoom s. */
export function viewFrom(header: Header, yaw: number, pitch: number, zoom: number, target: Vec3): View {
  const distance = header.camDist / zoom
  const back: Vec3 = [Math.cos(pitch) * Math.sin(yaw), Math.sin(pitch), Math.cos(pitch) * Math.cos(yaw)]
  const level = Math.hypot(back[0], back[2])
  const right: Vec3 = [back[2] / level, 0, -back[0] / level]
  const up: Vec3 = [
    back[1] * right[2] - back[2] * right[1],
    back[2] * right[0] - back[0] * right[2],
    back[0] * right[1] - back[1] * right[0],
  ]
  const [x, y, z] = target
  return {eye: [x + distance * back[0], y + distance * back[1], z + distance * back[2]], right, up, back, distance}
}
