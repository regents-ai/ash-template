import {defineConfig, devices} from "@playwright/test"

// The browser walk (the end of mix precommit, or make check-browser alone), started
// by test/browser/walk.sh, which takes the run's port, makes the run's database and
// drops it at the end. Here it builds the pages' scripts and styles, starts its own
// local server on that database, and signs its person in and pairs their agents
// first (test/browser/support/sign_in.exs). It walks a desktop at 1280 wide and a
// touch phone at 390 wide. Chromium only: WebKit is not run on the Mac.
// Neither the browser nor the server leaves this machine: the browser's outside
// requests fail the check that made them (test/browser/support/test.ts), and the
// server, with the outside services' settings cleared, refuses its own and the walk
// fails at the end (config/dev.exs, test/browser/support/teardown.ts).
// Each run's port and database are its own, so two walks at once, from two
// checkouts, never reach each other's server or data.
const port = Number(process.env.ASH_TEMPLATE_WALK_PORT)
const baseURL = `http://127.0.0.1:${port}`

export default defineConfig({
  testDir: "./test/browser",
  fullyParallel: true,
  workers: 3,
  forbidOnly: true,
  retries: 0,
  reporter: "line",
  globalTeardown: "./test/browser/support/teardown.ts",
  use: {
    baseURL,
    trace: "retain-on-failure",
  },
  webServer: {
    command:
      "mkdir -p tmp && rm -f tmp/walk-outside.txt tmp/walk-lines.jsonl && " +
      "unset ASH_TEMPLATE_CHAIN_NODE_URL ASH_TEMPLATE_BASE_NODE_URL ASH_TEMPLATE_ETHEREUM_NODE_URL " +
      "ASH_TEMPLATE_SIWA_BROKER_URL ETHEREUM_READ_RPC_URL OPENROUTER_API_KEY OPENROUTER_DECISIONS_URL " +
      "ASH_TEMPLATE_NOTES_WEBHOOK_URL ASH_TEMPLATE_INDEXNOW_KEY SIWA_ACTIVITY_READ_TOKEN && " +
      `export ASH_TEMPLATE_WALK=true PORT=${port} POOL_SIZE=3 && ` +
      "mix run test/browser/support/sign_in.exs && " +
      "mix assets.build && mix phx.server",
    url: `${baseURL}/healthz`,
    reuseExistingServer: false,
    // Three mix starts in a row; on a busy machine each can take a minute or more.
    timeout: 600_000,
  },
  projects: [
    {name: "desktop", use: {...devices["Desktop Chrome"], viewport: {width: 1280, height: 900}}},
    {name: "phone", use: {...devices["Pixel 7"], viewport: {width: 390, height: 844}}},
  ],
})
