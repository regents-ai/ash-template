import type {Page} from "@playwright/test"

// Founder rule, 2026-10-19: every ENS name, full address or short address a page
// shows opens and copies the full address (Regent.Primitives.address). These are
// the ones shown outside it.
export const bareAddresses = (page: Page) =>
  page.evaluate(() => {
    const address = /0x[0-9a-fA-F]{40}|0x[0-9a-fA-F]{4,6}(?:\.{2,3}|\u2026)[0-9a-fA-F]{4,6}|\b[a-z0-9-]+\.eth\b/g
    const texts = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT)
    const found: string[] = []
    for (let node = texts.nextNode(); node; node = texts.nextNode())
      if (!node.parentElement?.closest(".rg-address, script, style, template"))
        found.push(...(node.textContent!.match(address) ?? []))
    return found
  })
