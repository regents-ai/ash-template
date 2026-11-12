import type {Page} from "@playwright/test"
import {expect, test} from "./support/test"
import {watch} from "./support/person"

// The particles lab (/animations/particles): 80,000 grains drawn on the GPU over a
// real control, an icon or a mark. These checks open it with the GPU on, see the
// grains draw and the loop move, choose every shape from the grid, work each
// control by pointer and by key and see the field follow, and open the page with
// odd addresses. With less motion the grains never draw and the controls still work.
test.use({launchOptions: {args: ["--enable-unsafe-webgpu", "--enable-gpu"]}})

const field = (page: Page) => page.locator("#particle-field")

/** The field's shape and value, as the grains read them. */
const shown = (page: Page) =>
  field(page).evaluate(element => ({shape: element.dataset.particleShape, value: Number(element.dataset.particleValue)}))

async function open(page: Page, query = "") {
  await page.goto(`/animations/particles${query}`)
  await expect(page.locator("[data-phx-main].phx-connected")).toBeAttached()
}

async function drawn(page: Page) {
  await expect(field(page)).toHaveAttribute("data-particle-ready", "true")
}

for (const width of [320, 390]) {
  test.describe(`at ${width} wide`, () => {
    test.use({viewport: {width, height: 700}})

    test("the grains draw, the loop moves and pauses, and the page fits the screen", async ({page}) => {
      const problems = watch(page)
      let crashed = false
      page.on("crash", () => {
        crashed = true
      })
      await open(page)
      await field(page).scrollIntoViewIfNeeded()
      await drawn(page)
      await expect(page.locator("#particle-lab")).toHaveAttribute("data-loop", "on")

      // The loop turns the switch on, then flies the grains into a ring.
      await expect.poll(async () => (await shown(page)).shape, {timeout: 10_000}).toBe("ring")
      await page.getByRole("button", {name: "Pause"}).click()
      await expect(page.getByRole("button", {name: "Play"})).toBeVisible()
      const held = await shown(page)
      await page.waitForTimeout(1500)
      expect(await shown(page)).toEqual(held)

      expect(crashed).toBe(false)
      await drawn(page)
      await problems.expect()
    })
  })
}

test("every shape in the grid can be chosen and holds the stage", async ({page}) => {
  const problems = watch(page)
  await open(page)
  await drawn(page)
  const links = page.locator(".particle-lab__shapes nav a")
  const count = await links.count()
  expect(count).toBeGreaterThanOrEqual(24)
  for (let n = 0; n < count; n++) {
    const link = links.nth(n)
    const shape = new URL((await link.getAttribute("href"))!, "http://x").searchParams.get("shape")!
    await link.click()
    await expect(link).toHaveAttribute("aria-current", "page")
    await expect(page.locator("#particle-lab")).toHaveAttribute("data-loop", "off")
    await expect.poll(async () => (await shown(page)).shape).toBe(shape)
  }
  await drawn(page)
  await problems.expect()
})

test.describe("the controls drive the grains", () => {
  test("the switch, by press, Space and Enter", async ({page}) => {
    await open(page, "?shape=switch")
    const toggle = page.getByRole("switch", {name: "Switch"})
    await toggle.click()
    await expect(toggle).toHaveAttribute("aria-checked", "true")
    expect((await shown(page)).value).toBe(1)
    await toggle.focus()
    await page.keyboard.press("Space")
    await expect(toggle).toHaveAttribute("aria-checked", "false")
    expect((await shown(page)).value).toBe(0)
    await page.keyboard.press("Enter")
    await expect(toggle).toHaveAttribute("aria-checked", "true")
    expect((await shown(page)).value).toBe(1)
  })

  test("the slider, by pointer and by keys", async ({page}) => {
    await open(page, "?shape=slider")
    const slider = page.getByRole("slider", {name: "Level"})
    const box = (await slider.boundingBox())!
    await page.mouse.click(box.x + box.width * 0.8, box.y + box.height / 2)
    await expect.poll(async () => (await shown(page)).value).toBeGreaterThan(0.6)
    await slider.focus()
    await page.keyboard.press("Home")
    await expect.poll(async () => (await shown(page)).value).toBe(0)
    await page.keyboard.press("ArrowRight")
    await expect.poll(async () => (await shown(page)).value).toBeCloseTo(0.01)
    await page.keyboard.press("End")
    await expect.poll(async () => (await shown(page)).value).toBe(1)
  })

  test("the checkbox, by press and Space", async ({page}) => {
    await open(page, "?shape=checkbox")
    const box = page.getByRole("checkbox", {name: "Done"})
    await expect(box).toBeChecked()
    await box.click()
    await expect(box).not.toBeChecked()
    expect((await shown(page)).value).toBe(0)
    await page.keyboard.press("Space")
    await expect(box).toBeChecked()
    expect((await shown(page)).value).toBe(1)
  })

  test("the radio, by press and arrow keys", async ({page}) => {
    await open(page, "?shape=radio")
    await page.getByRole("radio", {name: "Large"}).check()
    await expect.poll(async () => (await shown(page)).value).toBe(1)
    await page.keyboard.press("ArrowLeft")
    await expect(page.getByRole("radio", {name: "Medium"})).toBeChecked()
    await expect.poll(async () => (await shown(page)).value).toBe(0.5)
  })

  test("the ring's Amount fills it and its progress bar together", async ({page}) => {
    await open(page, "?shape=ring")
    const amount = page.getByRole("slider", {name: "Amount"})
    await amount.focus()
    await page.keyboard.press("End")
    await expect.poll(async () => (await shown(page)).value).toBe(1)
    await expect(page.getByRole("progressbar", {name: "Progress"})).toHaveJSProperty("value", 100)
    await page.keyboard.press("Home")
    await expect.poll(async () => (await shown(page)).value).toBe(0)
    await expect(page.getByRole("progressbar", {name: "Progress"})).toHaveJSProperty("value", 0)
  })
})

test("odd addresses play the loop", async ({page}) => {
  for (const query of ["?shape[]=ring", "?shape[ring]=bar", "?shape=nothing", "?shape=", "?shape=icon:", "?shape=steps:99"]) {
    const response = await page.goto(`/animations/particles${query}`)
    expect(response!.status()).toBe(200)
    await expect(page.locator("#particle-lab")).toHaveAttribute("data-loop", "on")
  }
})

test.describe("with less motion", () => {
  test.use({reducedMotion: "reduce"})

  test("the grains never draw, the loop stays still and the controls still work", async ({page}) => {
    await open(page)
    await field(page).scrollIntoViewIfNeeded()
    // Longer than the loop takes to turn the switch on and leave it.
    await page.waitForTimeout(4500)
    expect(await shown(page)).toEqual({shape: "switch", value: 0})
    await expect(field(page)).not.toHaveAttribute("data-particle-ready", "true")
    await expect(page.locator("#particle-field-stage")).toHaveCSS("visibility", "hidden")

    const toggle = page.getByRole("switch", {name: "Switch"})
    await toggle.click()
    await expect(toggle).toHaveAttribute("aria-checked", "true")
    expect(await shown(page)).toEqual({shape: "switch", value: 1})
  })
})
