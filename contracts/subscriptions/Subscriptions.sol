// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;


import {ISubscriptions} from "./ISubscriptions.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title Subscriptions Contract
/// @notice Manages subscription plans with flexible token pricing, admin controls, and pause functionality
/// @dev Uses OpenZeppelin for access control, pausability, and safe ERC20 interactions
contract Subscriptions is ISubscriptions {
    /**
     * @dev Initializes the Subscriptions contract
     * Grants admin role to the deployer and pauses the contract initially
     */
    constructor() {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _pause();
    }

    /**
     * @dev Unpauses the contract, enabling subscription operations
     * @notice Only admin can call this function
     */
    function unpause() external override {
        if (!hasRole(DEFAULT_ADMIN_ROLE, msg.sender)) revert NotAdmin();
        _unpause();
    }

    /**
     * @dev Sets or updates the price for a subscription in a specific token
     * @param subId Subscription ID to set the price for
     * @param token ERC20 token address for the payment
     * @param price Price in token units (considering token decimals)
     * @notice Only admin can call this function
     * @notice The subscription must exist before setting a price
     */
    function editPayment(uint256 subId, address token, uint256 price) external override {
        if(!hasRole(DEFAULT_ADMIN_ROLE, msg.sender)) revert NotAdmin();
        if(!subscriptionExists(subId)) revert SubscriptionDoesNotExist();
        if(token == address(0)) revert TokenCannotBeZeroAddress();

        _subscriptionPrices[subId][token] = price;
    }
    
    /**
     * @dev Checks if a specific token is accepted as payment for a subscription
     * @param subId Subscription ID to check
     * @param token ERC20 token address to verify
     * @return True if the token has a non-zero price set for this subscription
     */
    function isAvailablePayment(uint256 subId, address token) public view override returns (bool) {
        return _subscriptionPrices[subId][token] > 0;
    }

    /**
     * @dev Creates a new subscription plan with specified parameters
     * @param name Name of the subscription (max 32 bytes)
     * @param duration Duration in seconds for the subscription
     * @param id Unique subscription ID to identify this plan
     * @notice Only admin can call this function
     * @notice Contract must not be paused
     * @notice Duration must be greater than zero
     */
    function createSubscription(string memory name, uint256 duration, uint256 id) external whenNotPaused override {
        if (!hasRole(DEFAULT_ADMIN_ROLE, msg.sender)) revert NotAdmin();
        if (duration == 0) revert DurationMustBeGreaterThanZero();

        Subscription memory newSub = Subscription({
            name: name,
            duration: duration
        });

        _subscriptions[id] = newSub;
    }

    /**
     * @dev Retrieves the details of a specific subscription plan
     * @param id Subscription ID to retrieve
     * @return Subscription struct containing name and duration
     * @notice Reverts if the subscription does not exist
     */
    function getSubscription(uint256 id) public view override returns (Subscription memory) {
        if (!subscriptionExists(id)) revert SubscriptionDoesNotExist();
        return _subscriptions[id];
    }

    /**
     * @dev Gets the price of a subscription in a specific token
     * @param subId Subscription ID to get the price for
     * @param token ERC20 token address to get the price in
     * @return Price in token units (considering token decimals)
     * @notice Reverts if the subscription does not exist
     */
    function getSubscriptionPrice(uint256 subId, address token) public view override returns (uint256) {
        if (!subscriptionExists(subId)) revert SubscriptionDoesNotExist();
        return _subscriptionPrices[subId][token];
    }

    /**
     * @dev Checks if a subscription plan exists
     * @param id Subscription ID to check
     * @return True if the subscription exists (duration > 0)
     */
    function subscriptionExists(uint256 id) public view override returns (bool) {
        return _subscriptions[id].duration > 0;
    }

    /**
     * @dev Checks if a user has an active (non-expired) subscription
     * @param user User address to check
     * @return True if the user's subscription is still active (not expired)
     */
    function userHasSubscription(address user) public view override returns (bool) {
        return _userSubscriptions[user].expiresAt >= block.timestamp;
    }

    /**
     * @dev Gets the expiration timestamp of a user's subscription
     * @param user User address to check
     * @return Expiration timestamp (Unix timestamp)
     */
    function subExpiresAt(address user) public view override returns (uint256) {
        return _userSubscriptions[user].expiresAt;
    }

    /**
     * @dev Subscribes a user to a subscription plan
     * @param subId Subscription ID to subscribe to
     * @param token ERC20 token address to pay with
     * @notice Contract must not be paused
     * @notice User must not already have an active subscription
     * @notice Token must be a valid payment method for this subscription
     * @notice User must have approved sufficient token allowance
     * @notice Emits Subscribed event upon successful subscription
     */
    function subscribe(uint256 subId, address token) external whenNotPaused nonReentrant override {
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

    /**
     * @dev Renews a user's existing subscription
     * @param subId Subscription ID to renew (must match user's current subscription)
     * @param token ERC20 token address to pay with
     * @notice Contract must not be paused
     * @notice User must have previously subscribed to this subscription ID
     * @notice Token must be a valid payment method for this subscription
     * @notice User must have approved sufficient token allowance
     * @notice If subscription is still active, duration is added to current expiration
     * @notice If subscription is expired, new expiration is set from current time
     * @notice Emits SubscriptionRenewed event upon successful renewal
     */
    function renewSubscription(uint256 subId, address token) external whenNotPaused nonReentrant override {
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

    /**
     * @dev Withdraws all funds of a specific token from the contract
     * @param token ERC20 token address to withdraw
     * @return True if the withdrawal was successful
     * @notice Contract must not be paused
     * @notice Only admin or revenue distribution contract can call this function
     * @notice Withdraws the entire balance of the specified token
     */
    function withdrawFunds(address token) external whenNotPaused nonReentrant override returns (bool) {
        if (token == address(0)) revert TokenCannotBeZeroAddress();
        if (!hasRole(DEFAULT_ADMIN_ROLE, msg.sender) && !hasRole(REVENUE_DISTRIBUTION_ROLE, msg.sender)) revert NotAdmin();
        if (!IERC20(token).transfer(msg.sender, IERC20(token).balanceOf(address(this)))) revert PaymentFailed();
        return true;
    }
}
