// Writes the splats page's two scenes as .ply files in the Gaussian splatting layout
// (ply.ts says what is in them), for opening in any splat viewer, then reads each file
// back and checks its header and counts against the scene it came from.
//
//   npm run ply:splats -- /tmp/splats        (from platform/; the folder must exist)
//
// The files are about 30 MB and 26 MB, so they are written outside the repository and
// never committed: the scenes grow from fixed seeds, so this script makes them again.
import {readFileSync, statSync, writeFileSync} from "node:fs"
import {join} from "node:path"
import {SPLAT_FLOATS} from "./build.ts"
import {buildFactory} from "./factory.ts"
import {buildIsland} from "./island.ts"
import {PLY_PROPERTIES, readPlyHeader, toPly} from "./ply.ts"

const folder = process.argv[2]
if (!folder) throw new Error("Name the folder to write the .ply files into.")

for (const [name, build] of [["factory", buildFactory], ["island", buildIsland]]) {
  const scene = build()
  const path = join(folder, `${name}.ply`)
  writeFileSync(path, toPly(scene))

  const bytes = new Uint8Array(readFileSync(path))
  const header = readPlyHeader(bytes)
  const expected = header.body + scene.count * PLY_PROPERTIES.length * 4
  const values = new DataView(bytes.buffer, bytes.byteOffset + header.body)
  const last = scene.count - 1
  const read = property => values.getFloat32((last * PLY_PROPERTIES.length + PLY_PROPERTIES.indexOf(property)) * 4, true)
  const checks = [
    ["binary, little-endian", header.format === "binary_little_endian 1.0"],
    [`${scene.count} splats`, header.count === scene.count],
    ["the standard properties, in order", header.properties.join() === PLY_PROPERTIES.join()],
    [`${expected} bytes`, statSync(path).size === expected],
    ["the last splat's place and rotation", read("x") === scene.data[last * SPLAT_FLOATS] && read("rot_3") === scene.data[last * SPLAT_FLOATS + 7]],
  ]
  const failed = checks.filter(([, ok]) => !ok).map(([what]) => what)
  console.log(`${path}: ${checks.map(([what]) => what).join("; ")}${failed.length ? ` — WRONG: ${failed.join("; ")}` : " — all as written"}`)
  if (failed.length) process.exitCode = 1
}
