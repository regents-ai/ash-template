// Invariant: a sign-out that did not happen leaves the page as it was. The person
// is still signed in, so the page can still refresh its sign-in, link an account
// or try signing out again. Only while a sign-out is under way, and after one that
// worked (that page is replaced), is establishing a session refused.
import {expect, it, vi} from "vitest"

import {createSessionMutationCoordinator} from "../js/auth_lazy"

const established = async () => "established"

it("a failed sign-out lets the page establish its session again", async () => {
  const sessions = createSessionMutationCoordinator()

  await expect(sessions.signOut(async () => Promise.reject(new Error("the request failed")))).rejects.toThrow()
  await expect(sessions.establish(established)).resolves.toBe("established")

  // And it can be tried again, running the sign-out anew.
  const again = vi.fn(async () => undefined)
  await sessions.signOut(again)
  expect(again).toHaveBeenCalledOnce()
})

it("while a sign-out is under way, and after one that worked, nothing is established", async () => {
  const sessions = createSessionMutationCoordinator()
  let finish = () => {}
  const underWay = sessions.signOut(() => new Promise<void>(resolve => (finish = resolve)))

  await expect(sessions.establish(established)).rejects.toThrow("Local sign out has already started.")
  finish()
  await underWay
  await expect(sessions.establish(established)).rejects.toThrow("Local sign out has already started.")
})

it("a sign-out asked for twice while under way runs once", async () => {
  const sessions = createSessionMutationCoordinator()
  const clear = vi.fn(async () => undefined)

  await Promise.all([sessions.signOut(clear), sessions.signOut(clear)])
  expect(clear).toHaveBeenCalledOnce()
})
