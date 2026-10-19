import {execFileSync} from "node:child_process"
import {defineConfig, devices} from "@playwright/test"

// The browser walk (make check-browser). It starts its own local server on the
// walk's own database, ash_template_browser_dev, and signs its person in first
// (test/browser/support/sign_in.exs). Chromium only: WebKit is not run on the Mac.
// Neither the browser nor the server leaves this machine: the browser's outside
// requests fail the check that made them (test/browser/support/test.ts), and the
// server, with the outside services' settings cleared, refuses its own and the walk
// fails at the end (config/dev.exs, test/browser/support/outside_teardown.ts).
// Each run takes a port nothing on this machine is using, so two walks at once,
// from two checkouts, never reach each other's server. The workers read this
// file again and keep the run's port from the environment they inherit.
process.env.ASH_TEMPLATE_WALK_PORT ??= execFileSync(process.execPath, [
  "-e",
  "const s = require('node:net').createServer().listen(0, '127.0.0.1', () => { console.log(s.address().port); s.close() })",
]).toString().trim()
const port = Number(process.env.ASH_TEMPLATE_WALK_PORT)
const baseURL = `http://127.0.0.1:${port}`

export default defineConfig({
  testDir: "./test/browser",
  fullyParallel: true,
  workers: 3,
  forbidOnly: true,
  retries: 0,
  reporter: "line",
  globalTeardown: "./test/browser/support/outside_teardown.ts",
  use: {
    baseURL,
    trace: "retain-on-failure",
  },
  webServer: {
    command:
      "mkdir -p tmp && rm -f tmp/walk-outside.txt && " +
      "unset ASH_TEMPLATE_CHAIN_NODE_URL ASH_TEMPLATE_BASE_NODE_URL ASH_TEMPLATE_ETHEREUM_NODE_URL " +
      "ASH_TEMPLATE_SIWA_BROKER_URL ETHEREUM_READ_RPC_URL OPENROUTER_API_KEY OPENROUTER_DECISIONS_URL " +
      "ASH_TEMPLATE_NOTES_WEBHOOK_URL SIWA_ACTIVITY_READ_TOKEN && " +
      `export ASH_TEMPLATE_WALK=true ASH_TEMPLATE_DEV_PARTITION=_browser PORT=${port} POOL_SIZE=3 && ` +
      "mix ecto.create --quiet && mix run test/browser/support/sign_in.exs && mix phx.server",
    url: `${baseURL}/healthz`,
    reuseExistingServer: false,
    timeout: 180_000,
  },
  projects: [
    {name: "desktop", use: {...devices["Desktop Chrome"], viewport: {width: 1280, height: 900}}},
    {name: "phone", use: {...devices["Desktop Chrome"], viewport: {width: 390, height: 844}}},
  ],
})
