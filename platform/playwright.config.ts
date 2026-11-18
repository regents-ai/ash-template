import {availableParallelism} from "node:os"
import {defineConfig, devices} from "@playwright/test"

// The browser walk (the end of mix precommit, or make check-browser alone), started
// by test/browser/walk.sh, which takes the run's port, makes the run's database and
// drops it at the end. Here it builds the pages' scripts and styles, starts its own
// local server on that database, and signs its person in and pairs their agents
// first (test/browser/support/sign_in.exs). It walks a desktop at 1280 wide and a
// touch phone at 390 wide, and opens every page on a touch phone at 320 wide.
// Chromium only: WebKit is not run on the Mac.
// Neither the browser nor the server leaves this machine: the browser's outside
// requests fail the check that made them (test/browser/support/test.ts), and the
// server, with the outside services' settings cleared, refuses its own and the walk
// fails at the end (config/dev.exs, test/browser/support/teardown.ts).
// Before the first check, one signed-in page is opened once, so the first checks do
// not meet a cold server (test/browser/support/warm_up.ts).
// Each run's port and database are its own, so two walks at once, from two
// checkouts, never reach each other's server or data.
// Every walk starts with the homepage's guided tour seen, so it never opens over what
// a walk presses; the saved sign-ins say the same (support/sign_in.exs), and
// tour.spec.ts starts with nothing seen.
// One browser for every three of the machine's cores, at most five: the Mac runs three
// checks at once, and each walk's server, its database and the check's other lanes need
// cores too. With eight browsers a walk, three checks at once left a browser waiting
// past a check's five seconds (17 Nov, load 66).
const workers = Math.max(1, Math.min(5, Math.floor(availableParallelism() / 3)))
const port = Number(process.env.ASH_TEMPLATE_WALK_PORT)
const baseURL = `http://127.0.0.1:${port}`
// The two specs that draw on the graphics card take pictures a set time after a drag or a
// zoom, so they need each frame on time. Run beside each other on every worker, frames came
// late and the Splats page's less-motion checks failed (18 Nov). So each width runs them one
// test at a time, in a lane of its own beside the other checks.
const gpu = ["splats.spec.ts", "scenes.spec.ts"]
const desktop = {...devices["Desktop Chrome"], viewport: {width: 1280, height: 900}}
const phone = {...devices["Pixel 7"], viewport: {width: 390, height: 844}}

export default defineConfig({
  testDir: "./test/browser",
  fullyParallel: true,
  workers,
  forbidOnly: true,
  retries: 0,
  reporter: "line",
  globalSetup: "./test/browser/support/warm_up.ts",
  globalTeardown: "./test/browser/support/teardown.ts",
  use: {
    baseURL,
    trace: "retain-on-failure",
    storageState: {
      cookies: [],
      origins: [{origin: baseURL, localStorage: [{name: "ash-template:tour:home", value: "seen"}]}],
    },
  },
  webServer: {
    command:
      "mkdir -p tmp && rm -f tmp/walk-outside.txt tmp/walk-lines.jsonl && " +
      "unset ASH_TEMPLATE_CHAIN_NODE_URL ASH_TEMPLATE_BASE_NODE_URL " +
      "ASH_TEMPLATE_SIWA_BROKER_URL ETHEREUM_READ_RPC_URL OPENROUTER_API_KEY OPENROUTER_DECISIONS_URL " +
      "ASH_TEMPLATE_NOTES_WEBHOOK_URL ASH_TEMPLATE_INDEXNOW_KEY SIWA_ACTIVITY_READ_TOKEN && " +
      `export PORT=${port} && ` +
      "mix run test/browser/support/sign_in.exs && " +
      "mix assets.build && mix phx.server",
    url: `${baseURL}/healthz`,
    reuseExistingServer: false,
    // Three mix starts in a row; on a busy machine each can take a minute or more.
    timeout: 600_000,
  },
  projects: [
    {name: "desktop", testIgnore: gpu, use: desktop},
    {name: "phone", testIgnore: gpu, use: phone},
    {name: "desktop-gpu", testMatch: gpu, workers: 1, use: desktop},
    {name: "phone-gpu", testMatch: gpu, workers: 1, use: phone},
    // The narrowest phones: every page opens and fits the screen at 320 wide.
    {name: "narrow", testMatch: ["pages.spec.ts", "oauth.spec.ts"], use: {...devices["Pixel 7"], viewport: {width: 320, height: 640}}},
  ],
})
