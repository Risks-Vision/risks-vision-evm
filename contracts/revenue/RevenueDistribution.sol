// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IRevenueDistribution} from "./IRevenueDistribution.sol";
import {ISubscriptions} from "../subscriptions/ISubscriptions.sol";
import {IUniswapFactory} from "../interfaces/IUniswapFactory.sol";
import {IUniswapPair} from "../interfaces/IUniswapPair.sol";
import {IUniswapRouter} from "../interfaces/IUniswapRouter.sol";
import {IERC20Burnable} from "../token/IERC20Burnable.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract RevenueDistribution is IRevenueDistribution {
    /**
     * @dev Initializes the RevenueDistribution contract
     * Grants admin role to the deployer and pauses the contract initially
     */
    constructor() {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    /**
     * @dev Validates the admin setter
     * @param _address The address of the admin setter
     * @notice Only admin can call this function
     * @notice The address cannot be zero
     */
    function validateAdminSetter(address _address) private view {
        if (!hasRole(DEFAULT_ADMIN_ROLE, msg.sender)) revert NotAdmin();
        if (_address == address(0)) revert TokenCannotBeZeroAddress();
    }

    /**
     * @dev Sets the Uniswap router address for token swaps and liquidity operations
     * @param _address The address of the Uniswap router contract
     * @notice Only admin can call this function
     */
    function setRouter(address _address) external override {
        validateAdminSetter(_address);
        _router = IUniswapRouter(_address);
    }
    
    /**
     * @dev Sets the USDT token contract address
     * @param _address The address of the USDT ERC20 token contract
     * @notice Only admin can call this function
     */
    function setUSDTAddress(address _address) external override {
        validateAdminSetter(_address);
        _USDT = IERC20Burnable(_address);
    }

    /**
     * @dev Sets the subscriptions contract address for revenue collection
     * @param _address The address of the ISubscriptions contract
     * @notice Only admin can call this function
     */
    function setSubscriptionsContractAddress(address _address) external override {
        validateAdminSetter(_address);
        _subscriptions = ISubscriptions(_address);
    }

    /**
     * @dev Sets the treasury address where project tokens will be sent
     * @param _address The address of the treasury wallet
     * @notice Only admin can call this function
     */
    function setTreasuryAddress(address _address) external override {
        validateAdminSetter(_address);
        _treasuryAddress = _address;
    }
    
    /**
     * @dev Sets the marketing address where USDT will be sent for marketing purposes
     * @param _address The address of the marketing wallet
     * @notice Only admin can call this function
     */
    function setMarketingAddress(address  _address) external override {
        validateAdminSetter(_address);
        _marketingAddress = _address;
    }

    /**
     * @dev Sets the staking address where project tokens will be sent for staking rewards
     * @param _address The address of the staking contract or wallet
     * @notice Only admin can call this function
     */
    function setStakingAddress(address _address) external override {
        validateAdminSetter(_address);
        _stakingAddress = _address;
    }

    /**
     * @dev Sets the project token contract address
     * @param _address The address of the project's ERC20 token contract
     * @notice Only admin can call this function
     */
    function setProjectToken(address _address) external override {
        validateAdminSetter(_address);
        _projectToken = IERC20Burnable(_address);
    }

    /**
     * @dev Calculates the distribution of USDT tokens based on current balance
     * @return _distribution A struct containing the amounts for marketing, liquidity, and buyback
     * @notice Marketing and liquidity get 50% each of the stable ratio, buyback gets the remaining USDT
     */
    function getUSDTDistribution() public view override returns (USDTDistribution memory) {
        uint256 _amount = _USDT.balanceOf(address(this));
        uint256 _stables = _amount * _stablesRatio / 100;

        return USDTDistribution({
            marketing: _stables * _marketingPercent / 100,
            liquidity: _stables * _liquidityPercent / 100,
            buyback: _amount - _stables
        });
    }

    /**
     * @dev Calculates the distribution of project tokens based on the input amount
     * @param _amount The total amount of project tokens to distribute
     * @return _distribution A struct containing the amounts for staking (40%), burn (40%), and treasury (20%)
     * @notice The distribution is based on the non-stable ratio of the total amount
     */
    function getProjectTokenDistribution(uint256 _amount) public pure override returns (ProjectTokenDistribution memory) {
        uint256 _tokens = _amount * (100 - _stablesRatio) / 100;

        return ProjectTokenDistribution({
            staking: _tokens * _stakingPercent / 100,
            burn: _tokens * _burnPercent / 100,
            treasury: _tokens * _treasuryPercent / 100
        });
    }

    /**
     * @dev Withdraws USDT funds from the subscriptions contract
     * @return success True if the withdrawal was successful, false otherwise
     * @notice This function is protected by reentrancy guard and can only be called internally
     */
    function getRevenueFromSubscriptions() private returns (bool) {
        if (address(_USDT) == address(0)) revert TokenCannotBeZeroAddress();
        if (address(_subscriptions) == address(0)) revert SubscriptionsAddressNotSet();
        return _subscriptions.withdrawFunds(address(_USDT));
    }

    /**
     * @dev Distributes project tokens to staking, burn (zero address), and treasury addresses
     * @param _distribution The distribution amounts for staking, burn, and treasury
     * @notice This function is protected by reentrancy guard and can only be called internally
     * @notice Burns tokens by sending them to the zero address
     */
    function distributeTokenToAddresses(ProjectTokenDistribution memory _distribution) private {
        if (_distribution.staking == 0 || _distribution.burn == 0 || _distribution.treasury == 0) revert InvalidAmount();
        if (!_projectToken.transfer(_stakingAddress, _distribution.staking)) revert PaymentFailed();
        if (!_projectToken.transfer(_treasuryAddress, _distribution.treasury)) revert PaymentFailed();
        _projectToken.burn(_distribution.burn);
    }

    /**
     * @dev Distributes USDT to the marketing address
     * @param _marketing The amount of USDT to send to the marketing address
     * @notice This function is protected by reentrancy guard and can only be called internally
     */
    function distributeUSDTToAddresses(uint256 _marketing) private {
        if (_marketing == 0) revert InvalidAmount();
        if (!_USDT.transfer(_marketingAddress, _marketing)) revert PaymentFailed();
    }

    /**
     * @dev Adds liquidity to the USDT/ProjectToken pair on Uniswap
     * @param _usdtA The amount of USDT to add as liquidity
     * @notice This function is protected by reentrancy guard and can only be called internally
     * @notice Calculates the required project token amount based on current pool reserves
     * @notice Uses a 5-minute deadline for the transaction
     */
    function addLiquidity(uint256 _usdtA) private {
        if (_usdtA == 0) revert InvalidAmount();
        if (address(_USDT) == address(0) || address(_projectToken) == address(0) || address(_router) == address(0)) revert InvalidToken();

        uint256 _tokenA = getRequiredTokenForLiquidity(_usdtA);

        if (_projectToken.balanceOf(address(this)) < _tokenA) revert InsufficientBalance();
        if (_USDT.balanceOf(address(this)) < _usdtA) revert InsufficientBalance();

        SafeERC20.forceApprove(_USDT, address(_router), _usdtA);
        SafeERC20.forceApprove(_projectToken, address(_router), _tokenA);

        uint256 deadline = block.timestamp + 300; // 5 minutes

        (uint256 amountA, uint256 amountB, uint256 liquidity) = _router.addLiquidity(
            address(_USDT),
            address(_projectToken),
            _usdtA,
            _tokenA,
            0,
            0,
            address(this),
            deadline
        );

        if (liquidity == 0 || amountA == 0 || amountB == 0) revert InsufficientLiquidityAdded();
    }

    /**
     * @dev Swaps USDT for project tokens using Uniswap router
     * @param _amount The amount of USDT to swap
     * @return The amount of project tokens received from the swap
     * @notice This function is protected by reentrancy guard and can only be called internally
     * @notice Uses a direct USDT -> ProjectToken swap path
     * @notice Uses a 5-minute deadline for the transaction
     */
    function swapUSDTToToken(uint256 _amount) private returns (uint256) {
        if (address(_projectToken) == address(0)) revert TokenCannotBeZeroAddress();
        if (address(_USDT) == address(0)) revert USDTAddressNotSet();
        if (address(_router) == address(0)) revert RouterAddressNotSet();
        if (_amount == 0) revert InvalidAmount();

        SafeERC20.forceApprove(_USDT, address(_router), _amount);

        uint256 deadline = block.timestamp + 300; // 5 minutes
        address[] memory path = new address[](2);

        path[0] = address(_USDT);
        path[1] = address(_projectToken);

        uint256[] memory amounts = _router.swapExactTokensForTokens(_amount, 0, path, address(this), deadline);

        if (amounts[1] == 0) revert SwapFailed();

        return amounts[1];
    }

    /**
     * @dev Calculates the required amount of project tokens for adding liquidity with a given USDT amount
     * @param _amount The amount of USDT to be used for liquidity
     * @return The required amount of project tokens based on current pool reserves
     * @notice This function queries the Uniswap pair reserves to maintain the correct ratio
     * @notice Reverts if the pair doesn't exist or has zero reserves
     */
     function getRequiredTokenForLiquidity(uint256 _amount) public view override returns (uint256) {
        if (_amount == 0) revert InvalidAmount();

        address factory = IUniswapRouter(address(_router)).factory();
        address pair = IUniswapFactory(factory).getPair(address(_USDT), address(_projectToken));

        if (address(pair) == address(0)) revert PairNotFound();

        IUniswapPair uniswapPair = IUniswapPair(pair);
        (uint112 reserve0, uint112 reserve1,) = uniswapPair.getReserves();

        if (reserve0 == 0 || reserve1 == 0) revert ZeroReserves();

        if (uniswapPair.token0() == address(_USDT)) return (_amount * reserve1) / reserve0;
        return (_amount * reserve0) / reserve1;
    }

    /**
     * @dev Main function to distribute revenue from subscriptions
     * @notice Only admin can call this function
     * @notice This function:
     *         1. Withdraws USDT from subscriptions contract
     *         2. Calculates USDT distribution (marketing, liquidity, buyback)
     *         3. Swaps buyback USDT for project tokens
     *         4. Distributes USDT to marketing address
     *         5. Distributes project tokens (staking, burn, treasury)
     *         6. Adds liquidity to the USDT/ProjectToken pair
     */
    function distributeRevenue() external nonReentrant override {
        if (!hasRole(DEFAULT_ADMIN_ROLE, msg.sender)) revert NotAdmin();
        if (address(_USDT) == address(0)) revert TokenCannotBeZeroAddress();
        if(!getRevenueFromSubscriptions()) revert InvalidFundsWithdrawn();

        USDTDistribution memory _distribution = getUSDTDistribution();
        uint256 _projectTokenAmount = swapUSDTToToken(_distribution.buyback);

        distributeUSDTToAddresses(_distribution.marketing);
        distributeTokenToAddresses(getProjectTokenDistribution(_projectTokenAmount));
        addLiquidity(_distribution.liquidity);
    }
}
