import { ethers } from "hardhat";
import { Contract } from "ethers";

async function main() {
  const [deployer] = await ethers.getSigners();

  console.log("Deploying contracts with the account:", deployer.address);
  console.log("Account balance:", (await deployer.getBalance()).toString());

  // Deploy the implementation contract
  console.log("\n1. Deploying RevenueDistribution implementation...");
  const RevenueDistribution = await ethers.getContractFactory("RevenueDistribution");
  const implementation = await RevenueDistribution.deploy();
  await implementation.deployed();
  console.log("RevenueDistribution implementation deployed to:", implementation.address);

  // Deploy the proxy admin
  console.log("\n2. Deploying ProxyAdmin...");
  const ProxyAdmin = await ethers.getContractFactory("RevenueDistributionProxyAdmin");
  const proxyAdmin = await ProxyAdmin.deploy(deployer.address);
  await proxyAdmin.deployed();
  console.log("ProxyAdmin deployed to:", proxyAdmin.address);

  // Prepare initialization data
  console.log("\n3. Preparing initialization data...");
  const initData = implementation.interface.encodeFunctionData("initialize", [deployer.address]);
  console.log("Initialization data prepared");

  // Deploy the proxy
  console.log("\n4. Deploying RevenueDistributionProxy...");
  const Proxy = await ethers.getContractFactory("RevenueDistributionProxy");
  const proxy = await Proxy.deploy(implementation.address, proxyAdmin.address, initData);
  await proxy.deployed();
  console.log("RevenueDistributionProxy deployed to:", proxy.address);

  // Verify the proxy is working
  console.log("\n5. Verifying proxy setup...");
  const revenueDistribution = RevenueDistribution.attach(proxy.address);

  // Check if admin role is set correctly
  const DEFAULT_ADMIN_ROLE = await revenueDistribution.DEFAULT_ADMIN_ROLE();
  const hasAdminRole = await revenueDistribution.hasRole(DEFAULT_ADMIN_ROLE, deployer.address);
  console.log("Admin role set correctly:", hasAdminRole);

  // Check immutable values
  console.log("\n6. Checking immutable values...");
  console.log("Burn percent:", (await revenueDistribution._burnPercent()).toString());
  console.log("Treasury percent:", (await revenueDistribution._treasuryPercent()).toString());
  console.log("Staking percent:", (await revenueDistribution._stakingPercent()).toString());
  console.log("Marketing percent:", (await revenueDistribution._marketingPercent()).toString());
  console.log("Liquidity percent:", (await revenueDistribution._liquidityPercent()).toString());
  console.log("Stables ratio:", (await revenueDistribution._stablesRatio()).toString());

  console.log("\n=== Deployment Summary ===");
  console.log("Implementation address:", implementation.address);
  console.log("Proxy admin address:", proxyAdmin.address);
  console.log("Proxy address:", proxy.address);
  console.log("Admin address:", deployer.address);

  console.log("\n=== Usage Instructions ===");
  console.log("1. Use the proxy address as your main contract address");
  console.log("2. All calls to the proxy will be forwarded to the implementation");
  console.log("3. To upgrade: call upgrade() on the proxy admin with new implementation");
  console.log("4. Admin can transfer ownership of proxy admin to a multisig for security");

  return {
    implementation: implementation.address,
    proxyAdmin: proxyAdmin.address,
    proxy: proxy.address,
    admin: deployer.address,
  };
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
  .then((result) => {
    console.log("\nDeployment completed successfully!");
    process.exit(0);
  })
  .catch((error) => {
    console.error("Deployment failed:", error);
    process.exit(1);
  });
