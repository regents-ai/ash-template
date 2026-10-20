import type {Page} from "@playwright/test"

// A box that scrolls must be reachable from the keyboard, or a person without a
// pointer cannot scroll it: the box itself takes focus (tabindex="0"), or holds
// something that does (the accessibility rule scrollable-region-focusable).
// These are the shown boxes that scroll and are out of a keyboard's reach.
export const unreachableScrollers = (page: Page) =>
  page.evaluate(() => {
    const focusable = 'a[href], button, input, select, textarea, summary, [tabindex]:not([tabindex="-1"])'
    const scrolls = (box: Element, overflow: string, extra: number) =>
      (overflow === "auto" || overflow === "scroll") && extra > 1
    const name = (box: Element) =>
      box.id ? `#${box.id}` : `${box.tagName.toLowerCase()}${[...box.classList].map(c => `.${c}`).join("")}`
    return [...document.body.querySelectorAll("*")]
      .filter(box => {
        const style = getComputedStyle(box)
        return (
          box.checkVisibility() &&
          (scrolls(box, style.overflowX, box.scrollWidth - box.clientWidth) ||
            scrolls(box, style.overflowY, box.scrollHeight - box.clientHeight)) &&
          !box.matches(focusable) &&
          !box.querySelector(focusable)
        )
      })
      .map(name)
  })
