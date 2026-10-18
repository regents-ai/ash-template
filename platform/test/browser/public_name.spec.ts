import {expect, test} from "@playwright/test"
import {keepSignedIn, ready, signedIn, watch} from "./support/person"

// The Public Display Name form on the Account page. A save needs the browser's own
// sign-in with Privy, which never completes at the walk's address, so Save must
// finish, say why, send no change, and leave the form where it was. A save that
// goes through is proved by test/ash_template_web/public_name_test.exs.
test.use(signedIn)
test.beforeEach(({context}) => keepSignedIn(context))

test("Save without the browser's sign-in refuses and changes nothing", async ({page}) => {
  const problems = watch(page)
  const changes: string[] = []
  page.on("request", request => {
    if (new URL(request.url()).pathname.startsWith("/api/v1/profile") && request.method() !== "GET")
      changes.push(`${request.method()} ${request.url()}`)
  })
  await page.goto("/account")
  await ready(page)
  const form = page.locator("#account-public-name")
  const name = form.getByLabel("Public Display Name")
  const save = form.getByRole("button", {name: "Save"})
  await expect(name).toBeVisible()
  await expect(save).toBeVisible()
  // Where Save sits in the form, and how tall the form is, wherever the page scrolls.
  const place = () => Promise.all([form.boundingBox(), save.boundingBox()])
    .then(([f, b]) => ({x: b!.x - f!.x, y: b!.y - f!.y, height: f!.height}))
  const before = await place()

  await name.fill("Ada Lovelace")
  await save.click()
  await expect(form.locator("form")).not.toHaveAttribute("aria-busy")
  await expect(form.getByRole("status")).not.toBeEmpty()
  expect(changes).toEqual([])
  // The message sits beside Save without moving it.
  expect(await place()).toEqual(before)
  await problems.expect()
})
