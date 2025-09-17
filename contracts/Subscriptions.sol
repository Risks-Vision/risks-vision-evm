// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title Subscriptions Contract
/// @notice Manages subscription plans with flexible token pricing, admin controls, and pause functionality
/// @dev Uses OpenZeppelin for access control, pausability, and safe ERC20 interactions
contract Subscriptions is AccessControl, Pausable, ReentrancyGuard {
    // Errors 
    error SubscriptionDoesNotExist();
    error UserHasSubscription();
    error PaymentFailed();
    error NotAdmin();
    error DurationMustBeGreaterThanZero();
    error PaymentNotAvailable();
    error NotApproved();
    error TokenCannotBeZeroAddress();
    error InvalidSubscriptionId();

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    /// @notice Subscription struct containing name and duration
    struct Subscription {
        string name;
        uint256 duration; // In seconds
    }

    /// @notice User subscription details
    struct UserSubscription {
        address user;
        uint256 timestamp; // In seconds
        uint256 expiresAt; // In seconds
        uint256 subscription;
    }

    /// @notice Events emitted
    event SubscriptionCreated(uint256 indexed id, Subscription subscription);
    event Subscribed(address indexed user, address token, uint256 price, uint256 timestamp, Subscription subscription);
    event SubscriptionRenewed(address indexed user, address token, uint256 price, uint256 newExpiresAt, Subscription subscription);

    mapping(uint256 => Subscription) public _subscriptions;
    mapping(address => UserSubscription) public _userSubscriptions;
    mapping(uint256 => mapping(address => uint256)) public _subscriptionPrices; // subId => token => price

    constructor() {
        _grantRole(ADMIN_ROLE, msg.sender);
        _pause();
    }

    /// @notice Unpauses the contract, enabling subscriptions
    function unpause() external {
        if (!hasRole(ADMIN_ROLE, msg.sender)) revert NotAdmin();
        _unpause();
    }

    /// @notice Sets the price for a subscription in a specific token
    /// @param subId Subscription ID
    /// @param token ERC20 token address
    /// @param price Price in token units (considering token decimals)
    function editPayment(uint256 subId, address token, uint256 price) external {
        if(!hasRole(ADMIN_ROLE, msg.sender)) revert NotAdmin();
        if(!subscriptionExists(subId)) revert SubscriptionDoesNotExist();
        if(token == address(0)) revert TokenCannotBeZeroAddress();

        _subscriptionPrices[subId][token] = price;
    }
    
    /// @notice Checks if a token is accepted for a subscription
    /// @param subId Subscription ID
    /// @param token ERC20 token address
    /// @return True if the token has a non-zero price
    function isAvailablePayment(uint256 subId, address token) public view returns (bool) {
        return _subscriptionPrices[subId][token] > 0;
    }

    /// @notice Creates a new subscription plan
    /// @param name Name of the subscription (max 32 bytes)
    /// @param duration Duration in seconds
    /// @param id Unique subscription ID
    function createSubscription(string memory name, uint256 duration, uint256 id) external whenNotPaused {
        if (!hasRole(ADMIN_ROLE, msg.sender)) revert NotAdmin();
        if (duration == 0) revert DurationMustBeGreaterThanZero();

        Subscription memory newSub = Subscription({
            name: name,
            duration: duration
        });

        _subscriptions[id] = newSub;
    }

    /// @notice Gets a subscription's details
    /// @param id Subscription ID
    /// @return Subscription struct
    function getSubscription(uint256 id) public view returns (Subscription memory) {
        if (!subscriptionExists(id)) revert SubscriptionDoesNotExist();
        return _subscriptions[id];
    }

    /// @notice Gets the price of a subscription in a specific token
    /// @param subId Subscription ID
    /// @param token ERC20 token address
    /// @return Price in token units
    function getSubscriptionPrice(uint256 subId, address token) public view returns (uint256) {
        if (!subscriptionExists(subId)) revert SubscriptionDoesNotExist();
        return _subscriptionPrices[subId][token];
    }

    /// @notice Checks if a subscription exists
    /// @param id Subscription ID
    /// @return True if the subscription exists
    function subscriptionExists(uint256 id) public view returns (bool) {
        return _subscriptions[id].duration > 0;
    }

    /// @notice Checks if a user has an active subscription
    /// @param user User address
    /// @return True if the subscription is active
    function userHasSubscription(address user) public view returns (bool) {
        return _userSubscriptions[user].expiresAt >= block.timestamp;
    }

    /// @notice Gets the expiration timestamp of a user's subscription
    /// @param user User address
    /// @return Expiration timestam
    function subExpiresAt(address user) public view returns (uint256) {
        return _userSubscriptions[user].expiresAt;
    }

    /// @notice Subscribes a user to a plan
    /// @param subId Subscription ID
    /// @param token ERC20 token address
    function subscribe(uint256 subId, address token) external whenNotPaused nonReentrant {
        address user = msg.sender;

        if (token == address(0)) revert TokenCannotBeZeroAddress();
        if (!subscriptionExists(subId)) revert SubscriptionDoesNotExist();
        if (userHasSubscription(user)) revert UserHasSubscription();

        uint256 price = _subscriptionPrices[subId][token];

        if (price == 0) revert PaymentNotAvailable();

        Subscription memory sub = _subscriptions[subId];

        _userSubscriptions[user] = UserSubscription({
            user: user,
            timestamp: block.timestamp,
            expiresAt: block.timestamp + sub.duration,
            subscription: subId
        });

        IERC20 _token = IERC20(token);

        if (_token.allowance(user, address(this)) < price) revert NotApproved();
        if (!_token.transferFrom(user, address(this), price)) revert PaymentFailed();

        emit Subscribed(user, token, price, block.timestamp, sub);
    }

    /// @notice Renews a user's subscription
    /// @param subId Subscription ID
    /// @param token ERC20 token address
    function renewSubscription(uint256 subId, address token) external whenNotPaused nonReentrant {
        address user = msg.sender;

        if (token == address(0)) revert TokenCannotBeZeroAddress();
        if (!subscriptionExists(subId)) revert SubscriptionDoesNotExist();
        if (_userSubscriptions[user].user != user) revert SubscriptionDoesNotExist(); // Must have subscribed before
        if (_userSubscriptions[user].subscription != subId) revert InvalidSubscriptionId();

        uint256 price = _subscriptionPrices[subId][token];

        if (price == 0) revert PaymentNotAvailable();

        Subscription memory sub = _subscriptions[subId];
        UserSubscription storage userSub = _userSubscriptions[user];

        userSub.expiresAt = userHasSubscription(user) ? userSub.expiresAt + sub.duration : block.timestamp + sub.duration;
        userSub.timestamp = block.timestamp;

        IERC20 _token = IERC20(token);

        if (_token.allowance(user, address(this)) < price) revert NotApproved();
        if (!_token.transferFrom(user, address(this), price)) revert PaymentFailed();

        emit SubscriptionRenewed(user, token, price, userSub.expiresAt, sub);
    }

    /// @notice Withdraws funds from the contract
    /// @param token ERC20 token address
    function withdrawFunds(address token) external whenNotPaused {
        if (!hasRole(ADMIN_ROLE, msg.sender)) revert NotAdmin();
        if (!IERC20(token).transfer(msg.sender, IERC20(token).balanceOf(address(this)))) revert PaymentFailed();
    }
}
