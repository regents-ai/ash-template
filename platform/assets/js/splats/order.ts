/**
 * The order the island's splats are drawn in: farthest from the camera first, so each
 * one lays its colour over the ones behind it.
 *
 * The island only ever turns about its upright axis under a camera that stays put, so
 * how far away a splat is depends on the turn alone, along one direction. A counting
 * sort on that distance, cut to 16 bits, orders fifty thousand splats in well under a
 * millisecond; the renderer sorts again only once the island has turned a little.
 *
 * This file imports nothing, so the script that draws the page's still picture
 * (`stills.mjs`, beside it) orders the splats exactly as the browser does.
 */
const BUCKETS = 65_536

/**
 * Returns a sorter for these splats: given the island's turn and the camera's pitch
 * (radians), it hands back splat indices, farthest first. The array is reused.
 */
export function depthOrder(data: Float32Array, count: number, stride: number, reach: number) {
  const keys = new Uint16Array(count)
  const starts = new Uint32Array(BUCKETS)
  const order = new Uint32Array(count)
  const scale = (BUCKETS - 1) / (2 * reach)

  return (turn: number, pitch: number): Uint32Array<ArrayBuffer> => {
    // The camera's forward direction, carried back into the island's own frame.
    const ax = Math.sin(turn) * Math.cos(pitch)
    const ay = -Math.sin(pitch)
    const az = -Math.cos(turn) * Math.cos(pitch)
    starts.fill(0)
    for (let i = 0; i < count; i++) {
      const o = i * stride
      const ahead = data[o] * ax + data[o + 1] * ay + data[o + 2] * az
      const key = Math.min(BUCKETS - 1, Math.max(0, Math.floor((reach - ahead) * scale)))
      keys[i] = key
      starts[key] += 1
    }
    let sum = 0
    for (let k = 0; k < BUCKETS; k++) {
      const here = starts[k]
      starts[k] = sum
      sum += here
    }
    for (let i = 0; i < count; i++) order[starts[keys[i]]++] = i
    return order
  }
}
