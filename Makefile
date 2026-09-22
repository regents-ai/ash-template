.DEFAULT_GOAL := help
.PHONY: help check-platform check-cli check-contracts
help:
	@echo "Run check-platform, check-cli or check-contracts for the changed component."
check-platform:
	cd platform && mix precommit
check-cli:
	cd cli && pnpm build && pnpm typecheck && pnpm test
check-contracts:
	@echo "contracts/ is empty; add a Foundry project there and replace this target with its checks."
