import type {Page} from "@playwright/test"

// Founder rule, 2026-10-28 (UI-4): no title, label or name opens with who, what,
// where, why or when; it reads as machine-written. The legal pages keep their
// versioned headings. People's own words (room messages) are theirs.
export const wWordTitles = (page: Page) =>
  page.evaluate(() => {
    const opener = /^(who|what|where|why|when)\b/i
    const titles = 'h1, h2, h3, h4, h5, h6, summary, legend, label, th, caption, button, a, [role="tab"], [role="heading"]'
    const found: string[] = []
    const check = (text: string | null) => {
      const words = (text ?? "").trim().replace(/\s+/g, " ")
      if (opener.test(words)) found.push(words.slice(0, 60))
    }
    check(document.title)
    for (const element of document.body.querySelectorAll<HTMLElement>(titles))
      if (!element.closest("#room-messages")) check(element.textContent)
    for (const element of document.body.querySelectorAll<HTMLElement>("[aria-label], [title]"))
      if (!element.closest("#room-messages")) check(element.getAttribute("aria-label") ?? element.getAttribute("title"))
    return found
  })
