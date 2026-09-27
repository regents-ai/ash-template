.DEFAULT_GOAL := help
.PHONY: help check check-platform check-cli check-contracts
help:
	@echo "Run make check for every gate, or check-platform, check-cli or check-contracts for one component."
check: check-platform check-cli check-contracts
check-platform:
	cd platform && mix precommit && npm run typecheck
REGENTS_CLI ?= ../regents-cli
check-cli:
	node $(REGENTS_CLI)/scripts/check-platform-commands.mjs cli/commands.json platform/priv/public/openapi.json platform/priv/static/api-contract.openapiv3.yaml
check-contracts:
	@echo "contracts/ is empty; add a Foundry project there and replace this target with its checks."
