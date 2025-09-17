import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

export default buildModule("SubscriptionsModule", (m) => {
  const subscriptions = m.contract("Subscriptions");
  const token = m.contract("Token");
  m.call(subscriptions, "unpause");
  m.call(subscriptions, "createSubscription", ["1", 60n, "1"], { id: "call_1" });
  m.call(subscriptions, "createSubscription", ["2", 60n, "2"], { id: "call_2" });
  m.call(subscriptions, "editPayment", [1n, token, 1000000000000000000n], { id: "call_3" });
  m.call(subscriptions, "editPayment", [2n, token, 1000000000000000000n], { id: "call_4" });
  return { subscriptions };
});
