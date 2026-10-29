// Invariant: the shared Privy sign-in (regent_privy) never leaves the server and
// Privy disagreeing about who is signed in. Sign-out logs Privy out only after the
// server has ended the session, and Privy's next token renews only the sign-in of
// the person the server already holds.
import {beforeEach, expect, it, vi} from "vitest"

const privy = {
  ready: true,
  authenticated: true,
  user: {id: "did:privy:owner"} as {id: string} | null,
  logout: vi.fn(async () => {}),
}

vi.mock("@privy-io/react-auth", () => ({
  PrivyProvider: (props: any) => props.children,
  getIdentityToken: async () => "id-token",
  useLogin: () => ({login: vi.fn()}),
  usePrivy: () => privy,
  useToken: () => ({getAccessToken: async () => "access-token"}),
}))
vi.mock("react", () => ({
  default: {
    useRef: (current: unknown) => ({current}),
    useEffect: (effect: () => void) => effect(),
    createElement: (type: any, props: any, child?: any) => ({type, props: {...props, children: child}}),
  },
}))
vi.mock("react-dom/client", () => ({
  createRoot: () => ({
    render(node: any) {
      while (node && typeof node.type === "function") node = node.type(node.props)
    },
  }),
}))

vi.stubGlobal("document", {createElement: () => ({}), body: {append() {}}})

const {startPrivySignIn} = await import("../vendor/regent_privy/privy_sign_in.mjs")

const start = (options = {}) =>
  startPrivySignIn({appId: "app", sessionPath: "/session", csrfToken: "csrf", ...options})

beforeEach(() => {
  privy.authenticated = true
  privy.user = {id: "did:privy:owner"}
  privy.logout.mockClear()
})

it("keeps Privy signed in, and rejects, when the server keeps the session", async () => {
  vi.stubGlobal("fetch", vi.fn(async () => ({ok: false, status: 403})))
  const {signOut} = await start()

  await expect(signOut()).rejects.toThrow()
  expect(privy.logout).not.toHaveBeenCalled()
})

it("logs Privy out once the server has ended the session", async () => {
  vi.stubGlobal("fetch", vi.fn(async () => ({ok: true})))
  const {signOut} = await start()

  await signOut()
  expect(privy.logout).toHaveBeenCalledOnce()
})

it("renews a sign-in that ended for the same person, as a sign-in", async () => {
  const fetch = vi.fn(async () => ({ok: true}))
  vi.stubGlobal("fetch", fetch)
  const onSignedIn = vi.fn()

  await start({session: {id: "did:privy:owner", current: false}, onSignedIn})
  await vi.waitFor(() => expect(onSignedIn).toHaveBeenCalledOnce())

  expect(fetch).toHaveBeenCalledWith(
    "/session",
    expect.objectContaining({
      method: "POST",
      headers: {
        authorization: "Bearer access-token",
        "privy-id-token": "id-token",
        "x-csrf-token": "csrf",
      },
    }),
  )
})

it("never renews for someone else, or while the sign-in still lasts", async () => {
  const fetch = vi.fn(async () => ({ok: true}))
  vi.stubGlobal("fetch", fetch)

  privy.user = {id: "did:privy:someone-else"}
  await start({session: {id: "did:privy:owner", current: false}})
  privy.user = {id: "did:privy:owner"}
  await start({session: {id: "did:privy:owner", current: true}})
  await start({session: null})
  await new Promise(resolve => setTimeout(resolve, 0))

  expect(fetch).not.toHaveBeenCalled()
})
