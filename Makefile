.DEFAULT_GOAL := help
.PHONY: help check check-style check-platform check-required-fixes check-cli check-contracts release live-check readiness
help:
	@echo "Run make check for every self-contained gate (style, platform precommit, required-fixes, contracts)."
	@echo "Run check-style, check-platform, check-required-fixes, check-cli or check-contracts for one component."
	@echo "Run make release to run every gate, then build the committed tree into an image and start it against a throwaway database."
	@echo "Run make readiness to start the local server and check what the agent-readiness scorer looks for."

# make check runs its gates side by side, each writing its output to
# $(CHECK_LOGS)/<gate>.log, then prints every gate's log, the failed ones last, and
# one line per gate, and fails when any gate failed. The gates of one quoted lane
# run in turn: check-style and mix precommit both compile _build/dev, and both run
# mix regent_ui.assets, which deletes assets/vendor/regent_ui and copies it again.
# The other gates write nothing another reads.
CHECK_LANES := "check-style check-platform" check-required-fixes check-contracts
CHECK_GATES := $(subst ",,$(CHECK_LANES))
CHECK_LOGS := platform/_build/check
CHECK_BUDGETS := check-style:5 check-platform:18 check-required-fixes:5 check-contracts:5
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
	  budget=$$(printf '%s\n' $(CHECK_BUDGETS) | sed -n "s/^$$gate://p"); \
	  if [ "$$3" -gt "$$budget" ]; then echo "SLOW: $$gate took $$3 s (budget $$budget s)"; fi; \
	done; \
	test -z "$$failed"

# The design system's style check (STYLE.md): every break of a style rule in the
# site's own CSS, scripts and templates, by file and line. mix regent_ui.assets
# copies the script from the pinned design system. Needs ripgrep, awk and perl.
check-style:
	cd platform && mix regent_ui.assets && bash assets/vendor/regent_ui/style-check.sh

# mix precommit compiles with warnings as errors and ends with the TypeScript
# typecheck.
check-platform:
	cd platform && mix precommit

# Checks shared library pins and Hex package minimums against security/required-fixes.json.
check-required-fixes:
	cd platform && elixir scripts/check_required_fixes.exs "local security/required-fixes.json" < ../security/required-fixes.json

# Optional: validates cli/commands.json against the OpenAPI documents using regents-cli via uv.
REGENTS_CLI_REV := c12d8563c46e8b5229e32db76c1a104fb469b7b7
check-cli:
	uv run --no-project --with "regents-cli[check] @ git+https://github.com/regents-ai/regents-cli@$(REGENTS_CLI_REV)" \
	  python -m regents_cli.check_commands cli/commands.json platform/priv/public/openapi.json platform/priv/static/api-contract.openapiv3.yaml

# A site with contracts replaces this target with its Foundry checks under nice.
check-contracts:
	@echo "contracts/ is empty; add a Foundry project there and replace this target with its checks."

# The release checks and builds exactly the committed tree, so every change must
# be committed first. A failing gate stops it before anything is built.
release:
	@test -z "$$(git status --porcelain)" || { echo "Commit every change first: the release checks and builds the committed tree." >&2; exit 1; }
	$(MAKE) check
	scripts/release.sh

live-check:
	scripts/live-check.sh

# Starts the local server on a free port, checks what the agent-readiness scorer
# looks for against it, and stops it. Needs the local development database.
readiness:
	scripts/readiness.sh
