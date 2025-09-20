// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {ISubscriptions} from "../subscriptions/ISubscriptions.sol";
import {IUniswapRouter} from "../interfaces/IUniswapRouter.sol";
import {IERC20Burnable} from "../token/IERC20Burnable.sol";

/// @title IRevenueDistribution
/// @notice Abstract contract defining the interface for revenue distribution functionality
/// @dev This abstract contract provides the structure for managing revenue distribution from subscriptions
abstract contract IRevenueDistribution is AccessControl, Pausable, ReentrancyGuard {
    // Custom errors
    error NotAdmin();
    error TokenCannotBeZeroAddress();
    error InvalidToken();
    error InvalidAmount();
    error PaymentFailed();
    error InvalidFundsWithdrawn();
    error RouterAddressNotSet();
    error USDTAddressNotSet();
    error SwapFailed();
    error PairNotFound();
    error ZeroReserves();
    error InvalidReserves();
    error InsufficientLiquidityAdded();
    error InsufficientBalance();
    error ApprovalFailed();
    error InvalidRatio();
    error SubscriptionsAddressNotSet();

    // Structs
    struct USDTDistribution {
        uint256 marketing;
        uint256 liquidity;
        uint256 buyback;
    }

    struct ProjectTokenDistribution {
        uint256 staking;
        uint256 burn;
        uint256 treasury;
    }

    // Immutable state variables
    uint256 public immutable _burnPercent = 40; // This amount will be burned forever
    uint256 public immutable _treasuryPercent = 20; // The treasury tokens will be sent to an address
    uint256 public immutable _stakingPercent = 40; // This will be sent to the staking pools
    uint256 public immutable _marketingPercent = 50; // This will be sent to the marketing address
    uint256 public immutable _liquidityPercent = 50; // This will be locked on the liquidity pool
    uint256 public immutable _stablesRatio = 50; // This will be used to calculate the amount of stables to be sent to the stable fund

    // Project addresses
    address public _treasuryAddress;
    address public _marketingAddress;
    address public _stakingAddress;

    // Token and contract instances
    IERC20Burnable public _USDT;
    IERC20Burnable public _projectToken;
    IUniswapRouter public _router;
    ISubscriptions public _subscriptions;

    // External functions - Configuration
    function setRouter(address _address) external virtual;
    function setUSDTAddress(address _address) external virtual;
    function setSubscriptionsContractAddress(address _address) external virtual;
    function setTreasuryAddress(address _address) external virtual;
    function setMarketingAddress(address _address) external virtual;
    function setStakingAddress(address _address) external virtual;
    function setProjectToken(address _address) external virtual;
    function unpause() external virtual;

    // Public view functions
    function getUSDTDistribution() public view virtual returns (USDTDistribution memory);
    function getProjectTokenDistribution(uint256 _amount) public pure virtual returns (ProjectTokenDistribution memory);
    function getRequiredTokenForLiquidity(uint256 _amount) public view virtual returns (uint256);

    // External functions - Main functionality
    function distributeRevenue() external virtual;
}