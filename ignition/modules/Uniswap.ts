import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

export default buildModule("UniswapModule", (m) => {
  const deadline = Math.floor(Date.now() / 1000) + 3600;

  // Deploy test tokens
  const tokenA = m.contract("Token", ["TokenA", "TKA"], { id: "tokenA", from: m.getAccount(0) });
  const tokenB = m.contract("Token", ["TokenB", "TKB"], { id: "tokenB", from: m.getAccount(0) });

  // Deploy Uniswap Factory
  const factory = m.contract("UniswapV2Factory", [m.getAccount(0)]);

  // Deploy WETH (Wrapped Ether)
  const weth = m.contract("WETH9");

  // Deploy Uniswap Router
  const router = m.contract("UniswapV2Router02", [factory, weth]);

  // Create the pair (TokenA/TokenB) via the factory
  m.call(factory, "createPair", [tokenA, tokenB], { id: "createPair_TKA_TKB" });

  // Approve router to spend TokenA and TokenB (after tokens are deployed)
  const approveTKA = m.call(tokenA, "approve", [router, 1000000], { from: m.getAccount(0), id: "approve_TKA_router", after: [tokenA, router] });
  const approveTKB = m.call(tokenB, "approve", [router, 1000000], { from: m.getAccount(0), id: "approve_TKB_router", after: [tokenB, router] });

  // Get the current block timestamp using a script call
  //0xf39fd6e51aad88f6f4ce6ab8827279cfffb92266
  //0xdc64a140aa3e981100a9beca4e685f962f0cf6c9

  m.call(router, "addLiquidity", [tokenA, tokenB, 1000000, 1000000, 0, 0, m.getAccount(0), deadline], { id: "addLiquidity_TKA_TKB", from: m.getAccount(0), after: [approveTKA, approveTKB] });

  return {
    tokenA,
    tokenB,
    factory,
    weth,
    router,
  };
});
