#!/bin/sh
# The browser walk (make check-browser, npm run test:browser). It takes a port nothing
# on this machine is using, makes the run's database, named after the port,
# ash_template_browser_<port>_dev, and drops it when the walk ends, whatever
# happens: passed, failed, stopped, or a server that never started, when Playwright
# skips its own teardown. Arguments go to Playwright.
set -eu

port=$(node -e "const s = require('node:net').createServer().listen(0, '127.0.0.1', () => { console.log(s.address().port); s.close() })")
export ASH_TEMPLATE_WALK_PORT="$port" ASH_TEMPLATE_DEV_PARTITION="_browser_$port"
echo "The walk runs on port $port with its own database, ash_template_browser_${port}_dev."

drop() {
  status=$?
  mix run --no-start test/browser/support/drop.exs || status=1
  exit "$status"
}
trap drop EXIT
trap 'exit 130' INT TERM

mix ecto.create --quiet
npx playwright test "$@"
