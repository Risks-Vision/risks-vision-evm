import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

export default buildModule("RevenueDistributionModule", (m) => {
  const proxyAdminOwner = m.getAccount(0);

  const demo = m.contract("RevenueDistribution");
  const proxy = m.contract("TransparentUpgradeableProxy", [demo, proxyAdminOwner, "0x"]);

  const proxyAdminAddress = m.readEventArgument(proxy, "AdminChanged", "newAdmin");
  const proxyAdmin = m.contractAt("ProxyAdmin", proxyAdminAddress);

  return { proxyAdmin, proxy };
});
