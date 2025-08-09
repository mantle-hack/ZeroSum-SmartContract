-include .env


deploy:
	@echo "Deploying ZeroSumHardcoreMystery contract..."
	@forge script script/DeployZeroSum.s.sol --broadcast --rpc-url $(RPC_URL) --private-key $(PRIVATE_KEY) --verify