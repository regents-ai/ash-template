/**
 * The slant of the pane. It leans away from the visitor like a window seen from
 * one side: its right edge and its foot are farther off than its left edge and
 * its head, and it is rolled a little so its lines climb to the right.
 */

type Vector = readonly [number, number, number]

/** In radians: turned about its upright, tipped back about its level, and rolled in its own plane. */
const TURN = 0.26
const TIP = 0.17
const ROLL = -0.08
/** How far the visitor's eye is from the middle of the pane, in window heights. */
export const EYE = 2.4

const lean = ([x, y, z]: Vector): Vector => {
  // Tipped, then turned, then rolled. Across is +x, down is +y, away from the eye is +z.
  const tipped: Vector = [x, y * Math.cos(TIP) - z * Math.sin(TIP), y * Math.sin(TIP) + z * Math.cos(TIP)]
  const turned: Vector = [
    tipped[0] * Math.cos(TURN) - tipped[2] * Math.sin(TURN),
    tipped[1],
    tipped[0] * Math.sin(TURN) + tipped[2] * Math.cos(TURN),
  ]
  return [
    turned[0] * Math.cos(ROLL) - turned[1] * Math.sin(ROLL),
    turned[0] * Math.sin(ROLL) + turned[1] * Math.cos(ROLL),
    turned[2],
  ]
}

const dot = (a: Vector, b: Vector) => a[0] * b[0] + a[1] * b[1] + a[2] * b[2]

/** The pane's own directions as the eye sees them: across it, down it, and straight out of its back. */
export const ACROSS = lean([1, 0, 0])
export const DOWN = lean([0, 1, 0])
export const FACING = lean([0, 0, 1])

/** Where on the pane a point of the window looks, in window heights from the pane's middle. */
const onPane = (x: number, y: number): readonly [number, number] => {
  const ray: Vector = [x, y, EYE]
  const reach = (FACING[2] * EYE) / dot(FACING, ray)
  const hit: Vector = [ray[0] * reach, ray[1] * reach, ray[2] * reach - EYE]
  return [dot(hit, ACROSS), dot(hit, DOWN)]
}

/**
 * The share of the picture behind the pane that a window of this shape sees at
 * its middle: small enough that its farthest corner still lands on the picture.
 */
export const zoomFor = (aspect: number): number =>
  Math.min(
    ...[-0.5, 0.5].flatMap(y =>
      [-0.5, 0.5].map(x => {
        const [across, down] = onPane(x * aspect, y)
        return Math.min((0.5 * aspect) / Math.abs(across), 0.5 / Math.abs(down))
      }),
    ),
  )
