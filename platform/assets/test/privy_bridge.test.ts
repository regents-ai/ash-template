// Invariant: after Disconnect, only a sign-in the visitor makes now signs them in.
// A Privy session the browser still remembers completes at once with
// wasAlreadyAuthenticated, even when a link carries privy_oauth_code; it must not
// sign the previous person back in or clear the Disconnect note (Sentinel,
// 12 Oct 2026). A real redirect return arrives signed out and still signs in.
import {beforeEach, expect, it, vi} from "vitest"
import type {PrivyEvents} from "@privy-io/react-auth"

vi.mock("@privy-io/react-auth", () => ({}))
vi.mock("react-dom/client", () => ({}))

const {createPrivyLoginCallbacks} = await import("../js/privy_bridge")

const disconnected = "regent:wallet-disconnected:v1"
const stored = new Map<string, string>()

beforeEach(() => {
  stored.clear()
  stored.set(disconnected, "true")
  const storage = {
    getItem: (key: string) => stored.get(key) ?? null,
    setItem: (key: string, value: string) => void stored.set(key, value),
    removeItem: (key: string) => void stored.delete(key),
  }
  vi.stubGlobal("window", {localStorage: storage, sessionStorage: storage})
  vi.stubGlobal("localStorage", storage)
  vi.stubGlobal("sessionStorage", storage)
})

function complete(wasAlreadyAuthenticated: boolean) {
  const completeLogin = vi.fn(async () => undefined)
  // A link carrying privy_oauth_code starts the page as if it opened sign-in.
  const callbacks = createPrivyLoginCallbacks({
    completeLogin,
    loginOpen: {current: true},
    showFailure: vi.fn(),
    reportFailure: vi.fn(),
  })
  const done = callbacks.onComplete as NonNullable<PrivyEvents["login"]["onComplete"]>
  done({
    user: {id: "did:privy:person"},
    isNewUser: false,
    wasAlreadyAuthenticated,
    loginMethod: "google",
    loginAccount: null,
  } as unknown as Parameters<typeof done>[0])
  return completeLogin
}

it("a remembered session never signs back in after Disconnect", () => {
  expect(complete(true)).not.toHaveBeenCalled()
  expect(stored.get(disconnected)).toBe("true")
})

it("a real redirect return after Disconnect signs in", () => {
  expect(complete(false)).toHaveBeenCalledOnce()
  expect(stored.has(disconnected)).toBe(false)
})
