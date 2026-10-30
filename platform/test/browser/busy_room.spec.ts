import {randomUUID} from "node:crypto"
import {type Locator, type Page} from "@playwright/test"
import {expect, onThisMachine, test} from "./support/test"
import {signedIn, watch} from "./support/person"

// In a busy room an open message menu stays usable: messages arriving below leave
// its message where it is, so a press on a choice lands on it. Once the reader
// scrolls the menu's button away, the menu closes. The walk's friend fills the room
// (sign_in.exs signs them in too, and starts a quiet room for each width) while the
// walk's person holds the menu open.
test.use(signedIn)

// Whether the message is inside the room's scrolling area.
const shown = (message: Locator) =>
  message.evaluate(element => {
    const scroller = element.closest("[data-conversation-scroller]")!.getBoundingClientRect()
    const box = element.getBoundingClientRect()
    return box.bottom > scroller.top && box.top < scroller.bottom
  })

// The reader's own scroll of the room, by finger on a phone and by wheel on a desktop.
async function drag(page: Page, hasTouch: boolean, distance: number) {
  const box = (await page.locator("[data-conversation-scroller]").boundingBox())!
  const x = box.x + box.width / 2
  const y = box.y + box.height / 2
  if (hasTouch) {
    const cdp = await page.context().newCDPSession(page)
    await cdp.send("Input.synthesizeScrollGesture", {x, y, yDistance: -distance, gestureSourceType: "touch", speed: 1500})
    await cdp.detach()
  } else {
    await page.mouse.move(x, y)
    await page.mouse.wheel(0, distance)
  }
}

// A finger's quick swipe, which carries the room on after the finger lifts.
async function fling(page: Page, distance: number) {
  const box = (await page.locator("[data-conversation-scroller]").boundingBox())!
  const cdp = await page.context().newCDPSession(page)
  await cdp.send("Input.synthesizeScrollGesture", {
    x: box.x + box.width / 2,
    y: box.y + box.height / 2,
    yDistance: -distance,
    gestureSourceType: "touch",
    speed: 3000,
    preventFling: false,
  })
  await cdp.detach()
}

const scrollTop = (page: Page) =>
  page.locator("[data-conversation-scroller]").evaluate(scroller => scroller.scrollTop)

// How far below the top of the room's scrolling area the message sits.
const place = (message: Locator) =>
  message.evaluate(element => {
    const scroller = element.closest("[data-conversation-scroller]")!
    return element.getBoundingClientRect().top - scroller.getBoundingClientRect().top
  })

// Makes the message taller by a rule of the page's own, which the server's
// updates to the message leave in place.
const grow = async (message: Locator, pixels: number) => {
  const id = await message.evaluate(element => element.id)
  await message.page().addStyleTag({content: `#${id} { padding-bottom: ${pixels}px }`})
}

// A phone keeps moving the room for a moment after a hand scroll past its end, and
// Chrome, keeping what is in view in place, may scroll a pixel a moment after a change.
async function still(page: Page) {
  await expect
    .poll(async () => {
      const before = await scrollTop(page)
      await page.waitForTimeout(300)
      return before === (await scrollTop(page))
    })
    .toBe(true)
}

async function settled(page: Page) {
  await still(page)
  expect(await scrollTop(page)).toBeGreaterThan(-2)
}

const drawn = (page: Page) => page.evaluate(() => new Promise(done => requestAnimationFrame(() => requestAnimationFrame(done))))

// A finger's tap on a phone and a mouse's click on a desktop, on a button in the room
// where the reader sees it. The walk never scrolls the room to reach it, as no
// reader's press does: Playwright, finding a button still squishing from the last
// press, would scroll it to the room's edge before trying again.
const presser = (hasTouch: boolean) => (target: Locator) =>
  hasTouch ? target.tap({scroll: "none"}) : target.click({scroll: "none"})

// The form sits below the room, so the page scrolls to its Send button as a reader's would.
async function send(page: Page, hasTouch: boolean, words: string) {
  await page.locator("#room-message-body").fill(words)
  const button = page.locator("#room-message-form").getByRole("button", {name: "Send"})
  await (hasTouch ? button.tap() : button.click())
  const said = page.locator(".rooms-message", {hasText: words.split("\n").at(-1)!})
  await expect(said).toBeVisible()
  return said
}

test("A message menu stays usable while new messages arrive, and closes once its message is scrolled away", async ({page, browser, baseURL, extraHTTPHeaders, hasTouch}, info) => {
  const press = presser(hasTouch)
  const problems = watch(page)
  const tag = randomUUID().slice(0, 8)
  const busy = `/rooms/walk-busy-${info.project.name}`
  await page.goto(busy)
  await expect(page.locator("[data-phx-main].phx-connected")).toBeAttached()

  const earlier = await send(page, hasTouch, `Earlier on the ${info.project.name} walk, ${tag}.`)
  const words = `Busy room on the ${info.project.name} walk, ${tag}.`
  const said = await send(page, hasTouch, words)
  await press(said.getByRole("button", {name: "Options for this message"}))
  const menu = said.getByRole("group", {name: "Message options"})
  await expect(menu).toBeVisible()

  // Three messages of ten lines each fill the room more than once at either width;
  // with the fourth below, that keeps inside the friend's allowance of quick posts
  // for both widths together.
  const friend = await browser.newContext({
    storageState: "test/browser/.auth/friend.json",
    baseURL,
    extraHTTPHeaders,
  })
  try {
    const outside = await onThisMachine(friend, baseURL!)
    const room = await friend.newPage()
    const friendProblems = watch(room)
    await room.goto(busy)
    await expect(room.locator("[data-phx-main].phx-connected")).toBeAttached()
    const post = async (n: number) => {
      const lines = Array.from({length: 10}, (_, k) => `Busy room ${tag}, message ${n}, line ${k + 1}.`)
      await room.locator("#room-message-body").fill(lines.join("\n"))
      await room.locator("#room-message-form").getByRole("button", {name: "Send"}).click()
      await expect(room.locator(".rooms-message", {hasText: lines[9]})).toBeVisible()
      return page.locator(".rooms-message", {hasText: lines[9]})
    }
    // Until the room is full, a message arriving moves the others up, as there is
    // nothing above to scroll; from then on the message stays put.
    const first = await post(1)
    const second = await post(2)
    await expect(second).toBeAttached()
    await still(page)
    expect(await page.locator("[data-conversation-scroller]").evaluate(scroller => scroller.scrollHeight > scroller.clientHeight)).toBe(true)
    const full = await place(said)
    const third = await post(3)
    await expect(third).toBeAttached()
    await still(page)
    expect(Math.abs((await place(said)) - full)).toBeLessThanOrEqual(2)
    await expect(menu).toBeVisible()
    // Left to itself, the third message would have pushed the menu's button out of view.
    const button = said.getByRole("button", {name: "Options for this message"})
    const [height, bottom] = await third.evaluate((message, button) => {
      const scroller = message.closest("[data-conversation-scroller]")!
      return [message.getBoundingClientRect().height, button!.getBoundingClientRect().bottom - scroller.getBoundingClientRect().top]
    }, await button.elementHandle())
    expect(height).toBeGreaterThan(bottom)

    // Two messages below grow a frame apart (each opens its whole text, as Show more
    // does); the message stays put.
    // Safari doesn't keep what is in view in place by itself, as Chrome does, so the
    // room is made to behave as there.
    const kept = await place(said)
    const growing = [await first.elementHandle(), await second.elementHandle()]
    await page.evaluate(
      ([a, b]) =>
        new Promise<void>(done => {
          const grow = (message: Element) =>
            message.querySelectorAll<HTMLElement>(".rooms-body").forEach(body => (body.hidden = !body.hidden))
          a!.closest<HTMLElement>("[data-conversation-scroller]")!.style.overflowAnchor = "none"
          requestAnimationFrame(() => {
            grow(a!)
            setTimeout(() => {
              grow(b!)
              requestAnimationFrame(() =>
                requestAnimationFrame(() => {
                  a!.closest<HTMLElement>("[data-conversation-scroller]")!.style.overflowAnchor = ""
                  done()
                }),
              )
            }, 0)
          })
        }),
      growing,
    )
    expect(Math.abs((await place(said)) - kept)).toBeLessThanOrEqual(1)

    // Opening another message's menu leaves the list where it is, also when the press
    // closes the first menu before its click lands, as a finger's or a pen's may. The list rested
    // on the newest message when the first menu opened, so it goes back there once
    // the second closes.
    const before = await place(earlier)
    const open = await menu.evaluate(element => element.id)
    const between = await earlier.getByRole("button", {name: "Options for this message"}).evaluate(async (button: HTMLElement, [open, pointerType]) => {
      const message = button.closest(".rooms-message")!
      const scroller = message.closest("[data-conversation-scroller]")!
      button.dispatchEvent(new PointerEvent("pointerdown", {bubbles: true, pointerType}))
      button.dispatchEvent(new PointerEvent("pointerup", {bubbles: true, pointerType}))
      document.getElementById(open)!.hidePopover()
      await new Promise(done => setTimeout(done, 100))
      const at = message.getBoundingClientRect().top - scroller.getBoundingClientRect().top
      button.click()
      return at
    }, [open, hasTouch ? "touch" : "pen"])
    expect(Math.abs(between - before)).toBeLessThanOrEqual(1)
    const other = earlier.getByRole("group", {name: "Message options"})
    await expect(other).toBeVisible()
    await expect(menu).toBeHidden()
    expect(Math.abs((await place(earlier)) - before)).toBeLessThanOrEqual(1)
    await press(other.getByRole("button", {name: "Like", exact: true}))
    await expect(earlier.locator(".rg-discussion__heart")).toHaveAttribute("aria-pressed", "true")
    await expect.poll(() => shown(third)).toBe(true)

    // The reader scrolls up and back to the newest message by hand, a little past it
    // as a hand does, which can leave the list a pixel off where it rests, and opens
    // the newest message's menu. A message arrives below and the newest stays put;
    // once the menu closes, the list is back on the newest.
    await drag(page, hasTouch, -300)
    await expect.poll(() => scrollTop(page)).toBeLessThan(-100)
    await drag(page, hasTouch, 40 - (await scrollTop(page)))
    await settled(page)
    await press(third.getByRole("button", {name: "Options for this message"}))
    await expect(third.getByRole("group", {name: "Message options"})).toBeVisible()
    const at = await place(third)
    const fourth = await post(4)
    await expect(fourth).toBeAttached()
    await still(page)
    expect(Math.abs((await place(third)) - at)).toBeLessThanOrEqual(1)

    // A message below grows and the reader scrolls before the room is next drawn;
    // the message moves by the reader's scroll alone (the room behaving as Safari's).
    const placed = await place(third)
    await third.evaluate(
      (message, below) =>
        new Promise<void>(done => {
          const scroller = message.closest<HTMLElement>("[data-conversation-scroller]")!
          scroller.style.overflowAnchor = "none"
          const taller = document.createElement("style")
          taller.id = "walk-taller"
          taller.textContent = `#${below!.id} { padding-bottom: 150px }`
          document.head.append(taller)
          scroller.scrollTop -= 6
          requestAnimationFrame(() =>
            requestAnimationFrame(() => {
              scroller.style.overflowAnchor = ""
              done()
            }),
          )
        }),
      await fourth.elementHandle(),
    )
    expect(Math.abs((await place(third)) - placed - 6)).toBeLessThanOrEqual(1)
    await page.keyboard.press("Escape")
    await expect(third.getByRole("group", {name: "Message options"})).toBeHidden()
    await expect.poll(() => shown(fourth)).toBe(true)
    await page.evaluate(() => document.getElementById("walk-taller")!.remove())

    // The reader scrolls a little with a menu open, then picks a choice; the list
    // stays off the newest message, where the reader put it.
    await settled(page)
    const choices = fourth.getByRole("group", {name: "Message options"})
    await press(fourth.getByRole("button", {name: "Options for this message"}))
    await expect(choices).toBeVisible()
    await page.locator("[data-conversation-scroller]").evaluate(scroller => (scroller.scrollTop -= 40))
    await expect.poll(() => scrollTop(page)).toBeLessThan(-30)
    await press(choices.getByRole("button", {name: "Like", exact: true}))
    await expect(fourth.locator(".rg-discussion__heart")).toHaveAttribute("aria-pressed", "true")
    await drawn(page)
    expect(await scrollTop(page)).toBeLessThan(-30)
    await page.locator("[data-conversation-scroller]").evaluate(scroller => scroller.scrollTo({top: 0}))
    await settled(page)

    let newest = fourth

    // With a mouse, a press that starts in the room and ends outside it closes the
    // menu with its click landing outside the room; the list still goes back to the
    // newest message. A menu opened later by key, with the list scrolled up, leaves
    // it there once closed.
    if (!hasTouch) {
      const options = third.getByRole("group", {name: "Message options"})
      await press(third.getByRole("button", {name: "Options for this message"}))
      await expect(options).toBeVisible()
      await grow(fourth, 80)
      await expect.poll(() => scrollTop(page)).toBeLessThan(-50)
      const box = (await page.locator("#room-message-body").boundingBox())!
      await page.mouse.move(box.x + 20, box.y + 10)
      await page.mouse.down()
      await page.mouse.move(4, 4, {steps: 4})
      await page.mouse.up()
      await expect(options).toBeHidden()
      await expect.poll(() => scrollTop(page)).toBeGreaterThan(-2)

      await second.evaluate(message => {
        const scroller = message.closest<HTMLElement>("[data-conversation-scroller]")!
        scroller.scrollTop += message.getBoundingClientRect().top - scroller.getBoundingClientRect().top - 8
      })
      const up = await scrollTop(page)
      expect(up).toBeLessThan(-50)
      await second.getByRole("button", {name: "Options for this message"}).focus()
      await page.keyboard.press("Enter")
      await expect(second.getByRole("group", {name: "Message options"})).toBeVisible()
      await page.keyboard.press("Escape")
      await expect(second.getByRole("group", {name: "Message options"})).toBeHidden()
      await drawn(page)
      expect(Math.abs((await scrollTop(page)) - up)).toBeLessThanOrEqual(1)

      // A message sent by key with the newest message's menu still open shows below it.
      await page.locator("[data-conversation-scroller]").evaluate(scroller => scroller.scrollTo({top: 0}))
      await settled(page)
      await fourth.getByRole("button", {name: "Options for this message"}).focus()
      await page.keyboard.press("Enter")
      await expect(fourth.getByRole("group", {name: "Message options"})).toBeVisible()
      await page.locator("#room-message-body").fill(`Sent with a menu open, ${tag}.`)
      await page.keyboard.press("Enter")
      const sent = page.locator(".rooms-message", {hasText: `Sent with a menu open, ${tag}.`})
      await expect(sent).toBeAttached()
      await expect.poll(() => shown(sent)).toBe(true)
      await expect(fourth.getByRole("group", {name: "Message options"})).toBeHidden()
      newest = sent

      // Resting the mouse on the room's tip "i", above the room, opens its words,
      // which closes an open menu with no press; the room stays where it is under the
      // mouse, also through the reader's small scroll and once the mouse leaves and
      // the words close.
      await settled(page)
      await press(fourth.getByRole("button", {name: "Options for this message"}))
      await expect(fourth.getByRole("group", {name: "Message options"})).toBeVisible()
      await grow(sent, 40)
      await expect.poll(() => scrollTop(page)).toBeLessThan(-30)
      const resting = await scrollTop(page)
      const topic = page.locator(".page-head [role=tooltip]")
      const tip = page.locator(".page-head .rg-tip-button")
      await tip.hover()
      await expect(topic).toBeVisible()
      await expect(fourth.getByRole("group", {name: "Message options"})).toBeHidden()
      await drawn(page)
      expect(Math.abs((await scrollTop(page)) - resting)).toBeLessThanOrEqual(1)
      await page.locator("[data-conversation-scroller]").evaluate(scroller => (scroller.scrollTop -= 10))
      await page.mouse.move(4, 4)
      await expect(topic).toBeHidden()
      await drawn(page)
      expect(Math.abs((await scrollTop(page)) - resting + 10)).toBeLessThanOrEqual(1)
      await page.locator("[data-conversation-scroller]").evaluate(scroller => scroller.scrollTo({top: 0}))

      // The tip's words, opened and closed with no menu open, leave nothing behind: a
      // menu a screen reader opens next, with a click and no press, goes back to the
      // newest message once closed.
      await settled(page)
      await tip.hover()
      await expect(topic).toBeVisible()
      await page.mouse.move(4, 4)
      await expect(topic).toBeHidden()
      await sent.getByRole("button", {name: "Options for this message"}).evaluate((button: HTMLElement) => button.click())
      await expect(sent.getByRole("group", {name: "Message options"})).toBeVisible()
      await grow(sent, 140)
      await expect.poll(() => scrollTop(page)).toBeLessThan(-50)
      await page.keyboard.press("Escape")
      await expect(sent.getByRole("group", {name: "Message options"})).toBeHidden()
      await expect.poll(() => scrollTop(page)).toBeGreaterThan(-2)
      await grow(sent, 0)
    }

    // A press that ends on a disabled button closes the menu with no click. A mouse's
    // click would have come as it let go, so the list goes back to the newest message;
    // a finger's would have come later, so the list stays where it is.
    await settled(page)
    const last = newest.getByRole("group", {name: "Message options"})
    await press(newest.getByRole("button", {name: "Options for this message"}))
    await expect(last).toBeVisible()
    await grow(newest, 120)
    await expect.poll(() => scrollTop(page)).toBeLessThan(-50)
    await page.evaluate(() => {
      const waiting = document.createElement("button")
      waiting.type = "button"
      waiting.disabled = true
      waiting.id = "walk-waiting"
      waiting.textContent = "Waiting"
      waiting.style.cssText = "position: fixed; left: 8px; top: 40%; width: 120px; height: 48px; z-index: 1000"
      document.body.append(waiting)
    })
    const waiting = (await page.locator("#walk-waiting").boundingBox())!
    const middle = [waiting.x + waiting.width / 2, waiting.y + waiting.height / 2] as const
    await (hasTouch ? page.touchscreen.tap(...middle) : page.mouse.click(...middle))
    await page.evaluate(() => document.getElementById("walk-waiting")!.remove())
    await expect(last).toBeHidden()
    if (hasTouch) {
      await drawn(page)
      await page.waitForTimeout(300)
      expect(await scrollTop(page)).toBeLessThan(-50)
      await page.locator("[data-conversation-scroller]").evaluate(scroller => scroller.scrollTo({top: 0}))
    }
    await expect.poll(() => scrollTop(page)).toBeGreaterThan(-2)

    // A finger's or a pen's tap closes the menu before its click comes, which may
    // land on a button nearby, so the list waits for the click before going back to
    // the newest message; on an iPhone a tap on a message's words has none, and the
    // list stays where it is.
    await grow(newest, 0)
    await settled(page)
    await press(newest.getByRole("button", {name: "Options for this message"}))
    await expect(last).toBeVisible()
    await grow(newest, 200)
    await expect.poll(() => scrollTop(page)).toBeLessThan(-50)
    await third.locator(".rooms-body").first().evaluate((body, pointerType) => {
      body.dispatchEvent(new PointerEvent("pointerdown", {bubbles: true, pointerType}))
      body.dispatchEvent(new PointerEvent("pointerup", {bubbles: true, pointerType}))
      document.querySelector<HTMLElement>("[data-conversation-scroller] :popover-open")!.hidePopover()
    }, hasTouch ? "touch" : "pen")
    await expect(last).toBeHidden()
    await drawn(page)
    await page.waitForTimeout(300)
    expect(await scrollTop(page)).toBeLessThan(-50)
    await third.locator(".rooms-body").first().evaluate((body: HTMLElement) => body.click())
    await expect.poll(() => scrollTop(page)).toBeGreaterThan(-2)

    // A tap on the menu's own edge has no click and leaves the menu open; Escape then
    // closes it, and the list goes back to the newest message.
    await grow(newest, 0)
    await settled(page)
    await press(newest.getByRole("button", {name: "Options for this message"}))
    await expect(last).toBeVisible()
    await grow(newest, 120)
    await expect.poll(() => scrollTop(page)).toBeLessThan(-50)
    await last.evaluate((menu, pointerType) => {
      menu.dispatchEvent(new PointerEvent("pointerdown", {bubbles: true, pointerType}))
      menu.dispatchEvent(new PointerEvent("pointerup", {bubbles: true, pointerType}))
    }, hasTouch ? "touch" : "pen")
    await expect(last).toBeVisible()
    await page.keyboard.press("Escape")
    await expect(last).toBeHidden()
    await expect.poll(() => scrollTop(page)).toBeGreaterThan(-2)

    // On a phone, a tap on the room's tip "i" closes an open menu and opens the tip's
    // words; the list stays where it is.
    if (hasTouch) {
      await grow(newest, 0)
      await settled(page)
      await press(newest.getByRole("button", {name: "Options for this message"}))
      await expect(last).toBeVisible()
      await grow(newest, 120)
      await expect.poll(() => scrollTop(page)).toBeLessThan(-50)
      const tapped = await scrollTop(page)
      await page.locator(".page-head .rg-tip-button").tap()
      await expect(page.locator(".page-head [role=tooltip]")).toBeVisible()
      await expect(last).toBeHidden()
      await drawn(page)
      await page.waitForTimeout(300)
      expect(Math.abs((await scrollTop(page)) - tapped)).toBeLessThanOrEqual(1)
      await page.locator(".page-head .rg-tip-button").tap()
      await expect(page.locator(".page-head [role=tooltip]")).toBeHidden()
      await page.locator("[data-conversation-scroller]").evaluate(scroller => scroller.scrollTo({top: 0}))
    }

    // A menu whose button leaves the room with no scroll, as when the page moves it,
    // closes, and the list stays where it is.
    await grow(newest, 0)
    await settled(page)
    await press(newest.getByRole("button", {name: "Options for this message"}))
    await expect(last).toBeVisible()
    await grow(newest, 160)
    await expect.poll(() => scrollTop(page)).toBeLessThan(-50)
    const held = await scrollTop(page)
    const id = await newest.evaluate(element => element.id)
    const away = await page.addStyleTag({content: `#${id} [popovertarget] { transform: translateY(-4000px) }`})
    await expect(last).toBeHidden()
    await drawn(page)
    await page.waitForTimeout(300)
    expect(Math.abs((await scrollTop(page)) - held)).toBeLessThanOrEqual(1)
    await away.evaluate(style => (style as Element).remove())

    // A menu the page takes off, as on a delete or a sign-out, lets its message go,
    // and the list stays where the reader next scrolls it.
    await page.locator("[data-conversation-scroller]").evaluate(scroller => scroller.scrollTo({top: 0}))
    await grow(newest, 0)
    await settled(page)
    await press(newest.getByRole("button", {name: "Options for this message"}))
    await expect(last).toBeVisible()
    await grow(newest, 120)
    await expect.poll(() => scrollTop(page)).toBeLessThan(-50)
    await last.evaluate(menu => menu.remove())
    const left = await scrollTop(page)
    await page.locator("[data-conversation-scroller]").evaluate(scroller => (scroller.scrollTop -= 10))
    await drawn(page)
    await page.waitForTimeout(300)
    expect(Math.abs((await scrollTop(page)) - left + 10)).toBeLessThanOrEqual(1)
    const after = await scrollTop(page)
    await page.locator("[data-conversation-scroller]").evaluate(scroller => (scroller.style.overflowAnchor = "none"))
    await grow(newest, 200)
    await drawn(page)
    expect(Math.abs((await scrollTop(page)) - after)).toBeLessThanOrEqual(1)
    await page.locator("[data-conversation-scroller]").evaluate(scroller => (scroller.style.overflowAnchor = ""))

    await friendProblems.expect()
    expect(outside, "requests that left the machine").toEqual([])
  } finally {
    await friend.close()
  }

  // The reader goes back toward the newest message with the menu open: on a phone by
  // a quick swipe, whose glide after the finger lifts is the reader's too, and on a
  // desktop by Shift+Tab from the message box to the newest message. The message
  // goes with the room, and its menu closes once it has gone. The message has gone up
  // out of the room by now, so the reader first scrolls back up to it.
  await said.scrollIntoViewIfNeeded()
  await press(said.getByRole("button", {name: "Options for this message"}))
  await expect(menu).toBeVisible()
  if (hasTouch) {
    const before = await scrollTop(page)
    await fling(page, 150)
    await still(page)
    expect((await scrollTop(page)) - before).toBeGreaterThan(300)
  } else {
    await page.locator("#room-message-body").focus()
    await page.keyboard.press("Shift+Tab")
    await expect(page.locator("[data-conversation-scroller] :focus")).toBeVisible()
  }
  await expect.poll(() => shown(said)).toBe(false)
  await expect(menu).toBeHidden()
  await problems.expect()
})

test("A tall message's menu closes once its button is scrolled away, while the message is still in view", async ({page, hasTouch}, info) => {
  const press = presser(hasTouch)
  const problems = watch(page)
  const tag = randomUUID().slice(0, 8)
  await page.goto("/rooms/general")
  await expect(page.locator("[data-phx-main].phx-connected")).toBeAttached()

  // Taller than the room at either width once opened in full.
  const lines = Array.from({length: 40}, (_, k) => `Tall ${info.project.name} ${tag}, line ${k + 1}.`)
  const said = await send(page, hasTouch, lines.join("\n"))
  await press(said.getByRole("button", {name: "Show more"}))
  await expect(said.getByText(lines[39])).toBeVisible()
  const button = said.getByRole("button", {name: "Options for this message"})

  // Bring its top, with the button, into the room, open the menu, then scroll toward
  // the newest message until the button has just left the top.
  await said.evaluate(message => {
    const scroller = message.closest<HTMLElement>("[data-conversation-scroller]")!
    scroller.scrollTop += message.getBoundingClientRect().top - scroller.getBoundingClientRect().top - 8
  })
  await press(button)
  const menu = said.getByRole("group", {name: "Message options"})
  await expect(menu).toBeVisible()
  await button.evaluate(element => {
    const scroller = element.closest<HTMLElement>("[data-conversation-scroller]")!
    scroller.scrollTop += element.getBoundingClientRect().bottom - scroller.getBoundingClientRect().top + 4
  })
  expect(await shown(said)).toBe(true)
  await expect(menu).toBeHidden()
  await problems.expect()
})
