// Invariant: the shared Privy reader (regent_privy) hands the server a whole pair
// or nothing. The identity token is read before the access token, so the session
// proof is never older than the evidence it goes with, and an attempt that goes
// stale between reads stops there.
import {expect, it, vi} from "vitest"

vi.mock("@privy-io/react-auth", () => ({}))
vi.mock("react-dom/client", () => ({}))

const {privyLoginFailure, privyPairHeaders, readPrivyPair} = await import(
  "../vendor/regent_privy/privy_sign_in.mjs"
)

it("reads the identity token first, then the access token", async () => {
  const reads: string[] = []
  const pair = await readPrivyPair({
    getIdentityToken: async () => (reads.push("identity"), "id-token"),
    getAccessToken: async () => (reads.push("access"), "access-token"),
  })

  expect(reads).toEqual(["identity", "access"])
  expect(pair).toEqual({accessToken: "access-token", identityToken: "id-token"})
})

it("never returns half a pair", async () => {
  for (const [identity, access] of [[null, "access-token"], ["id-token", null], ["id-token", "  "]]) {
    await expect(
      readPrivyPair({getIdentityToken: async () => identity, getAccessToken: async () => access}),
    ).rejects.toThrow()
  }
})

it("stops between reads when the attempt goes stale", async () => {
  let current = true
  const getAccessToken = vi.fn(async () => "access-token")
  const stale = new Error("stale")

  await expect(
    readPrivyPair({
      getIdentityToken: async () => ((current = false), "id-token"),
      getAccessToken,
      requireCurrent: () => {
        if (!current) throw stale
      },
    }),
  ).rejects.toBe(stale)
  expect(getAccessToken).not.toHaveBeenCalled()
})

it("sends each token in its own header", () => {
  expect(privyPairHeaders({accessToken: "access-token", identityToken: "id-token"})).toEqual({
    authorization: "Bearer access-token",
    "privy-id-token": "id-token",
  })
})

it("names Privy's login errors, and anything else as a provider error", () => {
  expect(privyLoginFailure("exited_auth_flow")).toBe("flow_closed")
  expect(privyLoginFailure("client_request_timeout")).toBe("request_timeout")
  expect(privyLoginFailure(new Error("boom"))).toBe("provider_error")
})
