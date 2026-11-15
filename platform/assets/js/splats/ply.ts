/**
 * A splats-page scene as a .ply file in the layout Gaussian splatting tools read (the
 * one `save_ply` writes in Kerbl et al.'s code): binary, little-endian, one vertex per
 * splat with its place, a zero normal, its colour as spherical harmonics (degree 0,
 * then degree 1 channel by channel: red's three, green's, blue's), its opacity before
 * the sigmoid, the logs of its scales, and its rotation, real part first.
 *
 * The scenes keep the light baked into their colours, so a viewer shows them lit as the
 * page does. What only the page adds is not in the file: the sky, the glows, the motes,
 * the pixel pass, and the motion (moving parts stand where they were grown; flames,
 * steam, fireflies and water stand at their seeds). Y is up, as on the page.
 * `export_ply.mjs` writes the files; nothing on the page reads them.
 */
import {SPLAT_FLOATS, type Scene} from "./build.ts"

export const PLY_PROPERTIES = [
  "x", "y", "z", "nx", "ny", "nz",
  "f_dc_0", "f_dc_1", "f_dc_2",
  ...Array.from({length: 9}, (_, i) => `f_rest_${i}`),
  "opacity", "scale_0", "scale_1", "scale_2",
  "rot_0", "rot_1", "rot_2", "rot_3",
]

// Where each property comes from in a splat (build.ts's layout), or -1 for a zero normal.
const SOURCE = [0, 1, 2, -1, -1, -1, 12, 13, 14, 16, 17, 18, 20, 21, 22, 24, 25, 26, 3, 8, 9, 10, 4, 5, 6, 7]

const END = "end_header\n"

export function toPly(scene: Pick<Scene, "count" | "data">): Uint8Array<ArrayBuffer> {
  const header = new TextEncoder().encode(
    ["ply", "format binary_little_endian 1.0", `element vertex ${scene.count}`, ...PLY_PROPERTIES.map(name => `property float ${name}`), END].join("\n"),
  )
  const bytes = new Uint8Array(header.length + scene.count * SOURCE.length * 4)
  bytes.set(header)
  const body = new DataView(bytes.buffer, header.length)
  for (let i = 0; i < scene.count; i++) {
    for (let p = 0; p < SOURCE.length; p++) {
      const from = SOURCE[p]!
      body.setFloat32((i * SOURCE.length + p) * 4, from < 0 ? 0 : scene.data[i * SPLAT_FLOATS + from]!, true)
    }
  }
  return bytes
}

/** A .ply file's header, as a reader sees it: its format, how many vertices, their properties, and the byte their values start at. */
export function readPlyHeader(bytes: Uint8Array): {format: string; count: number; properties: string[]; body: number} {
  const text = new TextDecoder("latin1").decode(bytes.subarray(0, 4096))
  const end = text.indexOf(END)
  const lines = text.slice(0, end).split("\n")
  const value = (prefix: string) => lines.find(line => line.startsWith(prefix))?.slice(prefix.length) ?? ""
  return {
    format: value("format "),
    count: Number(value("element vertex ")),
    properties: lines.filter(line => line.startsWith("property ")).map(line => line.split(" ").at(-1)!),
    body: end + END.length,
  }
}
