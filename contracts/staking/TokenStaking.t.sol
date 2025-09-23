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
        rvt.approve(address(staking), type(uint256).max);

        vm.prank(user1);
        rvt.approve(address(staking), type(uint256).max);
        vm.prank(user2);
        rvt.approve(address(staking), type(uint256).max);
    }

    function test_InitialCycle() public view {
        require(staking._currentCycle() == 0, "Cycle should be 0");
        require(staking.getCurrentCycle().startTime == 0, "Cycle should not have started");

        TokenStaking.Cycle memory cycle = staking.getCurrentCycle();

        require(cycle.state == TokenStaking.CycleState.INITIAL, "Cycle should be initial");
        require(cycle.startTime == 0, "Cycle should not have started");
        require(cycle.endTime == 0, "Cycle should not have an end time");
        require(cycle.pool == 0, "Cycle should not have a pool");
        require(cycle.supply == 0, "Cycle should not have a supply");
    }

    function test_OpenInitialCycle() public {
        require(staking._currentCycle() == 0, "Cycle should be 0");

        staking.openInitialCycle(1000e18);

        TokenStaking.Cycle memory cycle = staking.getCurrentCycle();

        require(staking._currentCycle() == 1, "Cycle should be 1");
        require(cycle.state == TokenStaking.CycleState.OPEN, "Cycle should be open");
        require(cycle.startTime == 0, "Cycle should have started");
        require(cycle.endTime == 0, "Cycle should have an end time");
        require(cycle.pool == 1000e18, "Cycle should have a pool of 1000e18");
        require(cycle.supply == 0, "Cycle should have a supply of 0");
    }

    function test_InitialCycleCanOnlyBeOpenedOnce() public {
        staking.openInitialCycle(1000e18);
        vm.expectRevert(abi.encodeWithSelector(TokenStaking.InvalidCycleState.selector));
        staking.openInitialCycle(1000e18);
    }

    function test_OwnerCanNotEndAndOpenBeforeInitialCycle() public {
        vm.expectRevert(abi.encodeWithSelector(TokenStaking.InvalidCycleState.selector));
        staking.endAndOpenCycle(1000e18);
    }

    function test_OwnerCanNotEndAndOpenAfterInitialCycle() public {
        staking.openInitialCycle(1000e18);
        vm.expectRevert(abi.encodeWithSelector(TokenStaking.InvalidCycleState.selector));
        staking.endAndOpenCycle(1000e18);
    }

    function test_OwnerCanNotStartNewCycleIfCycleIsNotOpen() public {
        staking.openInitialCycle(1000e18);
        staking.startNewCycle();
        vm.expectRevert(abi.encodeWithSelector(TokenStaking.InvalidCycleState.selector));
        staking.openInitialCycle(1000e18);
    }

    function test_OwnerCanNotEndAndOpenWhenCycleIsEnded() public {
        staking.openInitialCycle(1000e18);
        staking.startNewCycle();
        vm.warp(block.timestamp + 16 days);
        staking.endAndOpenCycle(1000e18);
    }

    function test_MinimumStakeAmount() public {
        staking.openInitialCycle(1000e18);

        vm.expectRevert(abi.encodeWithSelector(TokenStaking.CannotStakeZero.selector));
        staking.stake(0);
        vm.expectRevert(abi.encodeWithSelector(TokenStaking.AmountTooSmall.selector));
        staking.stake(1e17);
    }

    function test_CanNotStakeIfCycleIsNotOpen() public {
        vm.expectRevert(abi.encodeWithSelector(TokenStaking.CycleNotOpen.selector));
        staking.stake(1000e18);
    }

    function test_CanNotStakeIfCycleIsRunning() public {
        staking.openInitialCycle(1000e18);
        staking.startNewCycle();
        vm.expectRevert(abi.encodeWithSelector(TokenStaking.CycleNotOpen.selector));
        staking.stake(1000e18);
    }

    function test_CanNotStakeIfInsufficientAllowance() public {
        staking.openInitialCycle(1000e18);
        rvt.approve(address(staking), 0);
        vm.expectRevert(abi.encodeWithSelector(TokenStaking.InsufficientAllowance.selector));
        staking.stake(1000e18);
    }

    function test_CanStake() public {
        staking.openInitialCycle(1000e18);
        vm.prank(user1);
        staking.stake(1000e18);
        require(staking.getStakes(user1).amount == 1000e18, "User1 should have a stake of 1000e18");
    }

    function test_ValidCycleRewards() public {
        staking.openInitialCycle(1000e18);

        vm.prank(user1);
        staking.stake(750e18);
        vm.prank(user2);
        staking.stake(250e18);

        require(staking.getCycleReward(user1, 1) == 750e18, "User1 should have a reward of 750e18");
        require(staking.getCycleReward(user2, 1) == 250e18, "User2 should have a reward of 250e18");
    }

    function test_newCycleRewardsOnNewCycle() public {
        staking.openInitialCycle(1000e18);

        vm.prank(user1);
        staking.stake(750e18);
        vm.prank(user2);
        staking.stake(250e18);

        staking.startNewCycle();
        require(staking.getCycleReward(user1, 1) == 750e18, "User1 should have a reward of 750e18");
        require(staking.getCycleReward(user2, 1) == 250e18, "User2 should have a reward of 250e18");

        vm.warp(block.timestamp + 16 days);

        staking.endAndOpenCycle(500e18);
        staking.startNewCycle();

        require(staking.getCycleReward(user1, 2) == 375e18, "User1 should have a reward of 375e18");
        require(staking.getCycleReward(user2, 2) == 125e18, "User2 should have a reward of 125e18");
    }

    function test_CanNotClaimCurrentCycleRewards() public {
        staking.openInitialCycle(1000e18);
        vm.prank(user1);
        staking.stake(1000e18);

        staking.startNewCycle();

        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(TokenStaking.InvalidCycle.selector));
        staking.claimCycleRewards(1);
    }

    function test_CanNotClaimRewardsIfNotStaked() public {
        staking.openInitialCycle(1000e18);
        staking.startNewCycle();

        vm.warp(block.timestamp + 16 days);

        staking.endAndOpenCycle(500e18);

        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(TokenStaking.NoStakedTokens.selector));
        staking.claimCycleRewards(1);
    }

    function test_CanClaimPreviousCycleRewards() public {
        staking.openInitialCycle(1000e18);

        vm.prank(user1);
        staking.stake(1000e18);

        staking.startNewCycle();
        vm.warp(block.timestamp + 16 days);

        staking.endAndOpenCycle(500e18);

        vm.startPrank(user1);

        uint256 balanceBefore = rvt.balanceOf(user1);
        uint256 contractBalanceBefore = rvt.balanceOf(address(staking));

        staking.claimCycleRewards(1);

        uint256 balanceAfter = rvt.balanceOf(user1);
        uint256 contractBalanceAfter = rvt.balanceOf(address(staking));

        require(contractBalanceBefore - 1000e18 == contractBalanceAfter, "Contract balance should have decreased by 1000e18");
        require(balanceBefore + 1000e18 == balanceAfter, "User1 should have received 1000e18");

        vm.stopPrank();
    }

    function test_CanNotClaimRewardsIfAlreadyClaimed() public {
        staking.openInitialCycle(1000e18);

        vm.prank(user1);
        staking.stake(1000e18);

        staking.startNewCycle();
        vm.warp(block.timestamp + 16 days);

        staking.endAndOpenCycle(500e18);

        vm.startPrank(user1);
        staking.claimCycleRewards(1);
        vm.expectRevert(abi.encodeWithSelector(TokenStaking.AlreadyClaimedThisCycle.selector));
        staking.claimCycleRewards(1);
        vm.stopPrank();
    }

    function test_SummatoryOfOldRewardsIsCorrect() public {
        staking.openInitialCycle(500e18);

        vm.prank(user1);
        staking.stake(1000e18);

        staking.startNewCycle(); 
        vm.warp(block.timestamp + 16 days);
        staking.endAndOpenCycle(500e18); 
        staking.startNewCycle(); 
        vm.warp(block.timestamp + 16 days);
        staking.endAndOpenCycle(500e18);// 2 Cycle with 500e18 rewards
        staking.startNewCycle(); 
        vm.warp(block.timestamp + 16 days);
        staking.endAndOpenCycle(500e18); // 3 Cycle with 500e18 rewards
        staking.startNewCycle(); 
        vm.warp(block.timestamp + 16 days);
        staking.endAndOpenCycle(500e18); // 4 Cycle with 500e18 rewards, this is not claimable

        console.log("staking.getTotalOldCycleRewards(user1)", staking.getTotalOldCycleRewards(user1));

        require(staking.getTotalOldCycleRewards(user1) == 2000e18, "User1 should have a total of 2000e18");
    }

    function test_CanClaimOldRewardsAndIsNotClaimableAgain() public {
        staking.openInitialCycle(500e18);

        vm.prank(user1);
        staking.stake(1000e18);

        staking.startNewCycle(); 
        vm.warp(block.timestamp + 16 days);
        staking.endAndOpenCycle(500e18); // 2 Cycle with 500e18 rewards
        staking.startNewCycle(); 
        vm.warp(block.timestamp + 16 days);
        staking.endAndOpenCycle(500e18); // 3 Cycle with 500e18 rewards
        staking.startNewCycle(); 
        vm.warp(block.timestamp + 16 days);
        staking.endAndOpenCycle(500e18); // 4 Cycle with 500e18 rewards, this is not claimable
        staking.startNewCycle(); 
        vm.warp(block.timestamp + 16 days);
        staking.endAndOpenCycle(500e18);

        vm.startPrank(user1);

        uint256 balanceBefore = rvt.balanceOf(user1);
        uint256 contractBalanceBefore = rvt.balanceOf(address(staking));

        staking.claimOldRewards();
        
        uint256 balanceAfter = rvt.balanceOf(user1);
        uint256 contractBalanceAfter = rvt.balanceOf(address(staking));

        require(balanceBefore + 2000e18 == balanceAfter, "User1 should have received 2000e18");
        require(contractBalanceBefore - 2000e18 == contractBalanceAfter, "Contract balance should have decreased by 2000e18");

        vm.expectRevert(abi.encodeWithSelector(TokenStaking.NoRewardsToClaim.selector));
        staking.claimOldRewards();
    }
}