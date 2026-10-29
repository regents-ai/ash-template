import {defineConfig, devices} from "@playwright/test"

// The live check's browser half (make live-check, scripts/live-check.sh): the live
// site read the way an agent's browser reads it, in headless Chromium at 1280 and
// 390 wide. It opens the public pages and documents, lists the WebMCP tools the home
// page registers, calls the public reads, and calls the signed reads with the agent's
// key (SIWA_AGENT_HOME) through the SIWA client SIWA_CLIENT (test/live/live.spec.ts).
// It writes only the agent's own row on the site: when the agent was last seen.
// Chromium only: WebKit is not run on the Mac.
const baseURL = process.env.LIVE_URL
if (!baseURL) throw new Error("Set LIVE_URL to the live site's address. Run it through make live-check.")

export default defineConfig({
  testDir: "./test/live",
  fullyParallel: true,
  workers: 2,
  forbidOnly: true,
  retries: 0,
  reporter: "line",
  // Global Privacy Control, so the check's pages start no visit in the site's log
  // (AshTemplateWeb.VisitLog). No traces: they would keep signed headers on disk.
  use: {baseURL, extraHTTPHeaders: {"sec-gpc": "1"}, trace: "off"},
  projects: [
    {name: "desktop", use: {...devices["Desktop Chrome"], viewport: {width: 1280, height: 900}}},
    {name: "phone", use: {...devices["Pixel 7"], viewport: {width: 390, height: 844}}},
  ],
})
