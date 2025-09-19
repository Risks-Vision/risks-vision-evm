// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Subscriptions} from "./Subscriptions.sol";
import {ISubscriptions} from "./ISubscriptions.sol";
import {Test} from "forge-std/Test.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {console} from "forge-std/console.sol";

contract ERC20Mock is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {
        _mint(msg.sender, 10 ether);
    }
}

contract SubscriptionsTest is Test {
    Subscriptions subscriptions;
    ERC20 token;

    function setUp() public {
        token = new ERC20Mock("Test Token", "TEST");
        subscriptions = new Subscriptions();
        subscriptions.unpause();
        subscriptions.createSubscription("setup test subscription", 1 minutes, 1);
        subscriptions.editPayment(1, address(token), 1 ether);
    }

    function test_HaveTokens() public view {
        require(token.balanceOf(address(this)) > 0, "Should have tokens");
    }

    function test_CreateSubscription() public {
        subscriptions.createSubscription("test subscription", 1 minutes, 2);
        subscriptions.editPayment(2, address(token), 1 ether);
        require(subscriptions.subscriptionExists(2), "Subscription should exist");
        require(subscriptions.getSubscriptionPrice(2, address(token)) == 1 ether, "Subscription price should be 1 ether");
        require(subscriptions.getSubscription(2).duration == 1 minutes, "Subscription duration should be 1 minutes");
    }

    function test_UserDoesNotHaveSubscription() public view {
        require(!subscriptions.userHasSubscription(address(this)), "User should not have subscription");
    }

    function test_UserCanSubscribe() public {
        uint256 beforeBalance = token.balanceOf(address(this));

        require(beforeBalance >= 1 ether, "Balance should be greater than 1 ether");

        token.approve(address(subscriptions), 1 ether);
        subscriptions.subscribe(1, address(token));

        require(subscriptions.userHasSubscription(address(this)), "User should have subscription");
        require(token.allowance(address(this), address(subscriptions)) == 0, "Allowance should be 0");
        require(token.balanceOf(address(this)) == beforeBalance - 1 ether, "Balance should be before balance - 1 ether");
    }

    function test_UserCantResubscribe() public {
        token.approve(address(subscriptions), 1 ether);
        subscriptions.subscribe(1, address(token));
        require(subscriptions.userHasSubscription(address(this)), "User should have subscription");

        vm.expectRevert(ISubscriptions.UserHasSubscription.selector);
        subscriptions.subscribe(1, address(token));
    }

    function test_SubscriptionDuration() public {
        token.approve(address(subscriptions), 1 ether);
        subscriptions.subscribe(1, address(token));

        require(subscriptions.userHasSubscription(address(this)), "User should have subscription");
        require(subscriptions.subExpiresAt(address(this)) == block.timestamp + 1 minutes, "Expires at should be 1 minutes");
       
        vm.warp(block.timestamp + 2 minutes);
       
        require(subscriptions.userHasSubscription(address(this)) == false, "User should not have subscription");
    }

    function test_UserCanRenewSubscription() public {
        token.approve(address(subscriptions), 2 ether);
        subscriptions.subscribe(1, address(token));
        require(subscriptions.userHasSubscription(address(this)), "User should have subscription");
        vm.warp(block.timestamp + 2 minutes);
        require(subscriptions.userHasSubscription(address(this)) == false, "User should not have subscription");
        subscriptions.renewSubscription(1, address(token));
        require(subscriptions.userHasSubscription(address(this)), "User should have subscription final");
    }

    function test_UserCanExtendSubscription() public {
        token.approve(address(subscriptions), 3 ether);
        subscriptions.subscribe(1, address(token));
        require(subscriptions.userHasSubscription(address(this)), "User should have subscription");
        subscriptions.renewSubscription(1, address(token));
        subscriptions.renewSubscription(1, address(token));
    }

    function test_OnlyAdminCanCreateSubscription() public {
        vm.prank(address(1));
        vm.expectRevert(ISubscriptions.NotAdmin.selector);
        subscriptions.createSubscription("test subscription", 1 minutes, 1);
    }

    function test_OnlyAdminCanWithdrawFunds() public {
        vm.prank(address(1));
        vm.expectRevert(ISubscriptions.NotAdmin.selector);
        subscriptions.withdrawFunds(address(token));
    }

    function test_OnlyAdminCanEditPayment() public {
        vm.prank(address(1));
        vm.expectRevert(ISubscriptions.NotAdmin.selector);
        subscriptions.editPayment(1, address(token), 1 ether);
    }

    function test_AdminCanEditPayment() public {
        subscriptions.editPayment(1, address(token), 1 ether);
        require(subscriptions.isAvailablePayment(1, address(token)), "Payment should be available");
    }
}
