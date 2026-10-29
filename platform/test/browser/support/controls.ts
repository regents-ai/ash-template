import type {Page} from "@playwright/test"

// Founder rule, 2026-10-29 (UI-3): a button is 2.5rem (40 px) tall or less for a
// mouse, and 44 px or more for a finger. These are pictures that happen to be
// pressable, sized by their art, not controls:
const artwork = [
  ".rl-product-tab", // home's product keys, 52 px as on regents.sh (Sean, 21 Oct)
  "#site-buttons .sb-site", // each site's own buttons, drawn as that site draws them
  ".sc-theme-options", // the showcase's palette cards
]

// Every button, disclosure row and button-styled link the page shows, with its
// height, when it breaks the rule for this pointer.
export const misSizedControls = (page: Page, touch: boolean) =>
  page.evaluate(
    ({touch, artwork}) => {
      const found: string[] = []
      const controls = document.querySelectorAll<HTMLElement>('button, [role="button"], summary, a.rg-button')
      for (const control of controls) {
        if (control.closest(['[inert]', '[aria-hidden="true"]', ...artwork].join(", "))) continue
        const box = control.getBoundingClientRect()
        if (box.width === 0 || box.height === 0 || getComputedStyle(control).visibility === "hidden") continue
        const height = Math.round(box.height * 10) / 10
        if (touch ? height < 44 : height > 40) {
          const name = (control.getAttribute("aria-label") ?? control.textContent ?? "").trim().replace(/\s+/g, " ")
          const where = control.id ? `#${control.id}` : `${control.tagName.toLowerCase()}.${[...control.classList].join(".")}`
          found.push(`${where} "${name.slice(0, 40)}" ${height}px`)
        }
      }
      return found
    },
    {touch, artwork},
  )

// Founder rule, 2026-10-29 (UI-6): one theme switch per page. Every theme switch
// the page draws, open or folded away, named as a person hears it.
export const themeSwitches = (page: Page) =>
  page.evaluate(() =>
    [...document.querySelectorAll<HTMLElement>("[data-theme-toggle]")]
      .filter(control => !control.closest('[inert], [aria-hidden="true"]'))
      .map(control => `#${control.id} "${control.getAttribute("aria-label") ?? control.textContent?.trim()}"`),
  )
