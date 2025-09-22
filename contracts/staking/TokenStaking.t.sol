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

        rvt.mintTo(user1, 1000000e18);
        rvt.mintTo(user2, 1000000e18);

        vm.prank(user1);
        rvt.approve(address(staking), type(uint256).max);
        vm.prank(user2);
        rvt.approve(address(staking), type(uint256).max);
    }

    function test_InitialCycle() public view {
        require(staking._currentCycle() == 0, "Cycle should be 0");
        require(staking.getCurrentCycle().startTime == 0, "Cycle should not have started");
        require(staking.currentIsOpen() == false, "Cycle should not be open");
    }

    function test_InitialCycleOpening() public {
        require(staking._currentCycle() == 0, "Cycle should be 0");

        rvt.mintTo(address(staking), 1000e18);
        staking.closeAndOpenCycle(1000e18);

        require(staking._currentCycle() == 1, "Cycle should be 1");
        require(staking.currentIsOpen() == true, "Cycle should be open");
        require(staking.getCurrentCycle().startTime == 0, "Cycle should have started");
        require(staking.getCurrentCycle().endTime == 0, "Cycle should have an end time");
        require(staking.getCurrentCycle().pool == 1000e18, "Cycle should have a pool of 1000e18");
        require(staking.getCurrentCycle().supply == 0, "Cycle should have a supply of 0");

        // Try to open it again, this must be reverted
        vm.expectRevert(abi.encodeWithSelector(TokenStaking.CycleAlreadyOpened.selector));
        staking.closeAndOpenCycle(1000e18);
    }

    function test_StartNewCycleWithStakers() public {
        rvt.mintTo(address(staking), 1000e18);
        staking.closeAndOpenCycle(1000e18);

        require(staking.currentIsOpen() == true, "Cycle should be opened");

        vm.prank(user1);
        staking.stake(5000e18);
        vm.prank(user2);
        staking.stake(5000e18);

        TokenStaking.Cycle memory cycle = staking.getCurrentCycle();

        require(cycle.supply == 5000e18 + 5000e18, "Cycle should have a supply of 10000e18");
        require(cycle.pool == 1000e18, "Cycle should have a pool of 1000e18");

        staking.startNewCycle();

        cycle = staking.getCurrentCycle();

        require(cycle.startTime == block.timestamp, "Cycle should have a start time");
        require(cycle.endTime == block.timestamp + 15 days, "Cycle should have a end time (15 days)");
    }

    function test_StakersStakingAndWithdrawInOpenedCycle() public {
        rvt.mintTo(address(staking), 1000e18);
        staking.closeAndOpenCycle(1000e18);

        require(staking.currentIsOpen() == true, "Cycle should be opened");

        vm.prank(user1);
        staking.stake(5000e18);
        vm.prank(user2);
        staking.stake(5000e18);

        require(staking.getStakeAmount(user1) == 5000e18, "User1 should have a stake of 5000e18");
        require(staking.getStakeAmount(user2) == 5000e18, "User2 should have a stake of 5000e18");
        require(staking.getStakeProportion(user1, 1) == 0.5 ether, "User1 should have a stake proportion of 50%");
        require(staking.getStakeProportion(user2, 1) == 0.5 ether, "User2 should have a stake proportion of 50%");
        require(staking.getCycleReward(user1, 1) == 500e18, "User1 should have a reward of 500e18");
        require(staking.getCycleReward(user2, 1) == 500e18, "User2 should have a reward of 500e18");

        // Try to stake again, this must be reverted
        vm.prank(user1);
        staking.stake(10000e18);

        require(staking.getCurrentCycle().supply == 5000e18 + 5000e18 + 10000e18, "Cycle should have a supply of 20000e18");
        require(staking.getStakeAmount(user1) == 15000e18, "User1 should have a stake of 15000e18");
        require(staking.getStakeAmount(user2) == 5000e18, "User2 should have a stake of 5000e18");
        require(staking.getStakeProportion(user1, 1) == 0.75 ether, "User1 should have a stake proportion of 75%");
        require(staking.getCycleReward(user1, 1) == 750e18, "User1 should have a reward of 750e18");

        vm.prank(user2);
        staking.withdraw();

        require(staking.getCurrentCycle().supply == 5000e18 + 10000e18, "Cycle should have a supply of 15000e18");
        require(staking.getStakeAmount(user1) == 15000e18, "User1 should have a stake of 15000e18");
        require(staking.getStakeAmount(user2) == 0, "User2 should have a stake of 0");
        require(staking.getStakeProportion(user1, 1) == 1 ether, "User1 should have a stake proportion of 100%");
        require(staking.getCycleReward(user1, 1) == 1000e18, "User1 should have a reward of 1000e18");

        vm.prank(user2);
        staking.stake(5000e18);

        require(staking.getCurrentCycle().supply == 5000e18 + 5000e18 + 10000e18, "Cycle should have a supply of 20000e18");
        require(staking.getStakeAmount(user1) == 15000e18, "User1 should have a stake of 15000e18");
        require(staking.getStakeAmount(user2) == 5000e18, "User2 should have a stake of 5000e18");
        require(staking.getStakeProportion(user1, 1) == 0.75 ether, "User1 should have a stake proportion of 75%");
        require(staking.getStakeProportion(user2, 1) == 0.25 ether, "User2 should have a stake proportion of 25%");
        require(staking.getCycleReward(user1, 1) == 750e18, "User1 should have a reward of 750e18");
        require(staking.getCycleReward(user2, 1) == 250e18, "User2 should have a reward of 250e18");
    }

    function test_StakersStakingAndWithdrawInClosedCycle() public {
        rvt.mintTo(address(staking), 1000e18);
        staking.closeAndOpenCycle(1000e18);

        require(staking.currentIsOpen() == true, "Cycle should be opened");

        vm.prank(user1);
        staking.stake(5000e18);
        vm.prank(user2);
        staking.stake(5000e18);

        staking.startNewCycle();

        require(staking.currentIsStarted() == true, "Cycle should have started");

        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(TokenStaking.CycleNotOpen.selector));
        staking.withdraw();

        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(TokenStaking.CycleNotOpen.selector));
        staking.stake(5000e18);

        vm.warp(block.timestamp + 10 days);

        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(TokenStaking.CycleNotOpen.selector));
        staking.withdraw();

        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(TokenStaking.CycleNotOpen.selector));
        staking.stake(5000e18);
    }

    function test_StakersClaimRewards() public {
        rvt.mintTo(address(staking), 1000e18);
        staking.closeAndOpenCycle(1000e18);

        require(staking.currentIsOpen() == true, "Cycle should be opened");
        
        vm.prank(user1);
        staking.stake(5000e18);
        vm.prank(user2);
        staking.stake(5000e18);

        staking.startNewCycle();

        require(staking.currentIsStarted() == true, "Cycle should have started");
        require(staking.getCycleReward(user1, 1) == 500e18, "User1 should have a reward of 500e18");

        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(TokenStaking.IsCurrentCycle.selector));
        staking.claimCycleRewards(1);

        vm.warp(block.timestamp + 16 days);

        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(TokenStaking.IsCurrentCycle.selector));
        staking.claimCycleRewards(1);

        staking.closeAndOpenCycle(1000e18);

        require(staking._currentCycle() == 2, "Cycle should be 2");
        require(staking.getCycleReward(user1, 1) == 500e18, "User1 should have a reward of 500e18");

        uint256 balanceBefore = rvt.balanceOf(user1);

        vm.prank(user1);
        staking.claimCycleRewards(1);

        uint256 balanceAfter = rvt.balanceOf(user1);

        require(balanceBefore + 500e18 == balanceAfter, "User1 should have received 500e18");
        require(staking.getCycleReward(user1, 1) == 0, "User1 should have a reward of 0");

        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(TokenStaking.AlreadyClaimedThisCycle.selector));
        staking.claimCycleRewards(1);
    }

    function test_OwnerCanNotOpenCycleIfNotEnded() public {
        rvt.mintTo(address(staking), 1000e18);
        staking.closeAndOpenCycle(1000e18);

        require(staking.currentIsOpen() == true, "Cycle should be opened");

        vm.prank(staking.owner());
        staking.startNewCycle();

        require(staking.currentIsOpen() == false, "Cycle should be closed");
        require(staking.currentIsStarted() == true, "Cycle should have started");

        vm.expectRevert(abi.encodeWithSelector(TokenStaking.CycleNotEnded.selector));
        staking.closeAndOpenCycle(1000e18);

        vm.warp(block.timestamp + 16 days);
        vm.prank(staking.owner());
        staking.closeAndOpenCycle(1000e18);

        console.log("staking.currentIsOpen()", staking.currentIsOpen());
        console.log("staking.currentIsStarted()", staking.currentIsStarted());

        require(staking.currentIsOpen() == true, "Cycle should be opened");
    }


    function testRolloverAndRewards() public {
        // rvt.mintTo(address(staking), 1000e18);
        // staking.startNewCycle();

        // Cycle 1: User1 stakes 50% from start, User2 stakes 50% mid-cycle
        // vm.prank(user1);
        // staking.stake(5000e18);
        // vm.warp(block.timestamp + 15 days);
        // vm.prank(user2);
        // staking.stake(5000e18);
        // vm.warp(block.timestamp + 15 days); // End cycle
        // vm.prank(staking.owner());

        // // Check rewards for Cycle 1
        // uint256 user1Rewards = staking.earned(user1);
        // uint256 user2Rewards = staking.earned(user2);
        // console.log("user1Rewards after cycle 1", user1Rewards);
        // console.log("user2Rewards after cycle 1", user2Rewards);
        // assertGt(user1Rewards, user2Rewards); // User1 earns more due to longer duration

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