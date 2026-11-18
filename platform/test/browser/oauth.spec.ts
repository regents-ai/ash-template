import {createHash, randomBytes} from "node:crypto"
import {createServer, type RequestListener, type Server} from "node:http"
import type {AddressInfo} from "node:net"
import type {APIRequestContext, Page} from "@playwright/test"
import {expect, test} from "./support/test"
import {bareAddresses} from "./support/addresses"
import {unreachableScrollers} from "./support/scrollers"
import {signedIn, watch} from "./support/person"

// The connector's pages open only for an app registered here (RegentOAuth, from
// elixir-utils): the consent page names the app, a row for each thing it may do and
// the host it returns to, and the person allows or cancels; Connected apps lists
// each app with the day it connected and Disconnect. Each fits the screen, shows every address with its copy icon and lets
// a keyboard scroll every box that scrolls, at every width the walk runs. The app
// has a long name and a long return address, as a real one may; the walk answers
// that address itself, so the return goes nowhere else.
const callback = "https://agent-callbacks.research-assistant-for-long-organisation-names.localhost/api/mcp/auth_callback"

async function register(request: APIRequestContext, name: string, redirect = callback) {
  const response = await request.post("/oauth/register", {
    data: {client_name: name, redirect_uris: [redirect]},
    headers: {accept: "application/json"},
  })
  expect(response.status()).toBe(201)
  return (await response.json()).client_id as string
}

// A server on this machine for one of an app's own addresses.
async function serve(listener: RequestListener): Promise<{server: Server; origin: string}> {
  const server = createServer(listener)
  await new Promise<void>(resolve => server.listen(0, "127.0.0.1", resolve))
  return {server, origin: `http://127.0.0.1:${(server.address() as AddressInfo).port}`}
}

// The address an app sends the person to, asking for every permission the site has.
async function consent(request: APIRequestContext, clientId: string, verifier: string, redirect = callback) {
  const {resource, scopes_supported: scopes} = await (await request.get("/.well-known/oauth-protected-resource")).json()
  const query = new URLSearchParams({
    client_id: clientId,
    redirect_uri: redirect,
    response_type: "code",
    scope: scopes.join(" "),
    state: "walk",
    resource,
    code_challenge: createHash("sha256").update(verifier).digest("base64url"),
    code_challenge_method: "S256",
  })
  return `/oauth/authorize?${query}`
}

async function fits(page: Page, problems: ReturnType<typeof watch>) {
  expect(await bareAddresses(page)).toEqual([])
  expect(await unreachableScrollers(page)).toEqual([])
  await problems.expect()
}

test("signed out, the consent page asks the person to sign in first", async ({page}, testInfo) => {
  const problems = watch(page)
  const clientId = await register(page.request, `Research Assistant for Long Organisation Names (${testInfo.project.name})`)
  await page.goto(await consent(page.request, clientId, randomBytes(32).toString("base64url")))
  await expect(page.getByRole("heading", {level: 1})).toHaveText("Sign in to connect")
  await expect(page.getByRole("link", {name: "Continue after signing in"})).toBeVisible()
  await fits(page, problems)
})

test.describe("signed in", () => {
  test.use(signedIn)

  test("the consent page connects the app, and Connected apps disconnects it", async ({page}, testInfo) => {
    const name = `Research Assistant for Long Organisation Names (${testInfo.project.name})`
    const verifier = randomBytes(32).toString("base64url")
    const clientId = await register(page.request, name)
    const problems = watch(page)

    await page.goto(await consent(page.request, clientId, verifier))
    await expect(page.getByRole("heading", {level: 1})).toHaveText(`Connect ${name}`)
    await expect(page.getByText(`Returns to ${new URL(callback).host}`)).toBeVisible()
    await expect(page.getByRole("button", {name: "Allow"})).toBeVisible()
    await expect(page.getByRole("button", {name: "Cancel"})).toBeVisible()
    await fits(page, problems)

    // Allow returns the person to the app with a code, which the app trades for its
    // tokens. The browser follows the page Allow answers to the app's callback.
    await page.route(url => url.href.startsWith(`${callback}?`), route => route.fulfill({contentType: "text/plain", body: "Returned"}))
    await page.getByRole("button", {name: "Allow"}).click()
    await page.waitForURL(url => url.href.startsWith(`${callback}?`))
    const code = new URL(page.url()).searchParams.get("code")!
    const {resource} = await (await page.request.get("/.well-known/oauth-protected-resource")).json()
    const token = await page.request.post("/oauth/token", {
      form: {grant_type: "authorization_code", client_id: clientId, code, redirect_uri: callback, code_verifier: verifier, resource},
    })
    expect(token.status()).toBe(200)

    const connected = watch(page)
    await page.goto("/oauth/connections")
    await expect(page.getByRole("heading", {level: 1})).toHaveText("Connected apps")
    const app = page.getByRole("listitem").filter({hasText: name})
    await expect(app.getByRole("button", {name: "Disconnect"})).toBeVisible()
    await fits(page, connected)

    await app.getByRole("button", {name: "Disconnect"}).click()
    await expect(page).toHaveURL(/\/oauth\/connections$/)
    await expect(page.getByRole("listitem").filter({hasText: name})).toHaveCount(0)
  })

  // Seen live on 18 Nov 2026: an app's callback sent the browser on to another host,
  // and Chromium stopped that redirect after Allow's form, so Allow did nothing. The
  // app's two hosts here are two servers on this machine.
  test("Allow reaches an app whose callback sends the browser on to another host", async ({page}, testInfo) => {
    const landing = await serve((_request, response) => {
      response.writeHead(200, {"content-type": "text/plain"}).end("Landed")
    })
    const app = await serve((request, response) => {
      const {search} = new URL(request.url!, "http://app.localhost")
      response.writeHead(302, {location: `${landing.origin}/landed${search}`}).end()
    })

    try {
      const redirect = `${app.origin}/callback`
      const verifier = randomBytes(32).toString("base64url")
      const clientId = await register(page.request, `Forwarding App (${testInfo.project.name})`, redirect)
      await page.route(url => [app.origin, landing.origin].includes(url.origin), route => route.continue())

      await page.goto(await consent(page.request, clientId, verifier, redirect))
      await page.getByRole("button", {name: "Allow"}).click()
      await page.waitForURL(url => url.origin === landing.origin)

      const code = new URL(page.url()).searchParams.get("code")!
      const {resource} = await (await page.request.get("/.well-known/oauth-protected-resource")).json()
      const token = await page.request.post("/oauth/token", {
        form: {grant_type: "authorization_code", client_id: clientId, code, redirect_uri: redirect, code_verifier: verifier, resource},
      })
      expect(token.status()).toBe(200)
    } finally {
      app.server.close()
      landing.server.close()
    }
  })
})
