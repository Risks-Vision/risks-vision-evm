#!/bin/bash

# Script to install dependencies for RevenueDistribution proxy implementation

echo "Installing OpenZeppelin upgradeable contracts..."

# Install the upgradeable contracts package
npm install @openzeppelin/contracts-upgradeable

echo "Dependencies installed successfully!"
echo ""
echo "You can now:"
echo "1. Deploy the proxy: npx hardhat run scripts/deployRevenueDistributionProxy.ts"
echo "2. Run proxy tests: forge test --match-contract RevenueDistributionProxyTests -vv"
echo "3. Upgrade implementation: PROXY_ADMIN_ADDRESS=<addr> PROXY_ADDRESS=<addr> npx hardhat run scripts/upgradeRevenueDistribution.ts"
echo ""
echo "See contracts/revenue/README_PROXY.md for detailed documentation."
