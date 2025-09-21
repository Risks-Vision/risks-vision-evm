import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

import DemoModule from "./RevenueDistribution.js";

const upgradeModule = buildModule("UpgradeModule", (m) => {
  const proxyAdminOwner = m.getAccount(0);

  const { proxyAdmin, proxy } = m.useModule(DemoModule);

  const demoV2 = m.contract("DemoV2");

  const encodedFunctionCall = m.encodeFunctionCall(demoV2, "setName", ["Example Name"]);

  m.call(proxyAdmin, "upgradeAndCall", [proxy, demoV2, encodedFunctionCall], {
    from: proxyAdminOwner,
  });

  return { proxyAdmin, proxy };
});
