// Invariant: the sign-in bridge hands the server Privy's pair through the shared
// regent_privy reader, the file `mix regent_privy.assets` copies in and the bridge
// bundles: the identity token is read before the access token, so the session
// proof is never older than the evidence it goes with; a whole pair or nothing;
// an attempt gone stale between reads stops there; each token in its own header.
// The bridge names a Privy login failure by the shared naming too.
import {expect, it, vi} from "vitest"
import type {PrivyEvents} from "@privy-io/react-auth"

vi.mock("@privy-io/react-auth", () => ({}))
vi.mock("react-dom/client", () => ({}))

const {privyPairHeaders, readPrivyPair} = await import("../vendor/regent_privy/privy_sign_in.mjs")
const {createPrivyLoginCallbacks} = await import("../js/privy_bridge")

it("reads the identity token first, then the access token, and sends each in its own header", async () => {
  const reads: string[] = []
  const pair = await readPrivyPair({
    getIdentityToken: async () => (reads.push("identity"), "id-token"),
    getAccessToken: async () => (reads.push("access"), "access-token"),
  })

  expect(reads).toEqual(["identity", "access"])
  expect(privyPairHeaders(pair)).toEqual({
    authorization: "Bearer access-token",
    "privy-id-token": "id-token",
  })
})

it("never hands over half a pair", async () => {
  const halves: [string | null, string | null][] = [[null, "access-token"], ["id-token", null], ["id-token", "  "]]

  for (const [identity, access] of halves) {
    await expect(
      readPrivyPair({getIdentityToken: async () => identity, getAccessToken: async () => access}),
    ).rejects.toThrow()
  }
})

it("stops between reads once the attempt is stale", async () => {
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

it("the bridge reports a Privy login failure by its shared name, and says nothing when the person closed the window", () => {
  const fail = (error: unknown) => {
    const reportFailure = vi.fn()
    const showFailure = vi.fn()
    const callbacks = createPrivyLoginCallbacks({
      completeLogin: vi.fn(async () => undefined),
      loginOpen: {current: true},
      showFailure,
      reportFailure,
    })
    const failed = callbacks.onError as NonNullable<PrivyEvents["login"]["onError"]>
    failed(error as Parameters<typeof failed>[0])
    return {reported: reportFailure.mock.calls, shown: showFailure.mock.calls}
  }

  expect(fail("exited_auth_flow")).toEqual({reported: [["flow_closed"]], shown: []})
  expect(fail("client_request_timeout")).toEqual({reported: [["request_timeout"]], shown: [["provider"]]})
  expect(fail("something_new")).toEqual({reported: [["provider_error"]], shown: [["provider"]]})
})
