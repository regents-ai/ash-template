/**
 * The camera and the art-pixel grid of a baked scene (studio/FORMAT.md 5.1 and 5.2),
 * shared by the painter, the page's renderer, the GIF and the stills.
 */
import type {Header} from "./scene.ts"

type Vec3 = readonly [number, number, number]

/** The shape the scenes are framed for, three wide by two high. A narrower stage steps the camera back so the scene still fits across it. */
const FRAMED = 3 / 2

/** The steepest the view tilts over or under the scene, a little short of straight above or below. */
export const TILT_LIMIT = (86 * Math.PI) / 180

export type Grid = {
  /** 1 at the scene's own distance, less on a stage narrower than three by two. */
  readonly zoom: number
  /** Screen pixels to a side of an art pixel (q). */
  readonly scale: number
  readonly columns: number
  readonly rows: number
  /** The focal length in art pixels (F). */
  readonly focal: number
}

/** The art-pixel grid for a stage this many screen pixels wide and high. */
export function gridFor(header: Header, width: number, height: number): Grid {
  const zoom = Math.min(1, width / height / FRAMED)
  // FORMAT.md's zoom power is 1/4 at a zoom of 1 or less, the only zooms used here.
  const detail = header.detail * zoom ** (1 / 4)
  const span = 2 * Math.tan(header.fov / 2)
  const scale = Math.min(18, Math.max(1, Math.round(height / (span * detail * (header.camDist / zoom)))))
  const rows = Math.ceil(height / scale)
  return {zoom, scale, columns: Math.ceil(width / scale), rows, focal: rows / span}
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

/** The camera at this yaw and pitch, stepped back by the zoom. */
export function viewFrom(header: Header, yaw: number, pitch: number, zoom: number): View {
  const distance = header.camDist / zoom
  const back: Vec3 = [Math.cos(pitch) * Math.sin(yaw), Math.sin(pitch), Math.cos(pitch) * Math.cos(yaw)]
  const level = Math.hypot(back[0], back[2])
  const right: Vec3 = [back[2] / level, 0, -back[0] / level]
  const up: Vec3 = [
    back[1] * right[2] - back[2] * right[1],
    back[2] * right[0] - back[0] * right[2],
    back[0] * right[1] - back[1] * right[0],
  ]
  const [x, y, z] = header.camTarget
  return {eye: [x + distance * back[0], y + distance * back[1], z + distance * back[2]], right, up, back, distance}
}
