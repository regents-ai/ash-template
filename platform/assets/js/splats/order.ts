/**
 * The order a scene's splats are drawn in: farthest from the camera first, so each one
 * lays its colour over the ones behind it, as Gaussian splatting composites them.
 *
 * How far a splat is from the camera, along the way the camera looks, is its depth in
 * the camera's frame up to a constant: one dot product with the camera's forward
 * direction, whatever the turn and tilt. A splat on a moving part is placed where its
 * part is now. A counting sort on that depth, cut to 16 bits, orders a few hundred
 * thousand splats in about a millisecond; the renderer sorts again only once the
 * view has moved a little, or a part has.
 *
 * Shared with the scripts beside it, so they order the splats as the browser does.
 */
import {PART_FLOAT, type Vec3} from "./build.ts"

const BUCKETS = 65_536

/**
 * Returns a sorter for these splats: given the camera's forward direction in the
 * scene's frame and where each moving part is (`Scene.pose`), it hands back splat
 * indices, farthest first. The array is reused.
 */
export function depthOrder(data: Float32Array, count: number, stride: number, reach: number) {
  const keys = new Uint16Array(count)
  const starts = new Uint32Array(BUCKETS)
  const order = new Uint32Array(count)
  const scale = (BUCKETS - 1) / (2 * reach)

  return (ahead: Vec3, parts: Float32Array): Uint32Array<ArrayBuffer> => {
    const [ax, ay, az] = ahead
    starts.fill(0)
    for (let i = 0; i < count; i++) {
      const o = i * stride
      let x = data[o]!
      let y = data[o + 1]!
      let z = data[o + 2]!
      const part = data[o + PART_FLOAT]!
      if (part !== 0) {
        const p = part * 16
        const px = parts[p]! * x + parts[p + 4]! * y + parts[p + 8]! * z + parts[p + 12]!
        const py = parts[p + 1]! * x + parts[p + 5]! * y + parts[p + 9]! * z + parts[p + 13]!
        const pz = parts[p + 2]! * x + parts[p + 6]! * y + parts[p + 10]! * z + parts[p + 14]!
        x = px
        y = py
        z = pz
      }
      const ahead = x * ax + y * ay + z * az
      const key = Math.min(BUCKETS - 1, Math.max(0, Math.floor((reach - ahead) * scale)))
      keys[i] = key
      starts[key]! += 1
    }
    let sum = 0
    for (let k = 0; k < BUCKETS; k++) {
      const here = starts[k]!
      starts[k] = sum
      sum += here
    }
    for (let i = 0; i < count; i++) order[starts[keys[i]!]!++] = i
    return order
  }
}
