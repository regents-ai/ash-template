import {type BrowserContext, test as base, expect} from "@playwright/test"

// The browser never leaves this machine. The page's sign-in bridge, the only part
// that talks to Privy, is answered by a stand-in that holds no Privy sign-in, as
// a browser without one does; any other outside address is refused and fails the
// check that reached for it. The server's side: playwright.config.ts.
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

// Keeps the context's requests on this machine; returns the outside ones it refused.
export async function onThisMachine(context: BrowserContext, baseURL: string) {
  const site = new URL(baseURL).host
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
  return outside
}

// Each check's own visitor address, from 198.18.0.0/15, the block kept for tests
// (config/dev.exs). A repeat of a check is another visitor.
function visitor(id: string) {
  let hash = 0x811c9dc5
  for (const char of id) hash = Math.imul(hash ^ char.charCodeAt(0), 0x01000193)
  return `198.${18 + ((hash >>> 16) & 1)}.${(hash >>> 8) & 255}.${hash & 255}`
}

export const test = base.extend<{onThisMachine: void}>({
  extraHTTPHeaders: async ({}, use, info) =>
    use({"fly-client-ip": visitor(`${info.testId}:${info.repeatEachIndex}:${info.retry}`)}),
  onThisMachine: [async ({context, baseURL}, use) => {
    const outside = await onThisMachine(context, baseURL!)
    await use()
    expect(outside, "requests that left the machine").toEqual([])
  }, {auto: true}],
})

export {expect}
