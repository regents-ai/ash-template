import {existsSync, readFileSync} from "node:fs"

// The walk's server writes each request it refused outside this machine to this
// file (AshTemplate.WalkOffline); one line fails the walk, whichever page caused it.
export default function outsideTeardown() {
  const file = "tmp/walk-outside.txt"
  const outside = existsSync(file) ? readFileSync(file, "utf8").trim() : ""
  if (outside !== "")
    throw new Error(`The walk's server made requests outside this machine:\n${outside}`)
}
