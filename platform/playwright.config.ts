import {defineConfig, devices} from "@playwright/test"

// The browser walk (make check-browser). It starts its own local server on the
// walk's own database, ash_template_browser_dev, and signs its person in first
// (test/browser/support/sign_in.exs). Chromium only: WebKit is not run on the Mac.
const port = 4098
const baseURL = `http://127.0.0.1:${port}`

export default defineConfig({
  testDir: "./test/browser",
  fullyParallel: true,
  workers: 3,
  forbidOnly: true,
  retries: 0,
  reporter: "line",
  use: {
    baseURL,
    trace: "retain-on-failure",
  },
  webServer: {
    command:
      `export ASH_TEMPLATE_DEV_PARTITION=_browser PORT=${port} POOL_SIZE=3 && ` +
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
