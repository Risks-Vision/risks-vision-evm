// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {ISubscriptions} from "./subscriptions/ISubscriptions.sol";

contract RevenueDistribution is AccessControl, Pausable, ReentrancyGuard {
    error NotAdmin();
    error TokenCannotBeZeroAddress();
    error InvalidToken();
    error InvalidSubscriptionFunds();
    error InvalidAmount();
    error PaymentFailed();

    ISubscriptions public _subscriptionsContract;

    struct Distribution {
        uint256 burn;
        uint256 treasury;
        uint256 staking;
        uint256 marketing;
        uint256 liquidity;
    }

    uint256 public immutable _burnPercent = 20; // This amount will be burned forever
    uint256 public immutable _treasuryPercent = 10; // The treasury tokens will be sent to an address
    uint256 public immutable _stakingPercent = 20; // This will be sent to the staking pools
    uint256 public immutable _marketingPercent = 25; // This will be sent to the marketing address
    uint256 public immutable _liquidityPercent = 25; // This will be locked on the liquidity pool

    // Porject addresses

    address public _treasuryAddress;
    address public _marketingAddress;

    constructor() {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _pause();
    }

    function setSubscriptionsContractAddress(address _address) external {
        if (!hasRole(DEFAULT_ADMIN_ROLE, msg.sender)) revert NotAdmin();
        _subscriptionsContract = ISubscriptions(_address);
    }

    function setTreasuryAddress(address _address) external {
        if (!hasRole(DEFAULT_ADMIN_ROLE, msg.sender)) revert NotAdmin();
        _treasuryAddress = _address;
    }
    
    function setMarketingAddress(address  _address) external {
        if (!hasRole(DEFAULT_ADMIN_ROLE, msg.sender)) revert NotAdmin();
        _marketingAddress = _address;
    }

    function unpause() external {
        if (!hasRole(DEFAULT_ADMIN_ROLE, msg.sender)) revert NotAdmin();
        _unpause();
    }

    function getDistribution(uint256 _amount) public pure returns (Distribution memory) {
        return Distribution({
            burn: _amount * _burnPercent / 100,
            treasury: _amount * _treasuryPercent / 100,
            staking: _amount * _stakingPercent / 100,
            marketing: _amount * _marketingPercent / 100,
            liquidity: _amount * _liquidityPercent / 100
        });
    }

    function getRevenueFromSubscriptions(address _token) internal {
        _subscriptionsContract.withdrawFunds(_token);
    }

    function distributeToAddresses(address _token, uint256 _treasuryAmount, uint256 _marketingAmount) internal {
        if (_treasuryAmount == 0 || _marketingAmount == 0) revert InvalidAmount();
        if (_token == address(0)) revert TokenCannotBeZeroAddress();
        if (!IERC20(_token).transfer(_treasuryAddress, _treasuryAmount)) revert PaymentFailed();
        if (!IERC20(_token).transfer(_marketingAddress, _marketingAmount)) revert PaymentFailed();
    }

    function burnProjectTokens(address _token, uint256 _amount) internal {
        if (_amount == 0) revert InvalidAmount();
        if (_token == address(0)) revert TokenCannotBeZeroAddress();
        if (!IERC20(_token).transfer(address(0), _amount)) revert PaymentFailed();
    }

    function distributeRevenue(address _token, bool _isProject) external {
        if (!hasRole(DEFAULT_ADMIN_ROLE, msg.sender)) revert NotAdmin();
        if (_token == address(0)) revert TokenCannotBeZeroAddress();
        if (!_subscriptionsContract.withdrawFunds(_token)) revert InvalidSubscriptionFunds();

        uint256 _amount = IERC20(_token).balanceOf(address(this));

        if (_amount == 0) revert InvalidAmount();

        if (_isProject) _distributeRevenueWithProjectToken(_token, _amount);
        else _distributeRevenueWithExternalToken(_token, _amount);
    }

    function _distributeRevenueWithExternalToken(address _token, uint256 _amount) internal {
        Distribution memory distribution = getDistribution(_amount);
        distributeToAddresses(_token, distribution.treasury, distribution.marketing);
    }

    function _distributeRevenueWithProjectToken(address _token, uint256 _amount) internal {
        Distribution memory distribution = getDistribution(_amount);
        distributeToAddresses(_token, distribution.treasury, distribution.marketing);
        burnProjectTokens(_token, distribution.burn);
    }
}
