// Invariant: Save on the Account page's Public Display Name writes the name to
// the profile it just read, making that profile from the sign-in only when the
// person has none, and never writes after a read or a profile-making that failed.
import {expect, it} from "vitest"
import {saveName} from "../vendor/regent_ui/profile.mjs"
import type {ProfileAction, ProfileResult} from "../vendor/regent_ui/profile.mjs"

const profile = (id: string, name: string | null = null): ProfileResult =>
  ({ok: true, status: 200, body: {profile: {profile_id: id, display_name: name}}})
const refused = (status: number, code: string): ProfileResult =>
  ({ok: false, status, body: {error: {code}}})

function server(answers: Record<string, ProfileResult>) {
  const calls: unknown[][] = []
  const action: ProfileAction = async (operation, input, options) => {
    calls.push([operation, input, options?.expectedProfileId])
    return answers[operation]
  }
  return {action, calls}
}

it("a first save makes the profile from the sign-in, then saves the name to it", async () => {
  const {action, calls} = server({
    get: refused(404, "profile_not_created"),
    sync: profile("p1"),
    update: profile("p1", "Ada"),
  })

  expect(await saveName(action, "Ada")).toEqual({ok: true, displayName: "Ada", message: "Saved."})
  expect(calls).toEqual([
    ["get", {}, undefined],
    ["sync", {}, undefined],
    ["update", {display_name: "Ada"}, "p1"],
  ])
})

it("a later save changes the name on the profile it read", async () => {
  const {action, calls} = server({get: profile("p2", "Ada"), update: profile("p2", "Grace")})

  expect(await saveName(action, "Grace")).toMatchObject({ok: true, displayName: "Grace"})
  expect(calls.map(call => call[0])).toEqual(["get", "update"])
  expect(calls[1][2]).toBe("p2")
})

it("nothing is written without a current sign-in or a profile", async () => {
  const signedOut = server({get: {ok: false, status: null, error: {code: "authentication_required", outcome_unknown: false}}})
  expect(await saveName(signedOut.action, "Ada")).toEqual({ok: false, message: "Sign in again to save your name."})
  expect(signedOut.calls.map(call => call[0])).toEqual(["get"])

  const conflict = server({get: refused(404, "profile_not_created"), sync: refused(409, "identity_evidence_conflict")})
  expect(await saveName(conflict.action, "Ada")).toEqual({ok: false, message: "Your sign-in changed. Refresh and try again."})
  expect(conflict.calls.map(call => call[0])).toEqual(["get", "sync"])
})

it("a save whose outcome is unknown says so", async () => {
  const {action} = server({
    get: profile("p3"),
    update: {ok: false, status: null, error: {code: "profile_unavailable", outcome_unknown: true}},
  })
  expect(await saveName(action, "Ada")).toEqual({ok: false, message: "It may not have saved. Refresh to check."})
})
