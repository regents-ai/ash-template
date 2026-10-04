// Heroicons as Tailwind classes (`hero-plus`, `hero-user-solid`, ...), drawn
// from the `heroicons` package the way Phoenix's generated apps draw them.
import fs from "node:fs"
import path from "node:path"
import plugin from "tailwindcss/plugin"

const iconsDir = path.join(import.meta.dirname, "../../node_modules/heroicons")

const sets = [
  ["", "24/outline", "1.5rem"],
  ["-solid", "24/solid", "1.5rem"],
  ["-mini", "20/solid", "1.25rem"],
  ["-micro", "16/solid", "1rem"],
]

const values = Object.fromEntries(
  sets.flatMap(([suffix, dir, size]) =>
    fs.readdirSync(path.join(iconsDir, dir)).map(file => {
      const name = path.basename(file, ".svg") + suffix
      return [name, {name, size, fullPath: path.join(iconsDir, dir, file)}]
    }),
  ),
)

export default plugin(({matchComponents}) => {
  matchComponents(
    {
      hero: ({name, size, fullPath}) => {
        const svg = encodeURIComponent(fs.readFileSync(fullPath, "utf8").replace(/\r?\n|\r/g, ""))
        return {
          [`--hero-${name}`]: `url('data:image/svg+xml;utf8,${svg}')`,
          "-webkit-mask": `var(--hero-${name})`,
          mask: `var(--hero-${name})`,
          "mask-repeat": "no-repeat",
          "background-color": "currentColor",
          "vertical-align": "middle",
          display: "inline-block",
          width: size,
          height: size,
        }
      },
    },
    {values},
  )
})
