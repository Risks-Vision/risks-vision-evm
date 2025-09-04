import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

export default buildModule("SubscriptionsModule", (m) => {
  const subscriptions = m.contract("Subscriptions");
  m.call(subscriptions, "unpause");
  m.call(subscriptions, "setPayment", [m.contract("Token")]);
  m.call(subscriptions, "createSubscription", ["1", 5000000000000000000n, 2592000n, "1"], { id: "call_1" });
  m.call(subscriptions, "createSubscription", ["2", 10000000000000000000n, 2592000n, "2"], { id: "call_2" });
  return { subscriptions };
});
