.DEFAULT_GOAL := help
.PHONY: help check check-style check-platform platform-precommit platform-test check-browser check-scripts check-required-fixes check-cli check-siwa-latest check-contracts check-dependency-parity release live-check readiness
help:
	@echo "Run make check for every gate, side by side, each writing its output to platform/_build/check/<gate>.log; it prints every gate's log, the failed ones last, then one line per gate. Or run check-style, check-platform, check-browser, check-scripts, check-required-fixes, check-cli, check-siwa-latest or check-contracts for one component."
	@echo "Run make check-scripts to test scripts/deploy.sh and scripts/rollback.sh on a fixture repository, with stand-ins for Fly and the site."
	@echo "Run make release to run every gate, then build the committed tree into an image and start it against a throwaway database."
	@echo "Run SIWA_AGENT_HOME=<the agent's key folder> SIWA_CLIENT=<its siwa_agent.py> make live-check to check template.regents.sh the way a paired agent does: the CLI, then WebMCP and every public page in headless Chromium."
# template-only
	@echo "Run make drift to list where each site's copies of the shared, build and deploy files differ from the template's, then run make pins and make readiness."
	@echo "Run make pins to list each site's shared-library pins and how far each is behind the template's and the library's main."
	@echo "make check-scripts also tests the reports the daily jobs read: scripts/drift.sh, scripts/pins.sh and scripts/harvest.sh."
# /template-only
	@echo "Run make readiness to start the local server and check what the agent-readiness scorer looks for."
# template-only
# The passages fenced like this one are the template's own: scripts/init.sh drops
# them, and scripts/drift.sh compares the rest of this file with each site's.
.PHONY: drift pins
# /template-only
# make check runs its gates side by side, each writing its output to
# $(CHECK_LOGS)/<gate>.log, then prints every gate's log, the failed ones last, and
# one line per gate, and fails when any gate failed. The gates of one quoted lane
# run in turn: check-style and mix precommit both compile _build/dev, and both run
# mix regent_ui.assets, which deletes assets/vendor/regent_ui and copies it again;
# mix test's script build (ScriptBuildTest) reads that folder and writes the
# scripts the browser walk at the end of mix precommit serves. The other gates
# write nothing another reads.
CHECK_LANES := "check-style platform-precommit platform-test" check-scripts check-required-fixes check-cli check-siwa-latest check-contracts
CHECK_GATES := $(subst ",,$(CHECK_LANES))
CHECK_LOGS := platform/_build/check
check:
	@mkdir -p $(CHECK_LOGS) && : > $(CHECK_LOGS)/results
	@echo "Running $(words $(CHECK_GATES)) gates side by side; each writes $(CHECK_LOGS)/<gate>.log."
	@for lane in $(CHECK_LANES); do \
	  for gate in $$lane; do \
	    start=$$(date +%s); \
	    $(MAKE) --no-print-directory $$gate > $(CHECK_LOGS)/$$gate.log 2>&1; \
	    code=$$?; echo "$$gate $$code $$(( $$(date +%s) - start ))" >> $(CHECK_LOGS)/results; \
	  done & \
	done; wait
	@failed=; \
	for gate in $(CHECK_GATES); do \
	  if grep -q "^$$gate 0 " $(CHECK_LOGS)/results; then \
	    echo; echo "== $$gate ($(CHECK_LOGS)/$$gate.log)"; cat $(CHECK_LOGS)/$$gate.log; \
	  else failed="$$failed $$gate"; fi; \
	done; \
	for gate in $$failed; do \
	  echo; echo "== $$gate FAILED ($(CHECK_LOGS)/$$gate.log)"; cat $(CHECK_LOGS)/$$gate.log; \
	done; \
	echo; \
	for gate in $(CHECK_GATES); do \
	  set -- $$(grep "^$$gate " $(CHECK_LOGS)/results); \
	  if [ "$$2" = 0 ]; then echo "$$gate: ok in $$3 s"; else echo "$$gate: FAILED after $$3 s"; fi; \
	done; \
	test -z "$$failed"
# The design system's style check (STYLE.md): every break of a style rule in the
# site's own CSS, scripts and templates, by file and line. An exception Sean approved
# carries its marker on the line. mix regent_ui.assets copies the script from the
# pinned design system. Needs ripgrep, awk and perl; without one it stops with exit 2
# and names it, never passing.
check-style:
	cd platform && mix regent_ui.assets && bash assets/vendor/regent_ui/style-check.sh
# mix precommit ends with the TypeScript typecheck and tests and the browser walk;
# mix test runs after it.
check-platform: platform-precommit platform-test
platform-precommit:
	cd platform && mix precommit
platform-test:
	cd platform && mix test
# The deploy and rollback scripts' tests (scripts/tests/test_release.py), and every
# other test in scripts/tests, on fixture repositories with stand-ins for Fly, GitHub
# and the site. They reach no real app.
check-scripts:
	uv run --no-project python -B -m unittest discover -s scripts/tests
# The browser walk alone (platform/test/browser): every page at phone and desktop
# width, and the paths a person takes. It starts its own server on its own database,
# with Privy settings the server makes for itself, so it needs none of the site's.
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
REGENTS_CLI_REV := 1608c83572425ff17dc535c01351b68ee5337e96
check-cli:
	uv run --no-project --with "regents-cli[check] @ git+https://github.com/regents-ai/regents-cli@$(REGENTS_CLI_REV)" \
	  python -m regents_cli.check_commands cli/commands.json platform/priv/public/openapi.json platform/priv/static/api-contract.openapiv3.yaml
# Every site is on the newest SIWA: the newest regents-cli release on PyPI (the pin
# above, the agent guide and the install lines) and the newest change to the SIWA
# library in elixir-utils. Needs `gh auth login`.
check-siwa-latest:
	scripts/check-siwa-latest.sh $(REGENTS_CLI_REV)
# A site with contracts replaces this target with its Foundry checks under nice
# (contracts/README.md): the Solidity compiler takes every core it can, and beside
# the other gates in make check it gives way to them.
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
