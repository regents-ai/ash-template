import type {Locator, Page} from "@playwright/test"

// What a copy button showed for one press: its answer, the words on the button then
// (none on an icon), and the words its polite status read out.
export type Copy = {answer: string; shown: string; said: string}

// A copy button shows its answer for 1.6 seconds (assets/js/copy_buttons.ts), so a
// check that looks from outside can look after it has gone on a busy machine. The
// page records each answer every copy button shows, with the words on the button and
// in its status at that moment, and a check reads the button's record. Call it before
// the page opens.
export const recordCopies = (page: Page) =>
  page.addInitScript(() => {
    const shown = new WeakMap<Element, Copy[]>()
    Object.assign(window, {copiesShown: shown})
    new MutationObserver(records => {
      for (const {target} of records) {
        const button = target as HTMLElement
        const answer = button.dataset.copyState
        if (!answer) continue
        const said = document.getElementById(button.dataset.copyStatus ?? "")?.textContent ?? ""
        shown.set(button, [...(shown.get(button) ?? []), {answer, shown: button.innerText.trim(), said}])
      }
    }).observe(document, {subtree: true, attributes: true, attributeFilter: ["data-copy-state"]})
  })

// What one copy button has shown, oldest first.
export const copiesShown = (button: Locator) =>
  button.evaluate(el => (window as unknown as {copiesShown: WeakMap<Element, Copy[]>}).copiesShown.get(el) ?? [])
