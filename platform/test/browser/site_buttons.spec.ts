import type {Locator, Page} from "@playwright/test"
import {expect, test} from "./support/test"

// The buttons lab, /animations/buttons: each site's column wears that site's own theme
// from the design system, so its main button is the brand's own and stands out from its
// panel, and the frozen "Hover" and "Keyboard focus" are what a mouse and a key really bring.
const sites = ["regents", "autolaunch", "techtree", "patchbay"]

async function open(page: Page, baseURL: string, theme: "light" | "dark") {
  await page.context().addCookies([{name: "regent_theme", value: theme, url: baseURL}])
  await page.goto("/animations/buttons")
  await expect(page.locator('#site-buttons[data-brands-ready="true"]')).toBeAttached()
}

const stageButton = (page: Page, site: string) => page.locator(`#sb-${site} .sb-today .sb-stage .sb-button`)

// The colour that marks the button out on its panel: a main button's fill, a secondary
// one's edge, and the panel's fill under it, each as the browser draws it.
const paint = (button: Locator) =>
  button.evaluate(element => {
    const probe = document.createElement("canvas").getContext("2d", {willReadFrequently: true})!
    const rgb = (color: string) => {
      probe.clearRect(0, 0, 1, 1)
      probe.fillStyle = color
      probe.fillRect(0, 0, 1, 1)
      return Array.from(probe.getImageData(0, 0, 1, 1).data.slice(0, 3))
    }
    const skin = getComputedStyle(element, "::before")
    const context = element.closest(".sb-context")!
    const panel = context.classList.contains("rg-panel")
      ? getComputedStyle(context, "::after").backgroundColor
      : getComputedStyle(context).backgroundColor
    const secondary = element.classList.contains("rg-button--secondary")
    return {mark: rgb(secondary ? skin.borderTopColor : skin.backgroundColor), panel: rgb(panel)}
  })

const contrast = (a: number[], b: number[]) => {
  const lum = (c: number[]) => {
    const [r, g, bl] = c.map(v => v / 255).map(v => (v <= 0.04045 ? v / 12.92 : ((v + 0.055) / 1.055) ** 2.4))
    return 0.2126 * r + 0.7152 * g + 0.0722 * bl
  }
  const [x, y] = [lum(a), lum(b)].sort((p, q) => q - p)
  return (x + 0.05) / (y + 0.05)
}

// What hover or keyboard focus draws on a button: its outline when it draws one, and the
// paint skin's ring (its width, reach and cut) and marks. The skin's own fill and edge
// colour, and an undrawn outline's colour, are left out: a secondary button takes those
// from the panel it sits on.
const statePaint = (button: Locator) =>
  button.evaluate(element => {
    const own = getComputedStyle(element)
    const skin = getComputedStyle(element, "::before")
    return {
      outline: own.outlineStyle === "none"
        ? "none"
        : `${own.outlineStyle} ${own.outlineWidth} ${own.outlineColor} ${own.outlineOffset}`,
      ring: skin.borderTopWidth,
      skin: [skin.inset, skin.clipPath, skin.backgroundSize, skin.backgroundImage].join(" | "),
    }
  })

for (const theme of ["light", "dark"] as const) {
  test(`each site's column shows its own brand's main button, in ${theme}`, async ({page, baseURL}) => {
    await open(page, baseURL!, theme)
    const paints = await Promise.all(sites.map(site => paint(stageButton(page, site))))
    // Four brands, four different buttons.
    expect(new Set(paints.map(({mark}) => mark.join())).size).toBe(sites.length)
    for (const [index, site] of sites.entries()) {
      // Autolaunch's Tangerine is its brand fill and the one main button the design
      // system lets stand under 3:1 on its page (STYLE.md, Shape and spacing).
      if (site === "autolaunch") continue
      expect(contrast(paints[index].mark, paints[index].panel), site).toBeGreaterThanOrEqual(3)
    }
  })

  test(`the keyboard focus specimen is the ring a key brings, in ${theme}`, async ({page, baseURL}) => {
    await open(page, baseURL!, theme)
    for (const site of sites) {
      const button = stageButton(page, site)
      await button.focus()
      await page.keyboard.press("Shift+Tab")
      await page.keyboard.press("Tab")
      await expect(button).toBeFocused()
      expect(await button.evaluate(element => element.matches(":focus-visible"))).toBe(true)
      // Both grow their marks in over 150 ms, the frozen one once the page has dressed it.
      const specimen = page.locator(`#sb-${site} .sb-today li[data-show="focus"] .sb-button`)
      const both = async () => {
        const [real, frozen] = await Promise.all([statePaint(button), statePaint(specimen)])
        return {real, frozen, same: JSON.stringify(real) === JSON.stringify(frozen)}
      }
      await expect.poll(async () => (await both()).same, {message: site}).toBe(true)
      const {real} = await both()
      // The ring is drawn: an outline, or the cut ring, at least the shared 2px, on the skin.
      expect(real.outline.startsWith("solid") || parseFloat(real.ring) >= 2, site).toBe(true)
    }
  })

  test(`the hover specimen is what a mouse really brings, in ${theme}`, async ({page, baseURL, hasTouch}) => {
    await open(page, baseURL!, theme)
    const specimen = (site: string, show: string) => page.locator(`#sb-${site} .sb-today li[data-show="${show}"] .sb-button`)
    const same = async (a: Locator, b: Locator) =>
      JSON.stringify(await statePaint(a)) === JSON.stringify(await statePaint(b))
    if (hasTouch) {
      // No mouse on a phone, yet the frozen hover still wears the marks a mouse brings.
      // Techtree's Copy is a secondary button, which the shared button leaves as it is on hover.
      for (const site of sites.filter(site => site !== "techtree")) {
        await expect.poll(() => same(specimen(site, "hover"), specimen(site, "rest")), {message: site}).toBe(false)
      }
      return
    }
    for (const site of sites) {
      const button = stageButton(page, site)
      await button.hover()
      expect(await button.evaluate(element => element.matches(":hover"))).toBe(true)
      // Both grow their marks in over 150 ms, the frozen one once the page has dressed it.
      await expect.poll(() => same(button, specimen(site, "hover")), {message: site}).toBe(true)
    }
  })
}
