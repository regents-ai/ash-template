import {randomUUID} from "node:crypto"
import {expect, test} from "./support/test"
import {signedIn, watch} from "./support/person"

// The assistant's reply streams onto the page that sent the message, a few words at
// a time, and then arrives whole in their place. A second page opened while the reply
// is on its way never shows part of it: it says the assistant is writing until the
// whole reply arrives.
test.use(signedIn)

test("a reply streams onto the open page, and a page opened mid-reply shows it only whole", async ({page, context}) => {
  const problems = watch(page)
  await page.goto("/chat")
  await expect(page.locator("[data-phx-main].phx-connected")).toBeAttached()

  const words = `Where do the pines go? ${randomUUID().slice(0, 8)}`
  await page.locator("#chat-message-text").fill(words)
  await page.getByRole("button", {name: "Send"}).click()

  // A piece of the reply is on the page before the reply is whole.
  await expect(page.locator("[data-reply]")).not.toBeEmpty()

  const late = await context.newPage()
  await late.addInitScript(() => {
    const seen = {part: false, writing: false}
    Object.assign(window, {seen})
    new MutationObserver(() => {
      if (document.querySelector("[data-reply]")) seen.part = true
      if (document.querySelector(".chat-writing")) seen.writing = true
    }).observe(document, {childList: true, subtree: true})
  })
  await late.goto(page.url())

  for (const open of [page, late]) {
    await expect(open.locator("[data-reply]")).toHaveCount(0)
    await expect(open.locator(".chat-message[data-source='agent']").last()).toContainText(words)
    await expect(open.locator(".chat-writing")).toHaveCount(0)
  }

  expect(await late.evaluate(() => (window as unknown as {seen: object}).seen)).toEqual({
    part: false,
    writing: true,
  })
  await problems.expect()
})
