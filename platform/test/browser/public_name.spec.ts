import {expect, test} from "./support/test"
import {ready, signedIn, watch} from "./support/person"

// The Public Display Name form on the Account page saves with the page's own
// sign-in: its session cookie and forms token. The walk's person saves the name
// they already have (sign_in.exs), so every other page on the walk still shows it.
test.use(signedIn)

const walkName = "W".repeat(80)

test("Save keeps the name with the page's own sign-in", async ({page}) => {
  const problems = watch(page)
  await page.goto("/account")
  await ready(page)
  const form = page.locator("#account-public-name")
  const name = form.getByRole("textbox", {name: "Public Display Name"})
  const save = form.getByRole("button", {name: "Save"})
  await expect(name).toBeVisible()
  await expect(save).toBeVisible()
  // Where Save sits in the form, and how tall the form is, wherever the page scrolls.
  const place = () => Promise.all([form.boundingBox(), save.boundingBox()])
    .then(([f, b]) => ({x: b!.x - f!.x, y: b!.y - f!.y, height: f!.height}))
  const before = await place()

  await name.fill(walkName)
  const change = page.waitForResponse(response =>
    new URL(response.url()).pathname === "/api/v1/profile" && response.request().method() === "PATCH")
  await save.click()
  expect((await change).status()).toBe(200)
  await expect(form.locator("form")).not.toHaveAttribute("aria-busy")
  await expect(form.getByRole("status")).not.toBeEmpty()
  await expect(name).toHaveValue(walkName)
  // The message sits beside Save without moving it.
  expect(await place()).toEqual(before)
  await problems.expect()
})
