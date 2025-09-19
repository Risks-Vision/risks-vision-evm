// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title ISubscriptions Interface
/// @notice Abstract contract defining the interface for subscription management systems
/// @dev This interface provides a standard for subscription contracts with flexible token pricing
abstract contract ISubscriptions {
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

    // Events
    event SubscriptionCreated(uint256 indexed id, Subscription subscription);
    event Subscribed(address indexed user, address token, uint256 price, uint256 timestamp, Subscription subscription);
    event SubscriptionRenewed(address indexed user, address token, uint256 price, uint256 newExpiresAt, Subscription subscription);

    // Public mappings and state variables
    mapping(uint256 => Subscription) public _subscriptions;
    mapping(address => UserSubscription) public _userSubscriptions;
    mapping(uint256 => mapping(address => uint256)) public _subscriptionPrices; // subId => token => price

    // Role constants
    bytes32 public immutable REVENUE_DISTRIBUTION_ROLE = keccak256("REVENUE_DISTRIBUTION_ROLE");

    // Admin functions
    function unpause() external virtual;
    function editPayment(uint256 subId, address token, uint256 price) external virtual;
    function createSubscription(string memory name, uint256 duration, uint256 id) external virtual;
    function withdrawFunds(address token) external virtual returns (bool);

    // View functions
    function isAvailablePayment(uint256 subId, address token) external view virtual returns (bool);
    function getSubscription(uint256 id) external view virtual returns (Subscription memory);
    function getSubscriptionPrice(uint256 subId, address token) external view virtual returns (uint256);
    function subscriptionExists(uint256 id) external view virtual returns (bool);
    function userHasSubscription(address user) external view virtual returns (bool);
    function subExpiresAt(address user) external view virtual returns (uint256);

    // User functions
    function subscribe(uint256 subId, address token) external virtual;
    function renewSubscription(uint256 subId, address token) external virtual;
}
