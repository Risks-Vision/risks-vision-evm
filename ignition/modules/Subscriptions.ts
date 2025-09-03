import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

export default buildModule("SubscriptionsModule", (m) => {
  const subscriptions = m.contract("Subscriptions");
  m.call(subscriptions, "unpause");
  m.call(subscriptions, "setPayment", [m.contract("Token")]);
  return { subscriptions };
});
