import type {Page} from "@playwright/test"
import {expect, test} from "./support/test"

// The homepage, as regents.sh's: the datascape fills the window, with one glass panel
// over it that holds the header, the name and its line, the actions, the product tabs
// and the document links, and the copyright at the window's bottom right.
const waitForHomepage = async (page: Page) => {
  await expect(page.locator("#public-home")).toBeVisible()
  // The suite's browser draws no picture, so the panel stands open once the page knows that.
  await expect(page.locator("#home-glass")).toHaveCSS("opacity", "1")
  await page.evaluate(async () => {
    await document.fonts.ready
    await Promise.all([...document.images].filter(image => !image.complete).map(image => image.decode()))
  })
}

const assertNoOverflow = async (page: Page) => {
  expect(
    await page.evaluate(() => document.documentElement.scrollWidth - document.documentElement.clientWidth),
  ).toBe(0)
}

const boxOf = (page: Page, selector: string) =>
  page.locator(selector).first().evaluate(element => element.getBoundingClientRect().toJSON() as DOMRect)

// The four product sites, in the order the panel's tabs list them before Protocol.
const products = [
  {name: "Autolaunch", site: "https://autolaunch.sh"},
  {name: "Techtree", site: "https://techtree.sh"},
  {name: "Patchbay", site: "https://patchbay.help"},
  {name: "Keyfleet", site: "https://keyfleet.ai"},
]

test("the homepage is server-readable: name, line, actions and products", async ({browser}) => {
  const context = await browser.newContext({javaScriptEnabled: false})
  const page = await context.newPage()
  await page.goto("/")

  const glass = page.locator("#home-glass")
  await expect(page.getByRole("heading", {level: 1})).toHaveText("Ash Template")
  await expect(glass.locator(".rl-statement__line")).toHaveText(
    "We build tools for people and their agents. REGENT stakers share in the revenue.",
  )
  await expect(glass.getByRole("link", {name: "Enter App"})).toHaveAttribute("href", "/app")
  await expect(glass.getByRole("button", {name: "WebMCP Tools"}).first()).toBeVisible()
  await expect(glass.getByRole("link", {name: "Connect your agent from the command line"})).toHaveAttribute(
    "href",
    "/agents",
  )

  const tabs = glass.getByRole("navigation", {name: "Products"}).getByRole("link")
  await expect(tabs).toHaveCount(5)
  for (const [index, {name, site}] of products.entries()) {
    await expect(tabs.nth(index)).toHaveText(`${name}, opens in a new tab`)
    await expect(tabs.nth(index)).toHaveAttribute("href", site)
    await expect(tabs.nth(index)).toHaveAttribute("target", "_blank")
  }
  await expect(tabs.nth(4)).toHaveText("Protocol")
  await expect(tabs.nth(4)).toHaveAttribute("href", "https://regents.sh/stake")

  await expect(glass.getByRole("heading", {level: 2, name: "Products"})).toBeVisible()
  // The copyright stands outside the panel, at the window's bottom right.
  await expect(page.locator("#public-home > .home__copyright")).toHaveText("© 2026 Regents Labs")
  // Without scripts the picture is the server's still one, behind the panel.
  await expect(page.locator(".home__still")).toBeVisible()
  await expect(page.locator("#home-canvas")).toBeHidden()

  await context.close()
})

// With less motion asked for, the picture stays the server's still one and the panel
// stands open at its full size from the start.
test("with less motion the still picture stays and the panel is open", async ({browser}) => {
  const context = await browser.newContext({reducedMotion: "reduce"})
  const page = await context.newPage()
  await page.goto("/")
  await waitForHomepage(page)
  await expect(page.locator("[data-phx-main].phx-connected")).toBeAttached()
  await expect(page.locator(".home__still")).toBeVisible()
  await expect(page.locator("#public-home")).not.toHaveAttribute("data-datascape-ready", "true")
  const glass = page.locator("#home-glass")
  await expect(glass).toHaveCSS("opacity", "1")
  await expect(glass).toHaveCSS("transform", "none")
  await expect(glass).toHaveCSS("pointer-events", "auto")
  await context.close()
})

// A page whose script never arrives keeps the panel out of sight for four seconds, like a
// page still starting, then brings it in by itself, so its links are never lost.
test("the panel comes in by itself when the page's script never arrives", async ({page}) => {
  await page.route("**/assets/js/app.js*", route => route.abort())
  await page.goto("/")
  const glass = page.locator("#home-glass")
  await expect(glass).toHaveCSS("opacity", "0")
  await expect(glass).toHaveCSS("pointer-events", "none")
  await expect(glass).toHaveCSS("opacity", "1", {timeout: 6000})
  await expect(glass).toHaveCSS("transform", "none")
  await expect(glass).toHaveCSS("pointer-events", "auto")
  await expect(page.locator("#public-home")).not.toHaveAttribute("data-datascape-glass-state")
})

// The panel stands in the middle of the window and holds the whole page: its header, the
// name and actions, the product tabs, then the document links, each inside its edges at
// every width. A panel taller than the window scrolls the page while the picture stays
// put, and its foot ends above the copyright at the window's bottom right.
for (const viewport of [
  {name: "320", width: 320, height: 568},
  {name: "390", width: 390, height: 844},
  {name: "768", width: 768, height: 1024},
  {name: "1440", width: 1440, height: 900},
]) {
  test(`the panel holds the page at ${viewport.name} wide`, async ({page}) => {
    await page.setViewportSize({width: viewport.width, height: viewport.height})
    await page.goto("/")
    await waitForHomepage(page)
    await assertNoOverflow(page)

    const glass = await boxOf(page, "#home-glass")
    expect(Math.abs(glass.left - (viewport.width - glass.right)), "centred across").toBeLessThan(2)
    expect(glass.width).toBeLessThanOrEqual(Math.min(704, viewport.width - 32) + 1)
    // A page that fits the window holds the panel in its middle; a taller one scrolls.
    const fits = await page.evaluate(() => document.scrollingElement!.scrollHeight <= innerHeight)
    if (fits) {
      expect(Math.abs(glass.top - (viewport.height - glass.bottom)), "centred down").toBeLessThan(2)
    }

    const parts = await Promise.all(
      [".rl-header", "#home-title", ".rl-hero-actions", "#home-products-title", ".rl-product-tabs"].map(selector =>
        boxOf(page, selector),
      ),
    )
    for (const [index, box] of parts.entries()) {
      expect(box.left, `part ${index} inside the panel`).toBeGreaterThanOrEqual(glass.left)
      expect(box.right, `part ${index} inside the panel`).toBeLessThanOrEqual(glass.right)
      if (index > 0) expect(box.top, `part ${index} in order`).toBeGreaterThanOrEqual(parts[index - 1]!.top)
    }
    for (const selector of [".rl-product-tab", ".rl-header-links > *"]) {
      const boxes = await page.locator(selector).evaluateAll(elements =>
        elements.map(element => element.getBoundingClientRect().toJSON() as DOMRect),
      )
      expect(boxes.length, `${selector} shown`).toBeGreaterThan(0)
      expect(
        boxes.every(box => box.left >= glass.left - 0.5 && box.right <= glass.right + 0.5),
        `${selector} inside the panel`,
      ).toBe(true)
    }

    // The whole panel can be scrolled into view, and the picture stays put behind it.
    await page.evaluate(() => window.scrollTo(0, document.scrollingElement!.scrollHeight))
    const scrolled = await boxOf(page, "#home-glass")
    expect(scrolled.bottom, "the panel's foot is reachable").toBeLessThanOrEqual(viewport.height + 1)
    const copyright = await boxOf(page, ".home__copyright")
    expect(copyright.bottom, "the copyright inside the window").toBeLessThanOrEqual(viewport.height)
    expect(copyright.right, "the copyright inside the window").toBeLessThanOrEqual(viewport.width)
    if (!fits) {
      const foot = await boxOf(page, ".home__foot")
      expect(foot.bottom, "the panel's foot ends above the copyright").toBeLessThanOrEqual(copyright.top)
    }
    const still = await boxOf(page, ".home__still")
    expect(still.top).toBe(0)
    expect(still.height).toBe(viewport.height)
  })
}

// The picture behind the panel is drawn by the browser: hidden from assistive technology
// and behind the panel, so the heading and every action stay on top and reachable whether
// headless Chromium brings a GPU or not, and with less motion asked for.
test("the picture behind the panel never blocks the action", async ({page}) => {
  for (const viewport of [{width: 1280, height: 800}, {width: 390, height: 844}]) {
    await page.setViewportSize(viewport)
    await page.goto("/")
    await expect(page.locator(".home__still")).toHaveAttribute("aria-hidden", "true")
    await expect(page.locator("#home-canvas")).toHaveAttribute("aria-hidden", "true")
    for (const reducedMotion of ["no-preference", "reduce"] as const) {
      await page.emulateMedia({reducedMotion})
      await expect(page.locator("#home-title")).toBeVisible()
      // The panel is up once the page knows this browser draws no picture.
      await expect(page.locator("#home-glass")).toHaveCSS("opacity", "1")
      const action = page.locator(".rl-hero-actions a").first()
      await action.scrollIntoViewIfNeeded()
      // The panel, not the picture, is what a press at the action lands on.
      expect(
        await action.evaluate(element => {
          const box = element.getBoundingClientRect()
          return element.contains(document.elementFromPoint(box.x + box.width / 2, box.y + box.height / 2))
        }),
      ).toBe(true)
      await page.locator("#home-content .rl-hero-secondary").click({trial: true})
      await page.locator("#home-nav-techtree").click({trial: true})
    }
    await page.emulateMedia({reducedMotion: "no-preference"})
  }
})

// Under the buttons, one line sends a person whose agent works from the command line
// to the steps for connecting it.
test("the panel points agents to the command line", async ({page}) => {
  await page.goto("/")
  await waitForHomepage(page)
  await assertNoOverflow(page)

  const link = page.locator("#home-content").getByRole("link", {name: "Connect your agent from the command line"})
  await link.scrollIntoViewIfNeeded()
  await expect(link).toBeInViewport()
  const [line, actions, tabs] = await Promise.all(
    [link, page.locator(".rl-hero-actions"), page.locator(".rl-product-tabs")].map(locator =>
      locator.evaluate(element => element.getBoundingClientRect().toJSON()),
    ),
  )
  expect(line.top, "the line sits under the buttons").toBeGreaterThanOrEqual(actions.bottom)
  expect(line.bottom, "and above the product tabs").toBeLessThanOrEqual(tabs.top)
  expect(line.height, "a full tap target").toBeGreaterThanOrEqual(44)

  await link.click()
  await expect(page).toHaveURL(/\/agents$/)
  await expect(page.getByRole("heading", {name: "Agents", level: 1})).toBeVisible()
})
