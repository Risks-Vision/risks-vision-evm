import { ethers } from "hardhat";
import { Contract } from "ethers";

async function main() {
  const [deployer] = await ethers.getSigners();

  console.log("Upgrading contracts with the account:", deployer.address);
  console.log("Account balance:", (await deployer.getBalance()).toString());

  // Configuration - Update these addresses for your deployment
  const PROXY_ADMIN_ADDRESS = process.env.PROXY_ADMIN_ADDRESS || "";
  const PROXY_ADDRESS = process.env.PROXY_ADDRESS || "";

  if (!PROXY_ADMIN_ADDRESS || !PROXY_ADDRESS) {
    console.error("Please set PROXY_ADMIN_ADDRESS and PROXY_ADDRESS environment variables");
    process.exit(1);
  }

  console.log("Proxy Admin Address:", PROXY_ADMIN_ADDRESS);
  console.log("Proxy Address:", PROXY_ADDRESS);

  // Deploy the new implementation contract
  console.log("\n1. Deploying new RevenueDistribution implementation...");
  const RevenueDistribution = await ethers.getContractFactory("RevenueDistribution");
  const newImplementation = await RevenueDistribution.deploy();
  await newImplementation.deployed();
  console.log("New RevenueDistribution implementation deployed to:", newImplementation.address);

  // Get the proxy admin contract
  console.log("\n2. Connecting to ProxyAdmin...");
  const ProxyAdmin = await ethers.getContractFactory("RevenueDistributionProxyAdmin");
  const proxyAdmin = ProxyAdmin.attach(PROXY_ADMIN_ADDRESS);

  // Verify current implementation
  console.log("\n3. Checking current implementation...");
  const currentImplementation = await proxyAdmin.getProxyImplementation(PROXY_ADDRESS);
  console.log("Current implementation:", currentImplementation);

  // Upgrade the proxy to the new implementation
  console.log("\n4. Upgrading proxy to new implementation...");
  const upgradeTx = await proxyAdmin.upgrade(PROXY_ADDRESS, newImplementation.address);
  await upgradeTx.wait();
  console.log("Upgrade transaction hash:", upgradeTx.hash);

  // Verify the upgrade
  console.log("\n5. Verifying upgrade...");
  const newImplementationAddress = await proxyAdmin.getProxyImplementation(PROXY_ADDRESS);
  console.log("New implementation address:", newImplementationAddress);
  console.log("Upgrade successful:", newImplementationAddress === newImplementation.address);

  // Test that the proxy still works
  console.log("\n6. Testing proxy functionality...");
  const revenueDistribution = RevenueDistribution.attach(PROXY_ADDRESS);

  // Check if admin role is still set correctly
  const DEFAULT_ADMIN_ROLE = await revenueDistribution.DEFAULT_ADMIN_ROLE();
  const hasAdminRole = await revenueDistribution.hasRole(DEFAULT_ADMIN_ROLE, deployer.address);
  console.log("Admin role still set correctly:", hasAdminRole);

  // Check immutable values are still accessible
  console.log("\n7. Checking immutable values...");
  console.log("Burn percent:", (await revenueDistribution._burnPercent()).toString());
  console.log("Treasury percent:", (await revenueDistribution._treasuryPercent()).toString());
  console.log("Staking percent:", (await revenueDistribution._stakingPercent()).toString());
  console.log("Marketing percent:", (await revenueDistribution._marketingPercent()).toString());
  console.log("Liquidity percent:", (await revenueDistribution._liquidityPercent()).toString());
  console.log("Stables ratio:", (await revenueDistribution._stablesRatio()).toString());

  console.log("\n=== Upgrade Summary ===");
  console.log("Old implementation:", currentImplementation);
  console.log("New implementation:", newImplementation.address);
  console.log("Proxy address:", PROXY_ADDRESS);
  console.log("Proxy admin address:", PROXY_ADMIN_ADDRESS);
  console.log("Upgrade transaction:", upgradeTx.hash);

  return {
    oldImplementation: currentImplementation,
    newImplementation: newImplementation.address,
    proxy: PROXY_ADDRESS,
    proxyAdmin: PROXY_ADMIN_ADDRESS,
    upgradeTx: upgradeTx.hash,
  };
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
  .then((result) => {
    console.log("\nUpgrade completed successfully!");
    process.exit(0);
  })
  .catch((error) => {
    console.error("Upgrade failed:", error);
    process.exit(1);
  });
