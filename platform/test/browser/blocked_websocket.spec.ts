import {randomUUID} from "node:crypto"
import type {Locator, Page, WebSocketRoute} from "@playwright/test"
import {expect, test} from "./support/test"
import {signedIn, watch} from "./support/person"

// Pages connect by websocket only. On a network that refuses websockets, signing in
// and out still work: Sign in starts the sign-in bridge, which then needs one request
// to /auth/privy/session and a reload; the page as served shows the account, and its
// menu holds Sign out. A live form says it is not connected and its buttons are
// disabled until the connection is back (AshTemplateWeb.LiveConnection).
const live = /\/live\/websocket/

const refuseWebsockets = (page: Page) =>
  page.routeWebSocket(live, socket => socket.close({code: 1011, reason: "refused"}))

// A connection that can be dropped, as in a server restart, and let back.
async function droppable(page: Page) {
  let down = false
  const open: WebSocketRoute[] = []
  await page.routeWebSocket(live, socket => {
    if (down) return socket.close({code: 1011, reason: "restarting"})
    socket.connectToServer()
    open.push(socket)
  })
  return {
    drop: async () => {
      down = true
      for (const socket of open.splice(0)) await socket.close({code: 1012, reason: "restarting"})
    },
    restore: () => {
      down = false
    },
  }
}

const connected = (page: Page) => expect(page.locator("[data-phx-main].phx-connected")).toBeAttached()

const bridge = /^\/assets\/js\/privy_bridge(-[0-9a-f]+)?\.js$/

test("with websockets refused, Sign in still starts the sign-in bridge", async ({page, hasTouch}) => {
  await refuseWebsockets(page)
  await page.goto("/notes")
  const loaded = page.waitForRequest(request => bridge.test(new URL(request.url()).pathname))
  const signIn = page.locator("#account-control [data-account-target='sign-in']")
  await (hasTouch ? signIn.tap() : signIn.click())
  await loaded
  await expect(page.locator("[data-phx-main].phx-connected")).toHaveCount(0)
})

test.describe("signed in", () => {
  test.use(signedIn)

  test("with websockets refused, a signed-in page shows the account and its menu holds Sign out", async ({page, hasTouch}) => {
    const problems = watch(page)
    await refuseWebsockets(page)
    await page.goto("/rooms/general")
    await expect(page.locator("#account-control [data-account-target='sign-in']")).toHaveCount(0)
    const chip = page.locator("#account-chip")
    await (hasTouch ? chip.tap() : chip.click())
    await expect(page.locator("#account-menu").getByRole("button", {name: "Sign out"})).toBeVisible()
    await expect(page.locator("[data-phx-main].phx-connected")).toHaveCount(0)
    await problems.expect()
  })

  test("with websockets refused, Send says it is not connected and is disabled", async ({page}) => {
    await refuseWebsockets(page)
    await page.goto("/rooms/general")
    const notice = page.locator("#room-message-offline")
    await expect(notice).toHaveText("Not connected. Trying again…")
    await expect(page.locator("#room-message-form").getByRole("button", {name: "Send"})).toBeDisabled()
    await expect(page.locator("#room-message-body")).toBeEditable()
  })

  // Each live form that writes: its note shows, its buttons are disabled, and its
  // first box can still be typed in.
  for (const {path, form, offline, button, box} of [
    {path: "/notes", form: "#note-form", offline: "#note-form-offline", button: "Add note", box: "#note-title"},
    {path: "/polls", form: "#poll-start-form", offline: "#poll-start-offline", button: "Start poll", box: "#poll-start-question"},
    {path: "/rooms/general", form: "#room-start-form", offline: "#room-start-offline", button: "Start room", box: "#room-start-name"},
  ]) {
    test(`with websockets refused, ${button} on ${path} says it is not connected and is disabled`, async ({page}) => {
      await refuseWebsockets(page)
      await page.goto(path)
      await expect(page.locator(offline)).toBeVisible()
      await expect(page.locator(form).getByRole("button", {name: button})).toBeDisabled()
      await expect(page.locator(box)).toBeEditable()
    })
  }

  // On a plain page the Agent Message form is a live view of its own, inside a dialog
  // the page's script opens.
  test("with websockets refused, the Agent Message form says it is not connected and Send is disabled", async ({page, hasTouch}) => {
    await refuseWebsockets(page)
    await page.goto("/agents")
    const open = page.getByRole("button", {name: "Agent Message"})
    await (hasTouch ? open.tap() : open.click())
    const dialog = page.getByRole("dialog", {name: "Agent Message"})
    await expect(dialog.locator("#agents-message-person-offline")).toBeVisible()
    await expect(dialog.locator("#agents-message-person-form").getByRole("button", {name: "Send"})).toBeDisabled()
    await expect(dialog.getByRole("textbox", {name: "Message", exact: true})).toBeEditable()
  })

  // The pairing window opens from the page's script once it is connected; the Pair
  // New Agent page holds the same box on its own.
  test("with websockets refused, the pairing box says it is not connected and its agents are disabled", async ({page}) => {
    await refuseWebsockets(page)
    await page.goto("/pair")
    await expect(page.locator("#pair-pairing-box-offline")).toHaveText("Not connected. Trying again…")
    await expect(page.locator("form#pair-pairing-box").getByRole("radio", {name: "Dots", exact: true})).toBeDisabled()
  })

  // A connection that drops, as in a server restart, and comes back: the note shows
  // while it is down and goes once it is back, and Send works again.
  test("a dropped connection disables Send until it is back", async ({page, hasTouch}) => {
    const problems = watch(page)
    const connection = await droppable(page)
    await page.goto("/rooms/general")
    await connected(page)
    const notice = page.locator("#room-message-offline")
    const send = page.locator("#room-message-form").getByRole("button", {name: "Send"})
    await expect(notice).toBeHidden()
    await expect(send).toBeEnabled()

    await connection.drop()
    await expect(notice).toBeVisible()
    await expect(send).toBeDisabled()

    // Enter is Send, so it waits too.
    const words = `Typed while away ${Date.now()}`
    await page.locator("#room-message-body").fill(words)
    if (!hasTouch) await page.locator("#room-message-body").press("Enter")

    connection.restore()
    await expect(notice).toBeHidden({timeout: 15_000})
    await expect(send).toBeEnabled()
    await expect(page.locator(".rooms-message", {hasText: words})).toHaveCount(0)
    await (hasTouch ? send.tap() : send.click())
    await expect(page.locator(".rooms-message", {hasText: words})).toBeVisible()
    await problems.expect()
  })

  // Editing a note: Save changes and Cancel wait for the connection. A page that
  // connects again starts afresh, so the note is opened again and the edit saved.
  test("a dropped connection disables a note's Save changes and Cancel until it is back", async ({page, hasTouch}) => {
    const press = (target: Locator) => (hasTouch ? target.tap() : target.click())
    const problems = watch(page)
    const connection = await droppable(page)
    await page.goto("/notes")
    await connected(page)

    const form = page.locator("#note-form")
    const title = `Offline ${randomUUID().slice(0, 8)}`
    await page.locator("#note-title").fill(title)
    await press(form.getByRole("button", {name: "Add note"}))
    const note = page.locator(".notes-item", {has: page.getByRole("heading", {name: title})})
    await press(note.getByRole("button", {name: "Edit"}))
    const save = form.getByRole("button", {name: "Save changes"})
    const cancel = form.getByRole("button", {name: "Cancel"})
    await expect(save).toBeVisible()

    await connection.drop()
    await expect(page.locator("#note-form-offline")).toBeVisible()
    await expect(save).toBeDisabled()
    await expect(cancel).toBeDisabled()
    await expect(page.locator("#note-title")).toBeEditable()

    connection.restore()
    await expect(page.locator("#note-form-offline")).toBeHidden({timeout: 15_000})
    await press(note.getByRole("button", {name: "Edit"}))
    await expect(cancel).toBeEnabled()
    const edited = `${title} edited`
    await page.locator("#note-title").fill(edited)
    await press(save)
    await expect(page.getByRole("heading", {name: edited})).toBeVisible()
    await problems.expect()
  })

  // A poll the person started and has not voted in (sign_in.exs): Vote and End wait
  // for the connection, then the vote counts.
  test("a dropped connection disables Vote and End until it is back", async ({page, hasTouch}, info) => {
    const press = (target: Locator) => (hasTouch ? target.tap() : target.click())
    const problems = watch(page)
    const connection = await droppable(page)
    await page.goto("/polls")
    const poll = await page.locator("a", {hasText: `Walk offline, ${info.project.name}?`}).first().getAttribute("href")
    await page.goto(poll!)
    await connected(page)
    const vote = page.locator("#poll-vote-form").getByRole("button", {name: "Vote"})
    const end = page.locator("#poll-end")
    await expect(vote).toBeEnabled()
    await expect(end).toBeEnabled()

    await connection.drop()
    await expect(page.locator("#poll-offline")).toBeVisible()
    await expect(vote).toBeDisabled()
    await expect(end).toBeDisabled()

    connection.restore()
    await expect(page.locator("#poll-offline")).toBeHidden({timeout: 15_000})
    await expect(end).toBeEnabled()
    await press(page.locator("#poll-vote-form").getByText("Yes"))
    await press(vote)
    await expect(page.locator("#poll-my-vote")).toHaveText("You voted for “Yes”.")
    await problems.expect()
  })

  // A room the person started: Save topic waits for the connection, then the topic is
  // saved.
  test("a dropped connection disables a room's Save topic until it is back", async ({page, hasTouch}) => {
    const press = (target: Locator) => (hasTouch ? target.tap() : target.click())
    const problems = watch(page)
    const connection = await droppable(page)
    await page.goto("/rooms/general")
    await connected(page)

    await page.locator("#room-start-name").fill(`Offline ${randomUUID().slice(0, 8)}`)
    await page.locator("#room-start-topic").fill("A room started on the walk")
    await press(page.locator("#room-start-form").getByRole("button", {name: "Start room"}))
    const save = page.locator("#room-topic-form").getByRole("button", {name: "Save topic"})
    await expect(save).toBeEnabled()

    await connection.drop()
    await expect(page.locator("#room-topic-offline")).toBeVisible()
    await expect(save).toBeDisabled()
    await expect(page.locator("#room-start-form").getByRole("button", {name: "Start room"})).toBeDisabled()

    connection.restore()
    await expect(page.locator("#room-topic-offline")).toBeHidden({timeout: 15_000})
    const topic = `Quiet after the break ${Date.now()}`
    await page.locator("#room-topic").fill(topic)
    await press(save)
    await expect(page.locator(".page-head [role=tooltip]")).toContainText(topic)
    await problems.expect()
  })
})
