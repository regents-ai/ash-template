import type {Locator} from "@playwright/test"
import {expect, test} from "./support/test"
import {ready, resting, signedIn, watch} from "./support/person"

// Each width gives its own agent a picture (sign_in.exs pairs Desktop Picture and
// Phone Picture), so the two never meet. A PNG chosen in the agent's window shows
// before it is saved; once saved, the window shows the kept picture, which the site
// serves to anyone as a WebP at its own address. Removed, the agent's mark is back
// and the address serves nothing.
test.use(signedIn)

// A 16 by 16 PNG.
const png = Buffer.from(
  "iVBORw0KGgoAAAANSUhEUgAAABAAAAAQCAIAAACQkWg2AAABlklEQVR4nBXRURVEIQhFUSMYgQhGMAIRiGCEE8EIRiACEYhABCLMG7/ZrMt1jMEcyGAN9kAHNjgDBnfwBj6IQQ5q0IMxJnMikzXZE53Y5EyY3Mmb+CQmOalJzw8IUxBhCVtQwYQjIFzhCS6EkEIJLR9YzIUs1mIvdGGLs2BxF2/hi1jkoha9PrCZG9mszd7oxjZnw+Zu3sY3sclNbXp/QJmKKEvZiiqmHAXlKk9xJZRUSmn9gDENMZaxDTXMOAbGNZ7hRhhplNH2gcM8yGEd9kEPdjgHDvfwDn6IQx7q0OcD/wK/Sr4jv9hfkG/1N/x/Fx44BCQU9Pc94zIvclmXfdGLXc79j9/Lu/glLnmpS98PPOZDHuuxH/qwx3n/5ffxHv6IRz7q0e8DznTEWc521DHn+D/KdZ7jTjjplNP+gWAGEqxgBxpYcOIf/AYv8CCCDCro+EAyE0lWshNNLDn5P/MmL/Ekkkwq6fxAMQspVrELLaw49S/lFq/wIoosquj6QDMbaVazG22sOf2v8Dav8SaabKrp5geIAnAQEbP2+wAAAABJRU5ErkJggg==",
  "base64",
)

test("an agent's window saves and removes its picture", async ({page, hasTouch}, testInfo) => {
  const press = (target: Locator) => (hasTouch ? target.tap() : target.click())
  const problems = watch(page)
  const agent = testInfo.project.name === "phone" ? "Phone Picture" : "Desktop Picture"
  const wallet = `0x${(testInfo.project.name === "phone" ? "2" : "1").repeat(40)}`
  await page.goto("/account")
  await ready(page)
  await press(page.getByRole("button", {name: `See what ${agent} has done`}))

  const agentWindow = page.getByRole("dialog", {name: agent})
  await resting(agentWindow)
  const notice = agentWindow.locator("#account-agent-picture-notice")
  const kept = agentWindow.getByRole("img", {name: `${agent}’s picture`})
  await expect(kept).toHaveCount(0)

  await agentWindow.locator('input[type="file"]').setInputFiles({
    name: "agent.png",
    mimeType: "image/png",
    buffer: png,
  })
  await press(agentWindow.getByRole("button", {name: "Save picture"}))
  await expect(notice).toHaveText("Picture saved.")
  await expect(kept).toBeVisible()

  const src = await kept.getAttribute("src")
  expect(src).toMatch(new RegExp(`^/agents/${wallet}/picture\\?v=\\d+$`))
  const served = await page.request.get(src!)
  expect(served.status()).toBe(200)
  expect(served.headers()["content-type"]).toBe("image/webp")
  expect(served.headers()["cache-control"]).toBe("public, max-age=31536000, immutable")

  page.once("dialog", dialog => dialog.accept())
  await press(agentWindow.getByRole("button", {name: "Remove picture"}))
  await expect(notice).toHaveText("Picture removed.")
  await expect(kept).toHaveCount(0)
  expect((await page.request.get(src!)).status()).toBe(404)
  await problems.expect()
})
