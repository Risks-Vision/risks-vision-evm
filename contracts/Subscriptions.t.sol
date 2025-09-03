// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Subscriptions} from "./Subscriptions.sol";
import {Test} from "forge-std/Test.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

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
        subscriptions.setPayment(address(token));
        subscriptions.unpause();
    }

    function test_HaveTokens() public view {
        require(token.balanceOf(address(this)) > 0, "Should have tokens");
    }

    function test_CreateSubscription() public {
        subscriptions.createSubscription("test subscription", 1 ether, 1 minutes, 1);

        require(subscriptions.subscriptionExists(1), "Subscription should exist");

        Subscriptions.Subscription memory subscription = subscriptions.getSubscription(1);

        require(subscription.price == 1 ether, "Subscription price should be 1 ether");
        require(subscription.duration == 1 minutes, "Subscription duration should be 1 minutes");

        subscriptions.createSubscription("test subscription", 2 ether, 2 minutes, 1);

        require(subscriptions.subscriptionExists(1), "Subscription should exist");

        subscription = subscriptions.getSubscription(1);

        require(subscription.price == 2 ether, "Subscription price should be 2 ether");
        require(subscription.duration == 2 minutes, "Subscription duration should be 2 minutes");
    }

    function test_SubscriptionExist() public view {
        require(!subscriptions.subscriptionExists(2), "Subscription should not exist");
    }

    function test_UserDoesNotHaveSubscription() public view {
        require(!subscriptions.userHasSubscription(address(this)), "User should not have subscription");
    }

    function test_UserHasSubscription() public {
        uint256 beforeBalance = token.balanceOf(address(this));
        require(beforeBalance >= 1 ether, "Balance should be greater than 1 ether");

        subscriptions.createSubscription("test subscription", 1 ether, 1 minutes, 1);
        token.approve(address(subscriptions), 1 ether);
        subscriptions.subscribe(1);

        require(subscriptions.userHasSubscription(address(this)), "User should have subscription");
        require(token.allowance(address(this), address(subscriptions)) == 0, "Allowance should be 0");
        require(token.balanceOf(address(this)) == beforeBalance - 1 ether, "Balance should be before balance - 1 ether");

        // Try to subscribe again
        beforeBalance = token.balanceOf(address(this));
        token.approve(address(subscriptions), 1 ether);

        vm.expectRevert(Subscriptions.UserHasSubscription.selector);

        // Because it already have subscription, it should revert
        subscriptions.subscribe(1);
    }

    function test_SubscriptionDuration() public {
        subscriptions.createSubscription("test subscription", 1 ether, 1 minutes, 1);
        token.approve(address(subscriptions), 1 ether);
        subscriptions.subscribe(1);

        require(subscriptions.userHasSubscription(address(this)), "User should have subscription");
        require(subscriptions.subExpiresAt(address(this)) == block.timestamp + 1 minutes, "Expires at should be 1 minutes");
       
        vm.warp(block.timestamp + 2 minutes);
       
        require(subscriptions.userHasSubscription(address(this)) == false, "User should not have subscription");

        token.approve(address(subscriptions), 1 ether);
        subscriptions.subscribe(1);

        require(subscriptions.userHasSubscription(address(this)), "User should have subscription");

        vm.expectRevert(Subscriptions.UserHasSubscription.selector);
        subscriptions.subscribe(1);
    }

    function test_OnlyAdminCanCreateSubscription() public {
        vm.prank(address(1));
        vm.expectRevert(Subscriptions.NotAdmin.selector);
        subscriptions.createSubscription("test subscription", 1 ether, 1 minutes, 1);
    }

    function test_OnlyAdminCanWithdrawFunds() public {
        vm.prank(address(1));
        vm.expectRevert(Subscriptions.NotAdmin.selector);
        subscriptions.withdrawFunds(1 ether);
    }
}
