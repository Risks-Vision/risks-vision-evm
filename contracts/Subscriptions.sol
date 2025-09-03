// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";

contract Subscriptions is AccessControl, Pausable {
    // Errors 
    error SubscriptionDoesNotExist();
    error UserHasSubscription();
    error PaymentFailed();
    error NotAdmin();
    error PriceMustBeGreaterThanZero();
    error DurationMustBeGreaterThanZero();

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    struct Subscription {
        string name;
        uint256 price;
        uint256 duration;
    }

    struct UserSubscription {
        address user;
        uint256 timestamp;
        uint256 expiresAt;
        uint256 subscription;
    }

    event Subscribed(address indexed user, uint256 timestamp, Subscription subscription);

    mapping(uint256 => Subscription) public _subscriptions;
    mapping(address => UserSubscription) public _userSubscriptions;

    ERC20 public _payment;

    constructor() {
        _grantRole(ADMIN_ROLE, msg.sender);
        _pause();
    }

    function unpause() external {
        require(hasRole(ADMIN_ROLE, msg.sender), NotAdmin());
        _unpause();
    }

    function setPayment(address token) external {
        require(hasRole(ADMIN_ROLE, msg.sender), NotAdmin());
        _payment = ERC20(token);
    }

    function createSubscription(string memory name, uint256 price, uint256 duration, uint256 id) external whenNotPaused {
        require(hasRole(ADMIN_ROLE, msg.sender), NotAdmin());
        require(price > 0, PriceMustBeGreaterThanZero());
        require(duration > 0, DurationMustBeGreaterThanZero());

        Subscription memory newSub = Subscription({
            name: name,
            price: price,
            duration: duration
        });

        _subscriptions[id] = newSub;
    }

    function getSubscription(uint256 id) public view returns (Subscription memory) {
        require(subscriptionExists(id), SubscriptionDoesNotExist());
        return _subscriptions[id];
    }

    function subscriptionExists(uint256 id) public view returns (bool) {
        return _subscriptions[id].price > 0;
    }

    function userHasSubscription(address user) public view returns (bool) {
        return _userSubscriptions[user].expiresAt > block.timestamp;
    }

    function subExpiresAt(address user) public view returns (uint256) {
        return _userSubscriptions[user].expiresAt;
    }

    function subscribe(uint256 subId) external whenNotPaused {
        address user = msg.sender;

        require(subscriptionExists(subId), SubscriptionDoesNotExist());
        require(!userHasSubscription(user), UserHasSubscription());

        _userSubscriptions[user] = UserSubscription({
            user: user,
            timestamp: block.timestamp,
            expiresAt: block.timestamp + _subscriptions[subId].duration,
            subscription: subId
        });

        bool success = _payment.transferFrom(user, address(this), _subscriptions[subId].price);

        require(success, PaymentFailed());

        emit Subscribed(user, block.timestamp, _subscriptions[subId]);
    }

    function withdrawFunds(uint256 amount) external {
        require(hasRole(ADMIN_ROLE, msg.sender), NotAdmin());
        bool success = _payment.transfer(msg.sender, amount);
        require(success, PaymentFailed());
    }
}
