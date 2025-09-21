// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {RevenueDistribution} from "./RevenueDistribution.sol";
import {IRevenueDistribution} from "./IRevenueDistribution.sol";
import {ISubscriptions} from "../subscriptions/ISubscriptions.sol";
import {IERC20Burnable} from "../token/IERC20Burnable.sol";
import {IUniswapRouter} from "../interfaces/IUniswapRouter.sol";
import {IUniswapFactory} from "../interfaces/IUniswapFactory.sol";
import {IUniswapPair} from "../interfaces/IUniswapPair.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {console} from "forge-std/console.sol";

// Mock contracts for testing
contract MockERC20Burnable is ERC20, IERC20Burnable {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {
        _mint(msg.sender, 1000000 ether);
    }

    function burn(uint256 amount) external override {
        _burn(msg.sender, amount);
    }

    function burnFrom(address account, uint256 amount) external override {
        _spendAllowance(account, msg.sender, amount);
        _burn(account, amount);
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract MockUniswapRouter is IUniswapRouter {
    address public factory;
    MockERC20Burnable public usdt;
    MockERC20Burnable public projectToken;
    
    constructor(address _factory, address _usdt, address _projectToken) {
        factory = _factory;
        usdt = MockERC20Burnable(_usdt);
        projectToken = MockERC20Burnable(_projectToken);
    }

    function addLiquidity(
        address,
        address,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256,
        uint256,
        address,
        uint256
    ) external pure override returns (uint256 amountA, uint256 amountB, uint256 liquidity) {
        // Simulate successful liquidity addition
        amountA = amountADesired;
        amountB = amountBDesired;
        liquidity = 1000; // Mock liquidity amount
    }

    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256,
        address[] calldata,
        address,
        uint256
    ) external pure override returns (uint256[] memory amounts) {
        amounts = new uint256[](2);
        amounts[0] = amountIn;
        amounts[1] = amountIn * 100; // Mock 100:1 ratio for project tokens
    }

    function getAmountsOut(uint256 amountIn, address[] calldata)
        external
        pure
        override
        returns (uint256[] memory amounts)
    {
        amounts = new uint256[](2);
        amounts[0] = amountIn;
        amounts[1] = amountIn * 100;
    }

    function WETH() external pure override returns (address) {
        return address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2); // Mock WETH address
    }
}

contract MockUniswapFactory is IUniswapFactory {
    mapping(address => mapping(address => address)) public pairs;
    
    function createPair(address tokenA, address tokenB) external returns (address pair) {
        pair = address(new MockUniswapPair(tokenA, tokenB));
        pairs[tokenA][tokenB] = pair;
        pairs[tokenB][tokenA] = pair;
    }

    function getPair(address tokenA, address tokenB) external view override returns (address pair) {
        return pairs[tokenA][tokenB];
    }
}

contract MockUniswapPair is IUniswapPair {
    address public token0;
    address public token1;
    uint112 private reserve0;
    uint112 private reserve1;
    uint32 private blockTimestampLast;

    constructor(address _token0, address _token1) {
        token0 = _token0;
        token1 = _token1;
        reserve0 = 1000 * 10**18; // USDT has 18 decimals
        reserve1 = 100000 * 10**18; // ProjectToken has 18 decimals
        blockTimestampLast = uint32(block.timestamp);
    }

    function getReserves() external view override returns (uint112 _reserve0, uint112 _reserve1, uint32 _blockTimestampLast) {
        return (reserve0, reserve1, blockTimestampLast);
    }

    function setReserves(uint112 _reserve0, uint112 _reserve1) external {
        reserve0 = _reserve0;
        reserve1 = _reserve1;
        blockTimestampLast = uint32(block.timestamp);
    }
}

contract MockSubscriptions is ISubscriptions {
    mapping(address => uint256) public tokenBalances;
    bool public shouldWithdrawSucceed = true;

    function setTokenBalance(address token, uint256 amount) external {
        tokenBalances[token] = amount;
    }

    function setWithdrawResult(bool success) external {
        shouldWithdrawSucceed = success;
    }

    function withdrawFunds(address token) external override returns (bool) {
        if (!shouldWithdrawSucceed) return false;
        
        uint256 amount = tokenBalances[token];
        if (amount > 0) {
            tokenBalances[token] = 0;
            IERC20Burnable(token).transfer(msg.sender, amount);
        }
        return true;
    }

    // Stub implementations for other required functions
    function unpause() external override {}
    function editPayment(uint256, address, uint256) external override {}
    function createSubscription(string memory, uint256, uint256) external override {}
    function isAvailablePayment(uint256, address) external pure override returns (bool) { return true; }
    function getSubscription(uint256) external pure override returns (Subscription memory) { return Subscription("test", 0); }
    function getSubscriptionPrice(uint256, address) external pure override returns (uint256) { return 0; }
    function subscriptionExists(uint256) external pure override returns (bool) { return true; }
    function userHasSubscription(address) external pure override returns (bool) { return false; }
    function subExpiresAt(address) external pure override returns (uint256) { return 0; }
    function subscribe(uint256, address) external override {}
    function renewSubscription(uint256, address) external override {}
}

contract RevenueDistributionTests is Test {
    RevenueDistribution revenueDistribution;
    MockERC20Burnable usdt;
    MockERC20Burnable projectToken;
    MockUniswapRouter router;
    MockUniswapFactory factory;
    MockUniswapPair pair;
    MockSubscriptions subscriptions;
    
    address admin = address(0x1);
    address treasury = address(0x2);
    address marketing = address(0x3);
    address staking = address(0x4);
    address user = address(0x5);

    function setUp() public {
        // Deploy mock contracts
        usdt = new MockERC20Burnable("USDT", "USDT");
        projectToken = new MockERC20Burnable("Project Token", "PROJ");
        factory = new MockUniswapFactory();
        router = new MockUniswapRouter(address(factory), address(usdt), address(projectToken));
        subscriptions = new MockSubscriptions();
        
        // Create Uniswap pair
        pair = MockUniswapPair(factory.createPair(address(usdt), address(projectToken)));
        
        // Deploy RevenueDistribution contract
        vm.prank(admin);
        revenueDistribution = new RevenueDistribution();
        
        // Setup initial balances
        usdt.mint(address(subscriptions), 10000 ether);
        subscriptions.setTokenBalance(address(usdt), 10000 ether);
        projectToken.mint(address(revenueDistribution), 100000 ether);
    }

    // Constructor Tests
    function test_Constructor_SetsAdminRole() public view {
        assertTrue(revenueDistribution.hasRole(revenueDistribution.DEFAULT_ADMIN_ROLE(), admin));
    }

    // Setter Function Tests
    function test_SetRouter_OnlyAdmin() public {
        vm.prank(user);
        vm.expectRevert(IRevenueDistribution.NotAdmin.selector);
        revenueDistribution.setRouter(address(router));
    }

    function test_SetRouter_ZeroAddress() public {
        vm.prank(admin);
        vm.expectRevert(IRevenueDistribution.TokenCannotBeZeroAddress.selector);
        revenueDistribution.setRouter(address(0));
    }

    function test_SetRouter_Success() public {
        address newRouter = address(0x123);
        vm.prank(admin);
        revenueDistribution.setRouter(newRouter);
        assertEq(address(revenueDistribution._router()), newRouter);
    }

    function test_SetUSDTAddress_OnlyAdmin() public {
        vm.prank(user);
        vm.expectRevert(IRevenueDistribution.NotAdmin.selector);
        revenueDistribution.setUSDTAddress(address(usdt));
    }

    function test_SetUSDTAddress_ZeroAddress() public {
        vm.prank(admin);
        vm.expectRevert(IRevenueDistribution.TokenCannotBeZeroAddress.selector);
        revenueDistribution.setUSDTAddress(address(0));
    }

    function test_SetUSDTAddress_Success() public {
        address newUSDT = address(0x456);
        vm.prank(admin);
        revenueDistribution.setUSDTAddress(newUSDT);
        assertEq(address(revenueDistribution._USDT()), newUSDT);
    }

    function test_SetProjectToken_OnlyAdmin() public {
        vm.prank(user);
        vm.expectRevert(IRevenueDistribution.NotAdmin.selector);
        revenueDistribution.setProjectToken(address(projectToken));
    }

    function test_SetProjectToken_ZeroAddress() public {
        vm.prank(admin);
        vm.expectRevert(IRevenueDistribution.TokenCannotBeZeroAddress.selector);
        revenueDistribution.setProjectToken(address(0));
    }

    function test_SetProjectToken_Success() public {
        address newToken = address(0x789);
        vm.prank(admin);
        revenueDistribution.setProjectToken(newToken);
        assertEq(address(revenueDistribution._projectToken()), newToken);
    }

    function test_SetTreasuryAddress_OnlyAdmin() public {
        vm.prank(user);
        vm.expectRevert(IRevenueDistribution.NotAdmin.selector);
        revenueDistribution.setTreasuryAddress(treasury);
    }

    function test_SetTreasuryAddress_ZeroAddress() public {
        vm.prank(admin);
        vm.expectRevert(IRevenueDistribution.TokenCannotBeZeroAddress.selector);
        revenueDistribution.setTreasuryAddress(address(0));
    }

    function test_SetTreasuryAddress_Success() public {
        address newTreasury = address(0xABC);
        vm.prank(admin);
        revenueDistribution.setTreasuryAddress(newTreasury);
        assertEq(revenueDistribution._treasuryAddress(), newTreasury);
    }

    function test_SetMarketingAddress_OnlyAdmin() public {
        vm.prank(user);
        vm.expectRevert(IRevenueDistribution.NotAdmin.selector);
        revenueDistribution.setMarketingAddress(marketing);
    }

    function test_SetMarketingAddress_ZeroAddress() public {
        vm.prank(admin);
        vm.expectRevert(IRevenueDistribution.TokenCannotBeZeroAddress.selector);
        revenueDistribution.setMarketingAddress(address(0));
    }

    function test_SetMarketingAddress_Success() public {
        address newMarketing = address(0xDEF);
        vm.prank(admin);
        revenueDistribution.setMarketingAddress(newMarketing);
        assertEq(revenueDistribution._marketingAddress(), newMarketing);
    }

    function test_SetStakingAddress_OnlyAdmin() public {
        vm.prank(user);
        vm.expectRevert(IRevenueDistribution.NotAdmin.selector);
        revenueDistribution.setStakingAddress(staking);
    }

    function test_SetStakingAddress_ZeroAddress() public {
        vm.prank(admin);
        vm.expectRevert(IRevenueDistribution.TokenCannotBeZeroAddress.selector);
        revenueDistribution.setStakingAddress(address(0));
    }

    function test_SetStakingAddress_Success() public {
        address newStaking = address(0x123);
        vm.prank(admin);
        revenueDistribution.setStakingAddress(newStaking);
        assertEq(revenueDistribution._stakingAddress(), newStaking);
    }

    function test_SetSubscriptionsContractAddress_OnlyAdmin() public {
        vm.prank(user);
        vm.expectRevert(IRevenueDistribution.NotAdmin.selector);
        revenueDistribution.setSubscriptionsContractAddress(address(subscriptions));
    }

    function test_SetSubscriptionsContractAddress_ZeroAddress() public {
        vm.prank(admin);
        vm.expectRevert(IRevenueDistribution.TokenCannotBeZeroAddress.selector);
        revenueDistribution.setSubscriptionsContractAddress(address(0));
    }

    function test_SetSubscriptionsContractAddress_Success() public {
        address newSubscriptions = address(0x456);
        vm.prank(admin);
        revenueDistribution.setSubscriptionsContractAddress(newSubscriptions);
        assertEq(address(revenueDistribution._subscriptions()), newSubscriptions);
    }

    // Distribution Calculation Tests
    function test_GetUSDTDistribution_WithBalance() public {

        // Give the contract some USDT balance
        usdt.mint(address(revenueDistribution), 1000 ether);

        vm.prank(admin);
        revenueDistribution.setUSDTAddress(address(usdt));
 
        IRevenueDistribution.USDTDistribution memory distribution = revenueDistribution.getUSDTDistribution();
        
        // With 50% stables ratio: 1000 * 50% = 500 stables
        // Marketing: 500 * 50% = 250
        // Liquidity: 500 * 50% = 250  
        // Buyback: 1000 - 500 = 500
        assertEq(distribution.marketing, 250 ether);
        assertEq(distribution.liquidity, 250 ether);
        assertEq(distribution.buyback, 500 ether);
    }

    function test_GetUSDTDistribution_ZeroBalance() public {
        vm.prank(admin);
        revenueDistribution.setUSDTAddress(address(usdt));

        IRevenueDistribution.USDTDistribution memory distribution = revenueDistribution.getUSDTDistribution();
        
        assertEq(distribution.marketing, 0);
        assertEq(distribution.liquidity, 0);
        assertEq(distribution.buyback, 0);
    }

    function test_GetProjectTokenDistribution() public view {
        uint256 amount = 1000 ether;
        IRevenueDistribution.ProjectTokenDistribution memory distribution = revenueDistribution.getProjectTokenDistribution(amount);
        
        // With 50% stables ratio: 1000 * (100-50)% = 500 tokens
        // Staking: 500 * 40% = 200
        // Burn: 500 * 40% = 200
        // Treasury: 500 * 20% = 100
        assertEq(distribution.staking, 200 ether);
        assertEq(distribution.burn, 200 ether);
        assertEq(distribution.treasury, 100 ether);
    }

    function test_GetProjectTokenDistribution_ZeroAmount() public view {
        IRevenueDistribution.ProjectTokenDistribution memory distribution = revenueDistribution.getProjectTokenDistribution(0);
        
        assertEq(distribution.staking, 0);
        assertEq(distribution.burn, 0);
        assertEq(distribution.treasury, 0);
    }

    // Liquidity Calculation Tests
    function test_GetRequiredTokenForLiquidity_ValidAmount() public {
        vm.startPrank(admin);
        revenueDistribution.setUSDTAddress(address(usdt));
        revenueDistribution.setRouter(address(router));
        revenueDistribution.setProjectToken(address(projectToken));
        vm.stopPrank();

        uint256 usdtAmount = 100 ether;
        uint256 requiredTokens = revenueDistribution.getRequiredTokenForLiquidity(usdtAmount);

        // Based on mock reserves: 1000 USDT : 100000 ProjectToken
        // So 100 USDT should require 10000 ProjectToken
        assertEq(requiredTokens, 10000 ether);
    }

    function test_GetRequiredTokenForLiquidity_ZeroAmount() public {
        vm.expectRevert(IRevenueDistribution.InvalidAmount.selector);
        revenueDistribution.getRequiredTokenForLiquidity(0);
    }

    function test_GetRequiredTokenForLiquidity_PairNotFound() public {
        // Deploy new router with factory that has no pairs
        MockUniswapFactory emptyFactory = new MockUniswapFactory();
        MockUniswapRouter emptyRouter = new MockUniswapRouter(address(emptyFactory), address(usdt), address(projectToken));
        
        vm.prank(admin);
        revenueDistribution.setRouter(address(emptyRouter));
        
        vm.expectRevert(IRevenueDistribution.PairNotFound.selector);
        revenueDistribution.getRequiredTokenForLiquidity(100 ether);
    }

    function test_GetRequiredTokenForLiquidity_ZeroReserves() public {
        vm.startPrank(admin);
        revenueDistribution.setUSDTAddress(address(usdt));
        revenueDistribution.setRouter(address(router));
        revenueDistribution.setProjectToken(address(projectToken));
        vm.stopPrank();

        
        // Set reserves to zero
        pair.setReserves(0, 0);
        
        vm.expectRevert(IRevenueDistribution.ZeroReserves.selector);
        revenueDistribution.getRequiredTokenForLiquidity(100 ether);
    }

    // Main Revenue Distribution Tests
    function test_DistributeRevenue_OnlyAdmin() public {
        vm.prank(user);
        vm.expectRevert(IRevenueDistribution.NotAdmin.selector);
        revenueDistribution.distributeRevenue();
    }

    function test_DistributeRevenue_USDTNotSet() public {
        vm.prank(admin);
        vm.expectRevert(IRevenueDistribution.USDTAddressNotSet.selector);
        revenueDistribution.distributeRevenue();
    }

    function test_DistributeRevenue_Success() public {
        vm.startPrank(admin);
        revenueDistribution.setUSDTAddress(address(usdt));
        revenueDistribution.setProjectToken(address(projectToken));
        revenueDistribution.setRouter(address(router));
        revenueDistribution.setSubscriptionsContractAddress(address(subscriptions));
        revenueDistribution.setTreasuryAddress(treasury);
        revenueDistribution.setMarketingAddress(marketing);
        revenueDistribution.setStakingAddress(staking);
        vm.stopPrank();

        // Setup initial balances first
        usdt.mint(address(subscriptions), 10000 ether);
        subscriptions.setTokenBalance(address(usdt), 10000 ether);
        projectToken.mint(address(revenueDistribution), 10000000 ether);

        // Record initial balances after setup
        uint256 initialUSDTBalance = usdt.balanceOf(address(revenueDistribution));
        uint256 initialProjectTokenBalance = projectToken.balanceOf(address(revenueDistribution));
        uint256 initialMarketingBalance = usdt.balanceOf(marketing);
        uint256 initialTreasuryBalance = projectToken.balanceOf(treasury);
        uint256 initialStakingBalance = projectToken.balanceOf(staking);
        
        vm.startPrank(admin);
        revenueDistribution.distributeRevenue();
        vm.stopPrank();
        
        // Check that USDT was withdrawn from subscriptions
        assertGt(usdt.balanceOf(address(revenueDistribution)), initialUSDTBalance);
        
        // Check that marketing received USDT
        assertGt(usdt.balanceOf(marketing), initialMarketingBalance);
        
        // Check that treasury and staking received project tokens
        assertGt(projectToken.balanceOf(treasury), initialTreasuryBalance);
        assertGt(projectToken.balanceOf(staking), initialStakingBalance);
        
        // Check that some project tokens were burned (balance decreased)
        assertLt(projectToken.balanceOf(address(revenueDistribution)), initialProjectTokenBalance);
    }

    // Error Condition Tests
    function test_DistributeRevenue_SubscriptionsNotSet() public {
        vm.startPrank(admin);
        revenueDistribution.setUSDTAddress(address(usdt));
        revenueDistribution.setProjectToken(address(projectToken));
        revenueDistribution.setRouter(address(router));
        vm.expectRevert(IRevenueDistribution.SubscriptionsAddressNotSet.selector);
        revenueDistribution.distributeRevenue();
        vm.stopPrank();
    }

    function test_DistributeRevenue_RouterNotSet() public {
        vm.startPrank(admin);
        revenueDistribution.setUSDTAddress(address(usdt));
        revenueDistribution.setProjectToken(address(projectToken));
        vm.expectRevert(IRevenueDistribution.RouterAddressNotSet.selector);
        revenueDistribution.distributeRevenue();
        vm.stopPrank();
    }

    function test_DistributeRevenue_ProjectTokenNotSet() public {
        vm.startPrank(admin);
        revenueDistribution.setUSDTAddress(address(usdt));
        vm.expectRevert(IRevenueDistribution.ProjectTokenAddressNotSet.selector);
        revenueDistribution.distributeRevenue();
        vm.stopPrank();
    }

    // Access Control Tests
    function test_AccessControl_AdminRole() public view {
        assertTrue(revenueDistribution.hasRole(revenueDistribution.DEFAULT_ADMIN_ROLE(), admin));
        assertFalse(revenueDistribution.hasRole(revenueDistribution.DEFAULT_ADMIN_ROLE(), user));
    }

    function test_AccessControl_GrantRole() public {
        vm.startPrank(admin);
        revenueDistribution.grantRole(revenueDistribution.DEFAULT_ADMIN_ROLE(), user);
        vm.stopPrank();
        
        assertTrue(revenueDistribution.hasRole(revenueDistribution.DEFAULT_ADMIN_ROLE(), user));
    }

    function test_AccessControl_RevokeRole() public {
        vm.startPrank(admin);
        revenueDistribution.revokeRole(revenueDistribution.DEFAULT_ADMIN_ROLE(), admin);
        vm.stopPrank();
        
        assertFalse(revenueDistribution.hasRole(revenueDistribution.DEFAULT_ADMIN_ROLE(), admin));
    }

    // Immutable Values Tests
    function test_ImmutableValues() public view {
        assertEq(revenueDistribution._burnPercent(), 40);
        assertEq(revenueDistribution._treasuryPercent(), 20);
        assertEq(revenueDistribution._stakingPercent(), 40);
        assertEq(revenueDistribution._marketingPercent(), 50);
        assertEq(revenueDistribution._liquidityPercent(), 50);
        assertEq(revenueDistribution._stablesRatio(), 50);
    }

    // Edge Cases and Integration Tests
    function test_DistributeRevenue_WithZeroUSDTBalance() public {
        vm.startPrank(admin);
        revenueDistribution.setUSDTAddress(address(usdt));
        revenueDistribution.setProjectToken(address(projectToken));
        revenueDistribution.setRouter(address(router));
        revenueDistribution.setSubscriptionsContractAddress(address(subscriptions));
        revenueDistribution.setTreasuryAddress(treasury);
        revenueDistribution.setMarketingAddress(marketing);
        revenueDistribution.setStakingAddress(staking);
        subscriptions.setWithdrawResult(true);
        subscriptions.setTokenBalance(address(usdt), 0);
        vm.expectRevert(IRevenueDistribution.InvalidAmount.selector);
        revenueDistribution.distributeRevenue();
        vm.stopPrank();
    }

    function test_DistributeRevenue_WithInsufficientProjectTokenBalance() public {
        vm.startPrank(admin);
        revenueDistribution.setUSDTAddress(address(usdt));
        revenueDistribution.setProjectToken(address(projectToken));
        revenueDistribution.setRouter(address(router));
        revenueDistribution.setSubscriptionsContractAddress(address(subscriptions));
        revenueDistribution.setTreasuryAddress(treasury);
        revenueDistribution.setMarketingAddress(marketing);
        revenueDistribution.setStakingAddress(staking);
        vm.stopPrank();

        projectToken.mint(address(revenueDistribution), 1 ether);
        usdt.mint(address(subscriptions), 100000 ether);
        subscriptions.setTokenBalance(address(usdt), 100000 ether);
        
        vm.startPrank(admin);
        vm.expectRevert();
        revenueDistribution.distributeRevenue();
        vm.stopPrank();
    }
}
