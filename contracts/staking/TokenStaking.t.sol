// test/RVTStakingByCycle.t.sol
pragma solidity ^0.8.30;

import {console} from "forge-std/console.sol";
import "forge-std/Test.sol";
import "./TokenStaking.sol";
import "../token/Token.sol";

contract TokenStakingTest is Test {
    TokenStaking staking;
    Token rvt;
    address user1 = address(0x123);
    address user2 = address(0x456);

    function setUp() public {
        rvt = new Token("Risks Vision", "RVT");
        staking = new TokenStaking(address(rvt));

        rvt.mintTo(user1, 10000e18);
        rvt.mintTo(user2, 10000e18);

        vm.prank(user1);
        rvt.approve(address(staking), type(uint256).max);
        vm.prank(user2);
        rvt.approve(address(staking), type(uint256).max);
    }

    function testRolloverAndRewards() public {
        rvt.mintTo(address(staking), 1000e18);
        staking.startNewCycle(1000e18);

        // Cycle 1: User1 stakes 50% from start, User2 stakes 50% mid-cycle
        vm.prank(user1);
        staking.stake(5000e18);
        vm.warp(block.timestamp + 15 days);
        vm.prank(user2);
        staking.stake(5000e18);
        vm.warp(block.timestamp + 15 days); // End cycle
        vm.prank(staking.owner());

        // Check rewards for Cycle 1
        uint256 user1Rewards = staking.earned(user1);
        uint256 user2Rewards = staking.earned(user2);
        console.log("user1Rewards after cycle 1", user1Rewards);
        console.log("user2Rewards after cycle 1", user2Rewards);
        assertGt(user1Rewards, user2Rewards); // User1 earns more due to longer duration

        // Cycle 2: Stakes persist, check rollover
        // assertEq(staking.getStakes(user1).amount, 5000e18);
        // assertEq(staking.getStakes(user2).amount, 5000e18);
        // skip(30 days); // End Cycle 2

        // vm.prank(staking.owner());
        // staking.startNewCycle(1000e18); // Cycle 3 starts

        // // Both users earn equal rewards in Cycle 2 (full duration, equal stakes)
        // vm.prank(user1);
        // staking.claimRewards();
        // vm.prank(user2);
        // staking.claimRewards();
        // assertApproxEqAbs(staking.earned(user1), staking.earned(user2), 1e10);
    }
}