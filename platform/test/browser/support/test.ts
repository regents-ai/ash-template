import {test as base, expect} from "@playwright/test"

// The walk never leaves this machine. The page's sign-in bridge, the only part
// that talks to Privy, is answered by a stand-in that holds no Privy sign-in, as
// a browser without one does; any other outside address is refused and fails the
// check that reached for it.
const bridge = /^\/assets\/js\/privy_bridge(-[0-9a-f]+)?\.js$/

const standIn = `
export async function startPrivyBridge() {
  return {
    request: async () => {},
    openProfile: () => async () =>
      ({ok: false, status: null, error: {code: "authentication_required", outcome_unknown: false}}),
  }
}
`

export const test = base.extend<{onThisMachine: void}>({
  onThisMachine: [async ({context, baseURL}, use) => {
    const site = new URL(baseURL!).host
    const outside: string[] = []
    await context.route(() => true, route => {
      const url = new URL(route.request().url())
      if (url.host !== site) {
        outside.push(`${route.request().method()} ${url.origin}${url.pathname}`)
        return route.abort("blockedbyclient")
      }
      if (bridge.test(url.pathname))
        return route.fulfill({contentType: "text/javascript", body: standIn})
      return route.continue()
    })
    await use()
    expect(outside, "requests that left the machine").toEqual([])
  }, {auto: true}],
})

export {expect}
