import type {Page} from "@playwright/test"
import {expect, test} from "./support/test"
import {watch} from "./support/person"

// The cells lab (/animations/cells): the design system's Cells meter with its moving
// picture drawn on the GPU. These checks open it with the GPU on and see the picture
// take over from the still cells, add, resize and remove a holder and see the meter's
// parts follow while the picture keeps drawing, see a holder let go rise as sparks
// into the room above the bar and leave it empty again, start and stop counting, and
// fit the page at 320 and 390 wide. With less motion the picture never starts and the
// still cells stay.
test.use({launchOptions: {args: ["--enable-unsafe-webgpu", "--enable-gpu"]}})

const meter = (page: Page) => page.locator("#cells-lab-meter")

/** Each part's key and share, as the moving picture reads them. */
const parts = (page: Page) =>
  meter(page)
    .locator("[data-cells-key]")
    .evaluateAll(items =>
      items.map(item => [(item as HTMLElement).dataset.cellsKey, Number((item as HTMLElement).style.getPropertyValue("--rg-cells-share"))]),
    )

async function open(page: Page) {
  await page.goto("/animations/cells")
  await expect(page.locator("[data-phx-main].phx-connected")).toBeAttached()
  await meter(page).scrollIntoViewIfNeeded()
}

async function drawn(page: Page) {
  await expect(meter(page)).toHaveAttribute("data-cells-ready", "true")
  // The still cells give way to the picture.
  await expect(meter(page).locator(".rg-cells__track")).toHaveCSS("visibility", "hidden")
}

/** The canvas above the bar, short of the bar's own top edge, in page pixels. */
async function room(page: Page) {
  const canvas = (await meter(page).locator("[data-cells-canvas]").boundingBox())!
  const bar = (await meter(page).locator(".rg-cells__track").boundingBox())!
  return {x: canvas.x, y: canvas.y, width: canvas.width, height: bar.y - canvas.y - 2}
}

for (const width of [320, 390]) {
  test.describe(`at ${width} wide`, () => {
    test.use({viewport: {width, height: 700}})

    test("the picture draws and the page fits the screen", async ({page}) => {
      const problems = watch(page)
      await open(page)
      await drawn(page)
      expect(await page.evaluate(() => document.documentElement.scrollWidth)).toBeLessThanOrEqual(width)
      await page.getByRole("button", {name: "Narrow"}).click()
      await expect(page.getByRole("button", {name: "Narrow"})).toHaveAttribute("aria-pressed", "true")
      expect(await page.evaluate(() => document.documentElement.scrollWidth)).toBeLessThanOrEqual(width)
      await drawn(page)
      await problems.expect()
    })
  })
}

test("a holder is added, resized and removed, and the picture follows", async ({page}) => {
  const problems = watch(page)
  await open(page)
  await drawn(page)
  expect((await parts(page)).map(([key]) => key)).toEqual(["treasury", "liquidity", "team", "community"])

  await page.getByRole("button", {name: "Add"}).click()
  await expect.poll(async () => (await parts(page)).map(([key]) => key)).toEqual(["treasury", "liquidity", "team", "community", "rewards"])

  await page.getByLabel("Treasury", {exact: true}).fill("40")
  await expect.poll(async () => (await parts(page))[0]).toEqual(["treasury", 0.4])
  await expect(page.locator("#cells-lab-meter .rg-cells__used")).toHaveText("85M")

  await page.getByRole("button", {name: "Remove Liquidity"}).click()
  await expect.poll(async () => (await parts(page)).map(([key]) => key)).toEqual(["treasury", "team", "community", "rewards"])
  // Liquidity comes back in its own place in the bar.
  await page.getByRole("button", {name: "Add"}).click()
  await expect.poll(async () => (await parts(page)).map(([key]) => key)).toEqual(["treasury", "liquidity", "team", "community", "rewards"])

  await drawn(page)
  await problems.expect()
})

test("a holder let go rises as sparks above the bar, gone a second later", async ({page}) => {
  const problems = watch(page)
  await open(page)
  await drawn(page)
  // The words under the room above the bar are hidden, so only the picture can draw there.
  await page.addStyleTag({content: "#cells-lab-meter :is(.rg-cells__total, .rg-cells__status) { visibility: hidden }"})
  await expect(meter(page).locator(".rg-cells__status")).toHaveCSS("visibility", "hidden")
  const above = await room(page)
  const empty = await page.screenshot({clip: above})

  await page.getByRole("button", {name: "Remove Treasury"}).click()
  await expect
    .poll(async () => (await page.screenshot({clip: above})).equals(empty), {intervals: [0], timeout: 1500})
    .toBe(false)
  await page.waitForTimeout(1000)
  expect((await page.screenshot({clip: above})).equals(empty)).toBe(true)
  await problems.expect()
})

test("counting starts and stops", async ({page}) => {
  const problems = watch(page)
  await open(page)
  await drawn(page)
  await page.getByRole("button", {name: "Count"}).click()
  await expect(meter(page)).toHaveAttribute("data-cells-state", "counting")
  await expect(meter(page)).toHaveAttribute("aria-busy", "true")
  await page.getByLabel("Team", {exact: true}).fill("20")
  await expect.poll(async () => (await parts(page))[2]).toEqual(["team", 0.2])
  await page.getByRole("button", {name: "Stop"}).click()
  await expect(meter(page)).toHaveAttribute("data-cells-state", "idle")
  await expect(meter(page)).not.toHaveAttribute("aria-busy", /.*/)
  await drawn(page)
  await problems.expect()
})

test.describe("with less motion", () => {
  test.use({reducedMotion: "reduce"})

  test("the picture never starts and the still cells stay", async ({page}) => {
    await open(page)
    await page.waitForTimeout(1500)
    await expect(meter(page)).not.toHaveAttribute("data-cells-ready", /.*/)
    await expect(meter(page).locator(".rg-cells__track")).toHaveCSS("visibility", "visible")

    await page.getByRole("button", {name: "Remove Team"}).click()
    await expect.poll(async () => (await parts(page)).map(([key]) => key)).toEqual(["treasury", "liquidity", "community"])
    await expect(meter(page)).not.toHaveAttribute("data-cells-ready", /.*/)
  })
})
