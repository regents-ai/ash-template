import {randomUUID} from "node:crypto"
import {expect, onThisMachine, test} from "./support/test"
import {signedIn, watch} from "./support/person"

// The longest note the boxes take, in a character that is 9 bytes once the page sends
// it, reaches the site in one message: the page's connection stays open and the note
// is saved. A hidden character is refused under the box it is in once the
// writer leaves the box.
test.use(signedIn)

test("the longest note the boxes take is saved, and a hidden character is refused", async ({page, hasTouch}) => {
  const press = (target: ReturnType<typeof page.locator>) => (hasTouch ? target.tap() : target.click())
  const problems = watch(page)
  const closed: string[] = []
  page.on("websocket", socket => socket.on("close", () => closed.push(socket.url())))
  await page.goto("/notes")
  await expect(page.locator("[data-phx-main].phx-connected")).toBeAttached()

  const form = page.locator("#note-form")
  const body = page.locator("#note-body")
  await body.fill("Ada\u202Egnp.exe")
  await body.blur()
  await expect(form.getByText("Use letters, numbers and marks you can see.")).toBeVisible()

  const title = `${randomUUID().slice(0, 8)}${"中".repeat(112)}`
  await page.locator("#note-title").fill(title)
  await body.fill("中".repeat(10_000))
  await body.blur()
  await expect(form.getByText("Use letters, numbers and marks you can see.")).toHaveCount(0)
  await press(form.getByRole("button", {name: "Add note"}))
  await expect(page.getByRole("heading", {name: title})).toBeVisible()

  expect(closed).toEqual([])
  await problems.expect()
})

// The walk's person has a note for each width whose label waits to be rated
// (sign_in.exs). The label floats on the line above the note: it asks, the answer
// takes its place, and neither moves the note or covers anything that can be pressed.
// Other checks add notes above at the same time, so the note is measured from its own
// top.
test("a note's label gives way to its answer without moving the note", async ({page, hasTouch}, info) => {
  const problems = watch(page)
  await page.goto("/notes")
  await expect(page.locator("[data-phx-main].phx-connected")).toBeAttached()

  const note = page.locator(".notes-item", {has: page.getByRole("heading", {name: `Walk label ${info.project.name}`})})
  const asking = note.getByRole("group")
  const shown = note.locator(".notes-label__state[data-on]")
  const layout = () =>
    note.evaluate((item: HTMLElement) => [
      [item.offsetWidth, item.offsetHeight],
      ...[...item.querySelectorAll<HTMLElement>(":scope > :not(.notes-label)")].map(child => [
        child.offsetLeft,
        child.offsetTop,
        child.offsetWidth,
        child.offsetHeight,
      ]),
    ])
  const covered = () =>
    shown.evaluate(state => {
      const box = state.getBoundingClientRect()
      return [...document.querySelectorAll("#notes-page :is(button, a[href], input, textarea, select)")]
        .filter(control => !state.closest(".notes-label")!.contains(control))
        .filter(control => {
          const other = control.getBoundingClientRect()
          return other.width > 0 && box.left < other.right && other.left < box.right && box.top < other.bottom && other.top < box.bottom
        })
        .map(control => control.outerHTML.slice(0, 80))
    })

  await note.scrollIntoViewIfNeeded()
  await expect(asking).toBeVisible()
  await expect(shown).toHaveCount(1)
  expect(await covered()).toEqual([])
  const before = await layout()

  const yes = asking.getByRole("button", {name: "Yes"})
  await (hasTouch ? yes.tap() : yes.click())
  await expect(asking).toHaveCount(0)
  await expect(shown).toHaveCount(1)
  await expect(shown).toBeVisible()
  await expect(shown.getByRole("button")).toHaveCount(0)
  expect(await covered()).toEqual([])
  expect(await layout()).toEqual(before)
  await problems.expect()
})

// The walk's friend has 51 notes (sign_in.exs): the list shows the newest 50, and
// Older notes adds the last one and goes away.
test("Older notes adds the notes after the first fifty", async ({browser, baseURL, extraHTTPHeaders}) => {
  const friend = await browser.newContext({
    storageState: "test/browser/.auth/friend.json",
    baseURL,
    extraHTTPHeaders,
  })
  try {
    const outside = await onThisMachine(friend, baseURL!)
    const page = await friend.newPage()
    const problems = watch(page)
    await page.goto("/notes")
    await expect(page.locator("[data-phx-main].phx-connected")).toBeAttached()

    const notes = page.locator("#notes-list > .notes-item")
    await expect(notes).toHaveCount(50)
    await expect(notes.first().locator("h3")).toHaveText("Walk note 51")
    await page.getByRole("button", {name: "Older notes"}).click()
    await expect(notes).toHaveCount(51)
    await expect(notes.last().locator("h3")).toHaveText("Walk note 1")
    await expect(page.getByRole("button", {name: "Older notes"})).toHaveCount(0)
    await problems.expect()
    expect(outside, "the friend's requests that left the machine").toEqual([])
  } finally {
    await friend.close()
  }
})
