// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {LendingMarket, IFlashLoanReceiver} from "../src/LendingMarket.sol";
import {BrianICOToken} from "../src/BrianICOToken.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// ============================================================================
// Mock FlashLoanReceiver — 模拟闪电贷回调接收者
// ============================================================================

contract MockFlashLoanReceiver is IFlashLoanReceiver {
    bool public shouldSucceed;
    address public lastInitiator;
    address public lastAsset;
    uint256 public lastAmount;
    uint256 public lastPremium;

    function setShouldSucceed(bool succeed) external {
        shouldSucceed = succeed;
    }

    function onFlashLoan(
        address initiator,
        address asset,
        uint256 amount,
        uint256 premium,
        bytes calldata /*params*/
    ) external override returns (bool) {
        lastInitiator = initiator;
        lastAsset = asset;
        lastAmount = amount;
        lastPremium = premium;

        if (shouldSucceed) {
            // 授权 lending market 拉走 amount + premium
            IERC20(asset).approve(msg.sender, amount + premium);
            return true;
        }
        return false;
    }
}

// ============================================================================
// Tests
// ============================================================================

contract LendingMarketTest is Test {
    LendingMarket public market;
    BrianICOToken public tokenA;
    BrianICOToken public tokenB;
    MockFlashLoanReceiver public flashReceiver;

    address public owner = makeAddr("owner");
    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");
    address public carol = makeAddr("carol");

    uint256 constant INITIAL_SUPPLY = 1_000_000 * 10 ** 18;
    uint256 constant FUND_AMOUNT = 250_000 * 10 ** 18;

    uint256 constant RAY = 1e27;
    uint256 constant BPS = 10000;

    event Supplied(address indexed user, address indexed asset, uint256 amount);
    event Withdrawn(address indexed user, address indexed asset, uint256 amount);
    event Borrowed(address indexed user, address indexed asset, uint256 amount);
    event Repaid(address indexed user, address indexed asset, uint256 amount);
    event FlashLoan(address indexed receiver, address indexed asset, uint256 amount, uint256 premium);
    event Liquidated(
        address indexed liquidator,
        address indexed borrower,
        address collateralAsset,
        address debtAsset,
        uint256 debtCovered,
        uint256 collateralSeized
    );

    function setUp() public {
        vm.label(owner, "owner");
        vm.label(alice, "alice");
        vm.label(bob, "bob");
        vm.label(carol, "carol");

        // Deploy tokens
        vm.prank(owner);
        tokenA = new BrianICOToken(INITIAL_SUPPLY);
        vm.prank(owner);
        tokenB = new BrianICOToken(INITIAL_SUPPLY);
        vm.label(address(tokenA), "tokenA");
        vm.label(address(tokenB), "tokenB");

        // Deploy LendingMarket
        vm.prank(owner);
        market = new LendingMarket();

        // Deploy mock flash loan receiver
        flashReceiver = new MockFlashLoanReceiver();

        // Initialize reserves for both tokens
        _initReserve(address(tokenA), 7500, 8500, 10500, 9, 1e8);  // $1 USD price
        _initReserve(address(tokenB), 7500, 8500, 10500, 9, 2e8);  // $2 USD price

        // Fund users
        vm.startPrank(owner);
        tokenA.transfer(alice, FUND_AMOUNT);
        tokenA.transfer(bob, FUND_AMOUNT);
        tokenA.transfer(carol, FUND_AMOUNT);
        tokenB.transfer(alice, FUND_AMOUNT);
        tokenB.transfer(bob, FUND_AMOUNT);
        tokenB.transfer(carol, FUND_AMOUNT);
        vm.stopPrank();
    }

    // ======================================================================
    // HELPER
    // ======================================================================

    function _initReserve(
        address asset,
        uint256 cf,
        uint256 lt,
        uint256 lb,
        uint256 flp,
        uint256 price
    ) internal {
        vm.prank(owner);
        market.initReserve(
            asset,     // asset
            cf,        // collateralFactor
            lt,        // liquidationThreshold
            lb,        // liquidationBonus
            flp,       // flashLoanPremium
            price,     // price
            0.8e27,    // optimalUtilizationRate: 80%
            0.02e27,   // baseBorrowRate: 2%
            0.06e27,   // slope1: 6%
            3.0e27     // slope2: 300%
        );
    }

    function _approveToken(BrianICOToken token, address spender, address user, uint256 amount) internal {
        vm.prank(user);
        token.approve(spender, amount);
    }

    // ======================================================================
    // DEPLOYMENT & RESERVE INIT
    // ======================================================================

    function test_Deployment() public view {
        assertEq(market.owner(), owner);
        address[] memory list = market.getReservesList();
        assertEq(list.length, 2);
    }

    function test_InitReserve_RevertsIfAlreadyActive() public {
        vm.prank(owner);
        vm.expectRevert("LM: ALREADY_ACTIVE");
        market.initReserve(address(tokenA), 7500, 8500, 10500, 9, 1e8, 0.8e27, 0.02e27, 0.06e27, 3.0e27);
    }

    function test_InitReserve_RevertsIfCollateralFactorTooHigh() public {
        vm.prank(owner);
        vm.expectRevert("LM: INVALID_CF");
        market.initReserve(makeAddr("newToken"), 10001, 8500, 10500, 9, 1e8, 0.8e27, 0.02e27, 0.06e27, 3.0e27);
    }

    function test_SetAssetPrice() public {
        vm.prank(owner);
        market.setAssetPrice(address(tokenA), 5e8); // $5

        (,,,,,,,,,,,,, uint256 price,) = market.reserves(address(tokenA));
        assertEq(price, 5e8);
    }

    function test_SetFlashLoanPremium() public {
        vm.prank(owner);
        market.setFlashLoanPremium(address(tokenA), 50); // 0.5%

        (,,,,,,,,,,,, uint256 flp,,) = market.reserves(address(tokenA));
        assertEq(flp, 50);
    }

    // ======================================================================
    // SUPPLY
    // ======================================================================

    function test_Supply_Success() public {
        uint256 amount = 1000 ether;
        _approveToken(tokenA, address(market), alice, amount);

        vm.prank(alice);
        vm.expectEmit(true, true, false, true);
        emit Supplied(alice, address(tokenA), amount);
        market.supply(address(tokenA), amount);

        assertEq(tokenA.balanceOf(address(market)), amount);
        assertEq(market.getUserSupply(alice, address(tokenA)), amount);
    }

    function test_Supply_ZeroAmountReverts() public {
        vm.prank(alice);
        vm.expectRevert("LM: ZERO_AMOUNT");
        market.supply(address(tokenA), 0);
    }

    function test_Supply_InactiveReserveReverts() public {
        vm.prank(alice);
        vm.expectRevert("LM: INACTIVE_RESERVE");
        market.supply(makeAddr("unknown"), 100 ether);
    }

    // ======================================================================
    // WITHDRAW
    // ======================================================================

    function test_Withdraw_Success() public {
        uint256 amount = 1000 ether;
        _approveToken(tokenA, address(market), alice, amount);
        vm.prank(alice);
        market.supply(address(tokenA), amount);

        uint256 balanceBefore = tokenA.balanceOf(alice);
        vm.prank(alice);
        vm.expectEmit(true, true, false, true);
        emit Withdrawn(alice, address(tokenA), amount);
        market.withdraw(address(tokenA), amount);

        assertEq(tokenA.balanceOf(alice), balanceBefore + amount);
        assertEq(market.getUserSupply(alice, address(tokenA)), 0);
    }

    function test_Withdraw_InsufficientSupplyReverts() public {
        vm.prank(alice);
        vm.expectRevert("LM: INSUFFICIENT_SUPPLY");
        market.withdraw(address(tokenA), 1 ether);
    }

    function test_Withdraw_CollateralCheckAfterBorrow() public {
        // Alice supplies tokenA (collateral), bob supplies tokenB (liquidity)
        uint256 supplyAmount = 1000 ether;
        _approveToken(tokenA, address(market), alice, supplyAmount);
        _approveToken(tokenB, address(market), bob, 2000 ether);
        vm.prank(bob);
        market.supply(address(tokenB), 2000 ether); // liquidity for borrows

        vm.startPrank(alice);
        market.supply(address(tokenA), supplyAmount);
        market.setUserUseAsCollateral(address(tokenA), true);

        // tokenA price=$1, collateralFactor=75% → maxBorrow = 1000 * 0.75 = $750
        // tokenB price=$2 → maxBorrow in tokenB = 750/2 = 375
        uint256 borrowAmount = 375 ether;
        market.borrow(address(tokenB), borrowAmount);
        vm.stopPrank();

        // Trying to withdraw collateral now should fail (health factor < 1)
        vm.prank(alice);
        vm.expectRevert("LM: HEALTH_FACTOR_BELOW_1");
        market.withdraw(address(tokenA), supplyAmount);
    }

    // ======================================================================
    // BORROW
    // ======================================================================

    function test_Borrow_Success() public {
        // Setup: alice supplies tokenA, bob supplies tokenB (for liquidity)
        uint256 aliceSupply = 1000 ether;
        uint256 bobSupply = 2000 ether;
        _approveToken(tokenA, address(market), alice, aliceSupply);
        _approveToken(tokenB, address(market), bob, bobSupply);

        vm.prank(alice);
        market.supply(address(tokenA), aliceSupply);
        vm.prank(alice);
        market.setUserUseAsCollateral(address(tokenA), true);
        vm.prank(bob);
        market.supply(address(tokenB), bobSupply);

        // Alice borrows tokenB
        uint256 borrowAmount = 100 ether; // well within limits
        uint256 balanceBefore = tokenB.balanceOf(alice);

        vm.prank(alice);
        vm.expectEmit(true, true, false, true);
        emit Borrowed(alice, address(tokenB), borrowAmount);
        market.borrow(address(tokenB), borrowAmount);

        assertEq(tokenB.balanceOf(alice), balanceBefore + borrowAmount);
        assertEq(market.getUserBorrow(alice, address(tokenB)), borrowAmount);
    }

    function test_Borrow_InsufficientCollateralReverts() public {
        // Supply tokenA but no one supplies tokenB for liquidity
        _approveToken(tokenA, address(market), alice, 1000 ether);
        vm.startPrank(alice);
        market.supply(address(tokenA), 1000 ether);
        market.setUserUseAsCollateral(address(tokenA), true);

        // tokenB has no liquidity yet
        vm.expectRevert("LM: INSUFFICIENT_LIQUIDITY");
        market.borrow(address(tokenB), 100 ether);
        vm.stopPrank();
    }

    function test_Borrow_HealthFactorBelowOneReverts() public {
        // First: supply tokenB liquidity
        _approveToken(tokenB, address(market), bob, 2000 ether);
        vm.prank(bob);
        market.supply(address(tokenB), 2000 ether);

        // Alice supplies small collateral and tries to borrow too much
        uint256 supply = 100 ether; // $100 (price=$1)
        _approveToken(tokenA, address(market), alice, supply);
        vm.startPrank(alice);
        market.supply(address(tokenA), supply);
        market.setUserUseAsCollateral(address(tokenA), true);

        // Max borrow in USD = $100 * 0.75 = $75
        // In tokenB ($2 each) = 37.5 tokenB
        // Try to borrow 100 tokenB = $200 > $75
        vm.expectRevert("LM: HEALTH_FACTOR_BELOW_1");
        market.borrow(address(tokenB), 100 ether);
        vm.stopPrank();
    }

    // ======================================================================
    // REPAY
    // ======================================================================

    function test_Repay_Success() public {
        // Setup
        _approveToken(tokenA, address(market), alice, 1000 ether);
        _approveToken(tokenB, address(market), alice, 1000 ether);
        _approveToken(tokenB, address(market), bob, 2000 ether);

        vm.prank(bob);
        market.supply(address(tokenB), 2000 ether); // liquidity provider

        vm.startPrank(alice);
        market.supply(address(tokenA), 1000 ether);
        market.setUserUseAsCollateral(address(tokenA), true);
        market.borrow(address(tokenB), 100 ether);
        vm.stopPrank();

        uint256 borrowBefore = market.getUserBorrow(alice, address(tokenB));
        assertEq(borrowBefore, 100 ether);

        // Repay
        vm.prank(alice);
        vm.expectEmit(true, true, false, true);
        emit Repaid(alice, address(tokenB), 100 ether);
        market.repay(address(tokenB), 100 ether);

        assertEq(market.getUserBorrow(alice, address(tokenB)), 0);
    }

    // ======================================================================
    // INTEREST ACCRUAL
    // ======================================================================

    function test_InterestAccrual_DepositEarnsInterest() public {
        // Alice supplies, bob borrows — over time alice earns interest
        uint256 supplyAmount = 1000 ether;
        _approveToken(tokenA, address(market), alice, supplyAmount);
        _approveToken(tokenA, address(market), bob, 100 ether); // for approval
        _approveToken(tokenB, address(market), bob, 2000 ether);

        vm.prank(alice);
        market.supply(address(tokenA), supplyAmount);
        vm.prank(alice);
        market.setUserUseAsCollateral(address(tokenA), true);

        // Bob supplies tokenB and borrows tokenA to create utilization
        vm.startPrank(bob);
        market.supply(address(tokenB), 2000 ether);
        market.setUserUseAsCollateral(address(tokenB), true);
        market.borrow(address(tokenA), 500 ether); // 50% utilization → interest
        vm.stopPrank();

        uint256 supplyBefore = market.getUserSupply(alice, address(tokenA));
        assertEq(supplyBefore, supplyAmount);

        // Fast forward 30 days
        vm.warp(block.timestamp + 30 days);

        uint256 supplyAfter = market.getUserSupply(alice, address(tokenA));
        assertGt(supplyAfter, supplyBefore, "No interest accrued");
    }

    // ======================================================================
    // FLASH LOAN
    // ======================================================================

    function test_FlashLoan_Success() public {
        // Supply some tokens for flash loan liquidity
        uint256 supplyAmount = 5000 ether;
        _approveToken(tokenA, address(market), alice, supplyAmount);
        vm.prank(alice);
        market.supply(address(tokenA), supplyAmount);

        uint256 loanAmount = 1000 ether;
        uint256 premium = (loanAmount * 9) / BPS; // 0.09%

        // Fund receiver first so it can approve repayment
        vm.prank(alice);
        tokenA.transfer(address(flashReceiver), premium); // need premium to repay

        flashReceiver.setShouldSucceed(true);

        vm.prank(alice);
        vm.expectEmit(true, true, false, true);
        emit FlashLoan(address(flashReceiver), address(tokenA), loanAmount, premium);
        market.flashLoan(address(flashReceiver), address(tokenA), loanAmount, "");

        // Verify callback was called
        assertEq(flashReceiver.lastAsset(), address(tokenA));
        assertEq(flashReceiver.lastAmount(), loanAmount);
        assertEq(flashReceiver.lastPremium(), premium);
        assertEq(flashReceiver.lastInitiator(), alice);
    }

    function test_FlashLoan_CallbackFailsReverts() public {
        uint256 supplyAmount = 5000 ether;
        _approveToken(tokenA, address(market), alice, supplyAmount);
        vm.prank(alice);
        market.supply(address(tokenA), supplyAmount);

        flashReceiver.setShouldSucceed(false); // callback will return false

        vm.prank(alice);
        vm.expectRevert("LM: FLASHLOAN_CALLBACK_FAILED");
        market.flashLoan(address(flashReceiver), address(tokenA), 1000 ether, "");
    }

    function test_FlashLoan_SelfLoanReverts() public {
        uint256 supplyAmount = 5000 ether;
        _approveToken(tokenA, address(market), alice, supplyAmount);
        vm.prank(alice);
        market.supply(address(tokenA), supplyAmount);

        vm.prank(alice);
        vm.expectRevert("LM: SELF_LOAN");
        market.flashLoan(address(market), address(tokenA), 1000 ether, "");
    }

    function test_FlashLoan_InsufficientLiquidityReverts() public {
        vm.prank(alice);
        vm.expectRevert("LM: INSUFFICIENT_LIQUIDITY");
        market.flashLoan(address(flashReceiver), address(tokenA), 100 ether, "");
    }

    // ======================================================================
    // LIQUIDATION
    // ======================================================================

    function test_Liquidate_Success() public {
        // Alice supplies tokenA as collateral, borrows tokenB
        // Bob supplies tokenB for liquidity
        // Token price drops (tokenA price halved) → Alice undercollateralized
        // Carol liquidates

        _approveToken(tokenA, address(market), alice, 2000 ether);
        _approveToken(tokenB, address(market), alice, 1000 ether);
        _approveToken(tokenB, address(market), bob, 2000 ether);
        _approveToken(tokenB, address(market), carol, 1000 ether);

        // Bob supplies tokenB (liquidity)
        vm.prank(bob);
        market.supply(address(tokenB), 2000 ether);

        // Alice supplies tokenA, borrows tokenB
        vm.startPrank(alice);
        market.supply(address(tokenA), 2000 ether);
        market.setUserUseAsCollateral(address(tokenA), true);

        // 2000 tokenA * $1 * 75% = $1500 max borrow
        // tokenB price = $2 → max borrow = 750 tokenB
        // Borrow 600 tokenB → debt = $1200, collateral = $2000
        // Health = (2000 * 0.85) / 1200 = 1700/1200 = 1.416 → safe
        market.borrow(address(tokenB), 600 ether);
        vm.stopPrank();

        // Now admin drops tokenA price to $0.60
        // Collateral = 2000 * $0.60 = $1200
        // Debt = 600 * $2 = $1200
        // Health = (1200 * 0.85) / 1200 = 0.85 → LIQUIDATABLE
        vm.prank(owner);
        market.setAssetPrice(address(tokenA), 0.6e8);

        // Carol liquidates: covers 200 tokenB of debt
        vm.startPrank(carol);
        uint256 debtToCover = 200 ether;
        uint256 expectedCollateral =
            (debtToCover * 2e8 * 10500) / (0.6e8 * BPS); // (200 * 2 * 10500) / (0.6 * 10000) = 700 tokenA

        vm.expectEmit(true, true, false, false);
        emit Liquidated(
            carol, alice, address(tokenA), address(tokenB), debtToCover, expectedCollateral
        );
        market.liquidate(address(tokenA), address(tokenB), alice, debtToCover);
        vm.stopPrank();

        assertEq(market.getUserBorrow(alice, address(tokenB)), 400 ether); // 600 - 200
        assertEq(market.getUserSupply(alice, address(tokenA)), 2000 ether - expectedCollateral);
    }

    function test_Liquidate_HealthFactorAboveOneReverts() public {
        // Alice supplies and borrows within safe limits
        _approveToken(tokenA, address(market), alice, 2000 ether);
        _approveToken(tokenB, address(market), bob, 2000 ether);

        vm.prank(bob);
        market.supply(address(tokenB), 2000 ether);

        vm.startPrank(alice);
        market.supply(address(tokenA), 2000 ether);
        market.setUserUseAsCollateral(address(tokenA), true);
        market.borrow(address(tokenB), 100 ether); // safe
        vm.stopPrank();

        // Carol tries to liquidate a healthy position
        vm.prank(carol);
        vm.expectRevert("LM: HEALTH_FACTOR_ABOVE_1");
        market.liquidate(address(tokenA), address(tokenB), alice, 100 ether);
    }

    function test_Liquidate_SelfLiquidateReverts() public {
        _approveToken(tokenA, address(market), alice, 2000 ether);
        _approveToken(tokenB, address(market), bob, 2000 ether);

        vm.prank(bob);
        market.supply(address(tokenB), 2000 ether);

        vm.startPrank(alice);
        market.supply(address(tokenA), 2000 ether);
        market.setUserUseAsCollateral(address(tokenA), true);
        market.borrow(address(tokenB), 100 ether);
        vm.stopPrank();

        vm.prank(alice);
        vm.expectRevert("LM: SELF_LIQUIDATE");
        market.liquidate(address(tokenA), address(tokenB), alice, 100 ether);
    }

    // ======================================================================
    // USER ACCOUNT DATA
    // ======================================================================

    function test_GetUserAccountData_NoDebt() public {
        _approveToken(tokenA, address(market), alice, 1000 ether);
        vm.prank(alice);
        market.supply(address(tokenA), 1000 ether);
        vm.prank(alice);
        market.setUserUseAsCollateral(address(tokenA), true);

        (
            uint256 totalCollateralUSD,
            uint256 totalDebtUSD,
            ,
            ,
            ,
            uint256 healthFactor
        ) = market.getUserAccountData(alice);

        // 1000 tokens * $1 (price=1e8) / 1e8 = 1000e18 wei-equivalent
        assertEq(totalCollateralUSD, 1000 ether);
        assertEq(totalDebtUSD, 0);
        assertEq(healthFactor, type(uint256).max); // no debt = max
    }

    function test_GetUserAccountData_WithDebt() public {
        _approveToken(tokenA, address(market), alice, 1000 ether);
        _approveToken(tokenB, address(market), bob, 2000 ether);

        vm.prank(bob);
        market.supply(address(tokenB), 2000 ether);

        vm.startPrank(alice);
        market.supply(address(tokenA), 1000 ether);
        market.setUserUseAsCollateral(address(tokenA), true);
        market.borrow(address(tokenB), 100 ether);
        vm.stopPrank();

        (
            uint256 totalCollateralUSD,
            uint256 totalDebtUSD,
            uint256 availableBorrowsUSD,
            ,
            uint256 ltv,
            uint256 healthFactor
        ) = market.getUserAccountData(alice);

        // 1000 tokenA * $1 = 1000e18
        assertEq(totalCollateralUSD, 1000 ether);
        // 100 tokenB * $2 = 200e18
        assertEq(totalDebtUSD, 200 ether);
        assertEq(ltv, 7500);                // 75%
        assertGt(healthFactor, RAY);        // > 1.0
        assertGt(availableBorrowsUSD, 0);
    }

    // ======================================================================
    // COLLATERAL TOGGLE
    // ======================================================================

    function test_SetUserUseAsCollateral_NoSupplyReverts() public {
        vm.prank(alice);
        vm.expectRevert("LM: NO_SUPPLY");
        market.setUserUseAsCollateral(address(tokenA), true);
    }

    function test_SetUserUseAsCollateral_Disable() public {
        _approveToken(tokenA, address(market), alice, 1000 ether);
        vm.startPrank(alice);
        market.supply(address(tokenA), 1000 ether);
        market.setUserUseAsCollateral(address(tokenA), true);

        assertTrue(market.isUsingAsCollateral(alice, address(tokenA)));

        market.setUserUseAsCollateral(address(tokenA), false);
        assertFalse(market.isUsingAsCollateral(alice, address(tokenA)));
        vm.stopPrank();
    }

    // ======================================================================
    // VIEW FUNCTIONS
    // ======================================================================

    function test_GetCurrentBorrowRate() public view {
        uint256 rate = market.getCurrentBorrowRate(address(tokenA));
        // No borrowing yet, should be base rate = 2%
        assertEq(rate, 0.02e27);
    }

    function test_GetCurrentBorrowRate_WithUtilization() public {
        _approveToken(tokenA, address(market), alice, 1000 ether);
        _approveToken(tokenB, address(market), alice, 1000 ether); // for approval
        _approveToken(tokenB, address(market), bob, 2000 ether);
        _approveToken(tokenA, address(market), carol, 2000 ether);

        // Carol supplies tokenA (liquidity)
        vm.prank(carol);
        market.supply(address(tokenA), 2000 ether);

        // Alice supplies tokenB as collateral, borrows tokenA
        vm.startPrank(bob);
        market.supply(address(tokenB), 2000 ether);
        market.setUserUseAsCollateral(address(tokenB), true);
        vm.stopPrank();

        vm.startPrank(alice);
        market.supply(address(tokenB), 1000 ether);
        market.setUserUseAsCollateral(address(tokenB), true);
        market.borrow(address(tokenA), 500 ether); // 500/2000 = 25% utilization
        vm.stopPrank();

        uint256 rate = market.getCurrentBorrowRate(address(tokenA));
        // util=25%, optimal=80% → rate = base + (0.25/0.80) * slope1 = 2% + 0.3125*6% = 3.875%
        assertGt(rate, 0.02e27, "Rate should be above base");
    }
}
