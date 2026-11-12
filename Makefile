.DEFAULT_GOAL := help
.PHONY: help check check-platform check-browser check-required-fixes check-cli check-siwa-latest check-contracts check-dependency-parity release live-check readiness
help:
	@echo "Run make check for every gate, or check-platform, check-browser, check-required-fixes, check-cli, check-siwa-latest or check-contracts for one component."
	@echo "Run make release to run every gate, then build the committed tree into an image and start it against a throwaway database."
	@echo "Run SIWA_AGENT_HOME=<the agent's key folder> SIWA_CLIENT=<its siwa_agent.py> make live-check to check template.regents.sh the way a paired agent does: the CLI, then WebMCP and every public page in headless Chromium."
# template-only
	@echo "Run make drift to list where each site's copies of the shared, build and deploy files differ from the template's, then run make pins and make readiness."
	@echo "Run make pins to list each site's shared-library pins and how far each is behind the template's and the library's main."
	@echo "Run make check-scripts to test the reports the daily jobs read: scripts/drift.sh, scripts/pins.sh and scripts/harvest.sh."
# /template-only
	@echo "Run make readiness to start the local server and check what the agent-readiness scorer looks for."
# template-only
# The passages fenced like this one are the template's own: scripts/init.sh drops
# them, and scripts/drift.sh compares the rest of this file with each site's.
.PHONY: check-scripts drift pins
check: check-scripts
# The reports' tests, on fixture repositories (scripts/tests/test_reports.py).
check-scripts:
	uv run --no-project python -B -m unittest discover -s scripts/tests -p 'test_reports.py'
# /template-only
check: check-platform check-required-fixes check-cli check-siwa-latest check-contracts
# mix precommit ends with the TypeScript typecheck, the script tests and the
# browser walk.
check-platform:
	cd platform && mix precommit && mix test
# The browser walk alone (platform/test/browser): every page at phone and desktop
# width, and the paths a person takes. It starts its own server on its own database.
check-browser:
	cd platform && npm run test:browser
# Every site runs the same check against ash-template's current main branch, so a
# newly published required fix reaches every site's next gate. Needs `gh auth login`.
TEMPLATE := repos/regents-ai/ash-template
check-required-fixes:
	cd platform && mkdir -p _build && rev=$$(gh api $(TEMPLATE)/commits/main --jq .sha) \
	&& gh api -H "Accept: application/vnd.github.raw" "$(TEMPLATE)/contents/platform/scripts/check_required_fixes.exs?ref=$$rev" > _build/check_required_fixes.exs \
	&& gh api -H "Accept: application/vnd.github.raw" "$(TEMPLATE)/contents/security/required-fixes.json?ref=$$rev" > _build/required-fixes.json \
	&& elixir _build/check_required_fixes.exs "ash-template $$rev" < _build/required-fixes.json
# The command description check is regents-cli's own checker at the commit pinned
# here, run by uv straight from GitHub. Move the pin in a commit.
REGENTS_CLI_REV := fd325437e29fc6b239955e6ce946168bea2fb4ef
check-cli:
	uv run --no-project --with "regents-cli[check] @ git+https://github.com/regents-ai/regents-cli@$(REGENTS_CLI_REV)" \
	  python -m regents_cli.check_commands cli/commands.json platform/priv/public/openapi.json platform/priv/static/api-contract.openapiv3.yaml
# Every site is on the newest SIWA: the newest regents-cli release on PyPI (the pin
# above, the agent guide and the install lines) and the newest change to the SIWA
# library in elixir-utils. Needs `gh auth login`.
check-siwa-latest:
	scripts/check-siwa-latest.sh $(REGENTS_CLI_REV)
check-contracts:
	@echo "contracts/ is empty; add a Foundry project there and replace this target with its checks."
# Read-only comparison with explicitly selected local site checkouts.
# Example: make check-dependency-parity SITES="../regents ../patchbay"
check-dependency-parity:
	@test -n "$(SITES)" || { echo 'Set SITES to the site repository paths to compare.' >&2; exit 2; }
	python3 scripts/check-dependency-parity.py . $(SITES)
# The release checks and builds exactly the committed tree, so every change must
# be committed first. A failing gate stops it before anything is built.
release:
	@test -z "$$(git status --porcelain)" || { echo "Commit every change first: the release checks and builds the committed tree." >&2; exit 1; }
	$(MAKE) check
	scripts/release.sh
# The live site, checked the way an agent checks it (skills/regent-workflow, "Live
# checks"): the CLI as the paired agent whose key is in SIWA_AGENT_HOME, then WebMCP
# and every public page in headless Chromium (scripts/live-check.sh). It writes only
# the agent's own row on the site: when the agent was last seen.
live-check:
	scripts/live-check.sh
# template-only
# Lists where each site's copies of the template's shared files differ from these,
# reading every site's main branch on GitHub, then each site's shared-library pins,
# each as JSON, then measures this checkout the way the agent-readiness scorer does.
# Needs `gh auth login` and jq.
drift:
	scripts/drift.sh
	$(MAKE) pins
	$(MAKE) readiness
# Every site's shared-library pins (elixir-utils, design-system, ash_postgres, siwa
# and the regents-cli its Makefile checks with), each with how far it is behind the
# template's pin and the library's main, printed as JSON. Needs `gh auth login`, git
# and jq.
pins:
	scripts/pins.sh
# /template-only
# Starts the local server on a free port, checks what the agent-readiness scorer
# looks for against it, and stops it. Needs the local development database.
readiness:
	scripts/readiness.sh
