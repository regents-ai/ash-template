import type {Page} from "@playwright/test"
import {expect, test} from "./support/test"
import {watch} from "./support/person"

// Pressing on the agent harbour's sea (/animations/harbour), in each theme, at 1280
// wide and on the touch phone at 390. The sea is drawn with WebGPU, which headless
// Chromium on the Mac draws once it is turned on, here and only here; what the
// drawing looks like is not checked. A calm harbour (less motion) holds its ships
// still between moves, so the walk can find one: it runs the pointer over the sea,
// as a mouse would, noting where the harbour names a ship or offers an island,
// then presses those spots as the person would, with a click or a tap.
test.use({reducedMotion: "reduce", launchOptions: {args: ["--enable-unsafe-webgpu", "--enable-gpu"]}})

type Spot = {name: string; at: [number, number]}

const islands = ["inn", "forge", "castle"]

// Each ship the pointer named, by its agent's name, and each island it offered, by
// its page; each with the middle of the spots where it did.
function overTheSea(page: Page) {
  return page.getByRole("img", {name: "The agent harbour"}).evaluate(root => {
    const box = root.getBoundingClientRect()
    const hits = {ship: new Map<string, [number, number][]>(), island: new Map<string, [number, number][]>()}
    for (let y = box.top + 2; y < box.bottom - 2; y += 3) {
      for (let x = box.left + 2; x < box.right - 2; x += 3) {
        const canvas = document.elementFromPoint(x, y)
        if (!(canvas instanceof HTMLCanvasElement)) continue
        const stage = canvas.parentElement!
        canvas.dispatchEvent(new PointerEvent("pointermove", {bubbles: true, pointerType: "mouse", clientX: x, clientY: y}))
        const shown = [...stage.children].find(child => child !== canvas && !(child as HTMLElement).hidden)
        stage.dispatchEvent(new PointerEvent("pointerleave", {pointerType: "mouse"}))
        if (!shown) continue
        const [kind, name] =
          shown instanceof HTMLAnchorElement
            ? (["island", new URL(shown.href).pathname.split("/").pop()!] as const)
            : (["ship", shown.textContent!] as const)
        hits[kind].set(name, [...(hits[kind].get(name) ?? []), [x, y]])
      }
    }
    const middles = (found: Map<string, [number, number][]>) =>
      [...found].map(([name, spots]) => ({name, at: spots[Math.floor(spots.length / 2)]}))
    return {ships: middles(hits.ship), islands: middles(hits.island)}
  }) as Promise<{ships: Spot[]; islands: Spot[]}>
}

for (const colorScheme of ["light", "dark"] as const) {
  test.describe(`${colorScheme} theme`, () => {
    test.use({colorScheme})

    test("pressing a ship opens its agent's card, and pressing an island opens its page", async ({
      page,
      hasTouch,
    }) => {
      const press = ([x, y]: [number, number]) => (hasTouch ? page.touchscreen.tap(x, y) : page.mouse.click(x, y))
      const problems = watch(page)
      await page.goto("/animations/harbour")
      await expect(page.getByRole("img", {name: "The agent harbour"})).toHaveAttribute("data-harbour-ready", "true", {
        timeout: 15_000,
      })

      // An agent sails on every 7 seconds; just after one has, the ships stay put
      // long enough to be found and pressed.
      const where = () => page.getByRole("list", {name: "Crew"}).getByRole("listitem").allTextContents()
      const before = await where()
      await expect.poll(where, {timeout: 10_000}).not.toEqual(before)

      const sea = await overTheSea(page)
      expect(sea.ships.length, "ships the pointer named").toBeGreaterThan(0)
      expect(sea.islands.map(island => island.name).sort()).toEqual([...islands].sort())

      const ship = sea.ships[0]
      await press(ship.at)
      const card = page.getByRole("dialog", {name: ship.name})
      await expect(card).toBeVisible()
      await expect(page).toHaveURL(new RegExp(`\\?agent=${ship.name.toLowerCase()}$`))
      await page.keyboard.press("Escape")
      await expect(card).toBeHidden()
      await expect(page).toHaveURL(/\/animations\/harbour$/)

      await press(sea.islands.find(island => island.name === "forge")!.at)
      await expect(page).toHaveURL(/\/animations\/harbour\/forge$/)
      await expect(page.getByRole("heading", {level: 1})).toHaveText("Forge")
      await problems.expect()
    })
  })
}
