.DEFAULT_GOAL := help
.PHONY: help check check-platform check-browser check-required-fixes check-cli check-siwa-latest check-contracts check-dependency-parity release drift account-drift readiness
help:
	@echo "Run make check for every gate, or check-platform, check-browser, check-required-fixes, check-cli, check-siwa-latest or check-contracts for one component."
	@echo "Run make release to run every gate, then build the committed tree into an image and start it against a throwaway database."
	@echo "Run make drift to list where each site's copies of the shared, build and deploy files differ from the template's, then run make readiness."
	@echo "Run make account-drift to check that every site's /account is the template's, file for file; it fails when one differs."
	@echo "Run make readiness to start the local server and check what the agent-readiness scorer looks for."
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
REGENTS_CLI_REV := 0e3768f5b92fe8210fb00fea0053bcb5e9c2afaf
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
# Lists where each site's copies of the template's shared files differ from these,
# reading every site's main branch on GitHub, then measures this checkout the way
# the agent-readiness scorer does. Needs `gh auth login`.
drift:
	scripts/drift.sh
	$(MAKE) readiness
# Checks that every site's /account is the template's: the same files, routed and
# shown the same way. Fails naming each site that differs. Needs `gh auth login`.
account-drift:
	scripts/drift.sh --account
# Starts the local server on a free port, checks what the agent-readiness scorer
# looks for against it, and stops it. Needs the local development database.
readiness:
	scripts/readiness.sh
