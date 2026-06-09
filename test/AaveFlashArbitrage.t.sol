// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {AaveFlashArbitrage} from "../src/arbitrage/AaveFlashArbitrage.sol";
import {BrianICOToken} from "../src/token/BrianICOToken.sol";
import {UniswapV2Factory} from "../src/uniswap-v2/core/UniswapV2Factory.sol";
import {UniswapV2Pair} from "../src/uniswap-v2/core/UniswapV2Pair.sol";
import {WETH9} from "../src/uniswap-v2/periphery/WETH9.sol";
import {IERC20} from "../src/uniswap-v2/periphery/interfaces/IERC20.sol";
import {IUniswapV2Pair} from "../src/uniswap-v2/core/interfaces/IUniswapV2Pair.sol";
import {IFlashLoanSimpleReceiver} from "aave-v3-core/contracts/flashloan/interfaces/IFlashLoanSimpleReceiver.sol";

// ============================================================================
// Mock: Aave v3 PoolAddressesProvider
// ============================================================================

contract MockPoolAddressesProvider {
    address public pool;

    constructor(address _pool) {
        pool = _pool;
    }

    function getPool() external view returns (address) {
        return pool;
    }
}

// ============================================================================
// Mock: Aave v3 Pool — only flashLoanSimple
// ============================================================================

contract MockAavePool {
    uint256 public constant FLASHLOAN_PREMIUM_TOTAL = 9; // 9 bps = 0.09%
    uint256 public constant PREMIUM_BASE = 10000;

    /// @dev Simulates Aave v3 flashLoanSimple:
    ///      1. Transfer `amount` of `asset` to `receiver`
    ///      2. Call receiver.executeOperation(asset, amount, premium, sender, params)
    ///      3. Pull back amount + premium from receiver via transferFrom
    function flashLoanSimple(
        address receiver,
        address asset,
        uint256 amount,
        bytes calldata params,
        uint16 /*referralCode*/
    )
        external
    {
        uint256 premium = (amount * FLASHLOAN_PREMIUM_TOTAL) / PREMIUM_BASE;

        // Step 1: Lend
        IERC20(asset).transfer(receiver, amount);

        // Step 2: Callback
        bool ok = IFlashLoanSimpleReceiver(receiver).executeOperation(asset, amount, premium, address(this), params);
        require(ok, "FLASH_LOAN_FAILED");

        // Step 3: Pull back amount + premium
        IERC20(asset).transferFrom(receiver, address(this), amount + premium);
    }
}

// ============================================================================
// Tests
// ============================================================================

contract AaveFlashArbitrageTest is Test {
    AaveFlashArbitrage public arbitrage;
    UniswapV2Factory public factory;
    WETH9 public weth;
    MockPoolAddressesProvider public provider;
    MockAavePool public aavePool;

    BrianICOToken public tokenA;
    BrianICOToken public tokenB;
    BrianICOToken public tokenC;

    address public owner = makeAddr("owner");
    address public deployer = makeAddr("deployer");
    address public bot = makeAddr("bot");
    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");

    uint256 constant INITIAL_SUPPLY = 1_000_000 * 10 ** 18;
    uint256 constant FUND_AMOUNT = 250_000 * 10 ** 18;

    event ArbitrageExecuted(
        address indexed initiator,
        address indexed asset,
        uint256 borrowAmount,
        uint256 premium,
        uint256 repayAmount,
        uint256 profit
    );

    function setUp() public {
        vm.label(owner, "owner");
        vm.label(deployer, "deployer");
        vm.label(bot, "bot");
        vm.label(alice, "alice");
        vm.label(bob, "bob");

        // ---- Deploy Aave mocks ----
        aavePool = new MockAavePool();
        vm.label(address(aavePool), "AavePool");

        provider = new MockPoolAddressesProvider(address(aavePool));
        vm.label(address(provider), "PoolAddressesProvider");

        // ---- Deploy Uniswap V2 ----
        vm.prank(deployer);
        factory = new UniswapV2Factory(deployer);
        weth = new WETH9();
        vm.label(address(weth), "WETH");

        // ---- Deploy tokens ----
        vm.prank(deployer);
        tokenA = new BrianICOToken(INITIAL_SUPPLY);
        vm.prank(deployer);
        tokenB = new BrianICOToken(INITIAL_SUPPLY);
        vm.prank(deployer);
        tokenC = new BrianICOToken(INITIAL_SUPPLY);

        vm.label(address(tokenA), "tokenA");
        vm.label(address(tokenB), "tokenB");
        vm.label(address(tokenC), "tokenC");

        // ---- Deploy AaveFlashArbitrage ----
        vm.prank(owner);
        arbitrage = new AaveFlashArbitrage(address(provider), address(factory));

        // ---- Fund users ----
        vm.startPrank(deployer);
        tokenA.transfer(alice, FUND_AMOUNT);
        tokenB.transfer(alice, FUND_AMOUNT);
        tokenC.transfer(alice, FUND_AMOUNT);
        tokenA.transfer(bob, FUND_AMOUNT);
        tokenB.transfer(bob, FUND_AMOUNT);
        tokenC.transfer(bob, FUND_AMOUNT);
        vm.stopPrank();
    }

    // ======================================================================
    // HELPER: Create a pair with liquidity
    // ======================================================================

    function _createPair(address tokenX, address tokenY, address lp, uint256 amtX, uint256 amtY)
        internal
        returns (address pair)
    {
        vm.prank(deployer);
        pair = factory.createPair(tokenX, tokenY);

        vm.startPrank(lp);
        IERC20(tokenX).transfer(pair, amtX);
        IERC20(tokenY).transfer(pair, amtY);
        IUniswapV2Pair(pair).mint(lp);
        vm.stopPrank();
    }

    // ======================================================================
    // HELPER: Fund Aave mock pool with tokens
    // ======================================================================

    function _fundAavePool(address token, uint256 amount) internal {
        vm.prank(deployer);
        IERC20(token).transfer(address(aavePool), amount);
    }

    // ======================================================================
    // UNISWAP V2 MATH HELPERS
    // ======================================================================

    function _getAmountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut) internal pure returns (uint256) {
        uint256 amountInWithFee = amountIn * 997;
        uint256 numerator = amountInWithFee * reserveOut;
        uint256 denominator = (reserveIn * 1000) + amountInWithFee;
        return numerator / denominator;
    }

    // ======================================================================
    // DEPLOYMENT TESTS
    // ======================================================================

    function test_Deployment() public view {
        assertEq(address(arbitrage.ADDRESSES_PROVIDER()), address(provider));
        assertEq(address(arbitrage.POOL()), address(aavePool));
        assertEq(arbitrage.factory(), address(factory));
        assertEq(arbitrage.owner(), owner);
    }

    function test_Deployment_RevertZeroProvider() public {
        vm.expectRevert("ZERO_PROVIDER");
        new AaveFlashArbitrage(address(0), address(factory));
    }

    function test_Deployment_RevertZeroFactory() public {
        vm.expectRevert("ZERO_FACTORY");
        new AaveFlashArbitrage(address(provider), address(0));
    }

    // ======================================================================
    // ARBITRAGE: TRIANGULAR (borrow A, path A→C→B→A)
    // ======================================================================

    /// @notice 三角套利：从 Aave 借 tokenA，沿 A→C→B→A 闭环交易。
    ///
    ///         Pair 设置（制造可套利的价格偏离）：
    ///           pairAC: 100k A / 200k C  （A 昂贵：1A ≈ 2C）
    ///           pairCB: 200k C / 50k B   （C 便宜：4C ≈ 1B）
    ///           pairBA: 200k A / 50k B   （B 昂贵：1B ≈ 4A，隐含 1B≈1A，偏离!）
    ///
    ///         路径 A→C→B→A：应为正利润（B 在 pairBA 高估 → A 在 pairBA 低估）
    function test_TriangularArbitrage_BorrowA() public {
        // pairAC: A(0x124...) < C(0x9c5...), reserveA=100k, reserveC=200k
        address pairAC = _createPair(address(tokenA), address(tokenC), deployer, 100_000 ether, 200_000 ether);
        // pairCB: C(0x9c5...) < B(0xff2...), reserveC=200k, reserveB=50k
        address pairCB = _createPair(address(tokenC), address(tokenB), alice, 200_000 ether, 50_000 ether);
        // pairBA: A(0x124...) < B(0xff2...), reserveA=200k, reserveB=50k
        address pairBA = _createPair(address(tokenA), address(tokenB), deployer, 200_000 ether, 50_000 ether);

        uint256 borrowAmount = 100 ether;
        address[] memory path = new address[](4);
        path[0] = address(tokenA);
        path[1] = address(tokenC);
        path[2] = address(tokenB);
        path[3] = address(tokenA);

        // A→C: pairAC token0=A, token1=C. Input token0=A. reserveIn=A=100k, reserveOut=C=200k.
        uint256 cOut = _getAmountOut(borrowAmount, 100_000 ether, 200_000 ether);
        // C→B: pairCB token0=C, token1=B. Input token0=C. reserveIn=C=200k, reserveOut=B=50k.
        uint256 bOut = _getAmountOut(cOut, 200_000 ether, 50_000 ether);
        // B→A: pairBA token0=A=200k, token1=B=50k. Input token1=B, output token0=A.
        uint256 aOut = _getAmountOut(bOut, 50_000 ether, 200_000 ether);

        uint256 premium = (borrowAmount * 9) / 10000;
        uint256 repayAmount = borrowAmount + premium;
        assertGt(aOut, repayAmount, "no profit");

        uint256 expectedProfit = aOut - repayAmount;
        _fundAavePool(address(tokenA), borrowAmount);

        vm.prank(owner);
        vm.expectEmit(true, true, false, true);
        emit ArbitrageExecuted(owner, address(tokenA), borrowAmount, premium, repayAmount, expectedProfit);
        arbitrage.executeArbitrage(address(tokenA), borrowAmount, path, 0, block.timestamp + 60);
    }

    // ======================================================================
    // ARBITRAGE: BORROW WETH (闭环 WETH→B→C→WETH)
    // ======================================================================

    function test_TriangularArbitrage_BorrowWETH() public {
        uint256 wethAmount = 50 ether;

        // ---- pairWB: 50 WETH / 200,000 B （B 便宜：1 WETH = 4000 B） ----
        address deployerAddr = deployer;
        vm.prank(deployerAddr);
        address pairWB = factory.createPair(address(weth), address(tokenB));

        vm.deal(alice, wethAmount);
        vm.startPrank(alice);
        weth.deposit{value: wethAmount}();
        weth.transfer(pairWB, wethAmount);
        tokenB.transfer(pairWB, 200_000 ether);
        IUniswapV2Pair(pairWB).mint(alice);
        vm.stopPrank();

        // ---- pairBC: 100,000 B / 200,000 C （C 便宜：1 B = 2 C） ----
        vm.prank(deployerAddr);
        address pairBC = factory.createPair(address(tokenB), address(tokenC));
        vm.startPrank(bob);
        tokenB.transfer(pairBC, 100_000 ether);
        tokenC.transfer(pairBC, 200_000 ether);
        IUniswapV2Pair(pairBC).mint(bob);
        vm.stopPrank();

        // ---- pairCW: 5,000 C / 50 WETH （C 贵：5000 C = 50 WETH → 100 C = 1 WETH） ----
        vm.prank(deployerAddr);
        address pairCW = factory.createPair(address(tokenC), address(weth));

        vm.deal(deployer, wethAmount);
        vm.startPrank(deployer);
        weth.deposit{value: wethAmount}();
        weth.transfer(pairCW, wethAmount);
        tokenC.transfer(pairCW, 5_000 ether); // C 很贵：100 C = 1 WETH
        IUniswapV2Pair(pairCW).mint(deployer);
        vm.stopPrank();

        // 路径：WETH → B → C → WETH
        uint256 borrowAmount = 1 ether;
        address[] memory path = new address[](4);
        path[0] = address(weth);
        path[1] = address(tokenB);
        path[2] = address(tokenC);
        path[3] = address(weth);

        // 计算预期（动态处理 token 排序）
        // WETH→B in pairWB
        uint256 bOut = _getAmountOut(borrowAmount, 50 ether, 200_000 ether);
        // B→C in pairBC: tokenB(0xff2...) > C(0x9c5...), token0=C, token1=B
        //                reserve0=C=200k, reserve1=B=100k. Input token1=B.
        uint256 cOut = _getAmountOut(bOut, 100_000 ether, 200_000 ether);
        // C→WETH in pairCW
        uint256 wethOut = _getAmountOut(cOut, 5_000 ether, 50 ether);

        uint256 premium = (borrowAmount * 9) / 10000;
        uint256 repayAmount = borrowAmount + premium;
        assertGt(wethOut, repayAmount, "no profit");

        uint256 expectedProfit = wethOut - repayAmount;

        // 给 Aave mock pool 充 WETH
        vm.deal(deployer, borrowAmount);
        vm.startPrank(deployer);
        weth.deposit{value: borrowAmount}();
        weth.transfer(address(aavePool), borrowAmount);
        vm.stopPrank();

        vm.prank(owner);
        vm.expectEmit(true, true, false, true);
        emit ArbitrageExecuted(owner, address(weth), borrowAmount, premium, repayAmount, expectedProfit);
        arbitrage.executeArbitrage(address(weth), borrowAmount, path, 0, block.timestamp + 60);
    }

    // ======================================================================
    // REVERT: VALIDATION
    // ======================================================================

    function test_Revert_NotOwner() public {
        address[] memory path = new address[](3);
        path[0] = address(tokenA);
        path[1] = address(tokenB);
        path[2] = address(tokenA);

        vm.prank(bot);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", bot));
        arbitrage.executeArbitrage(address(tokenA), 1 ether, path, 0, block.timestamp);
    }

    function test_Revert_ZeroAsset() public {
        address[] memory path = new address[](3);
        path[0] = address(tokenA);
        path[1] = address(tokenB);
        path[2] = address(tokenA);

        vm.prank(owner);
        vm.expectRevert("ZERO_ASSET");
        arbitrage.executeArbitrage(address(0), 1 ether, path, 0, block.timestamp);
    }

    function test_Revert_ZeroAmount() public {
        address[] memory path = new address[](3);
        path[0] = address(tokenA);
        path[1] = address(tokenB);
        path[2] = address(tokenA);

        vm.prank(owner);
        vm.expectRevert("ZERO_AMOUNT");
        arbitrage.executeArbitrage(address(tokenA), 0, path, 0, block.timestamp);
    }

    function test_Revert_PathTooShort() public {
        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(tokenA);

        vm.prank(owner);
        vm.expectRevert("PATH_TOO_SHORT");
        arbitrage.executeArbitrage(address(tokenA), 1 ether, path, 0, block.timestamp);
    }

    function test_Revert_Expired() public {
        address[] memory path = new address[](3);
        path[0] = address(tokenA);
        path[1] = address(tokenB);
        path[2] = address(tokenA);

        vm.warp(2000);
        vm.prank(owner);
        vm.expectRevert("EXPIRED");
        arbitrage.executeArbitrage(address(tokenA), 1 ether, path, 0, 1999);
    }

    function test_Revert_PathStartNotAsset() public {
        address[] memory path = new address[](3);
        path[0] = address(tokenB); // != tokenA
        path[1] = address(tokenC);
        path[2] = address(tokenA);

        vm.prank(owner);
        vm.expectRevert("PATH_START_NOT_ASSET");
        arbitrage.executeArbitrage(address(tokenA), 1 ether, path, 0, block.timestamp + 60);
    }

    function test_Revert_PathEndNotAsset() public {
        address[] memory path = new address[](3);
        path[0] = address(tokenA);
        path[1] = address(tokenB);
        path[2] = address(tokenC); // != tokenA

        vm.prank(owner);
        vm.expectRevert("PATH_END_NOT_ASSET");
        arbitrage.executeArbitrage(address(tokenA), 1 ether, path, 0, block.timestamp + 60);
    }

    function test_Revert_PairNotFound_InPath() public {
        // 不创建 pair，直接走路径
        address[] memory path = new address[](3);
        path[0] = address(tokenA);
        path[1] = address(tokenC); // pair A-C 不存在
        path[2] = address(tokenA);

        _fundAavePool(address(tokenA), 100 ether);

        vm.prank(owner);
        vm.expectRevert(); // PAIR_NOT_FOUND or ZERO_OUTPUT
        arbitrage.executeArbitrage(address(tokenA), 100 ether, path, 0, block.timestamp + 60);
    }

    function test_Revert_InsufficientRepay() public {
        // 创建 1:1 的 pair，路径 A→B→A 经过两跳必然亏损（0.6% 手续费）
        address pairAB = _createPair(address(tokenA), address(tokenB), alice, 100_000 ether, 100_000 ether);

        uint256 borrowAmount = 1 ether;
        address[] memory path = new address[](3);
        path[0] = address(tokenA);
        path[1] = address(tokenB);
        path[2] = address(tokenA);

        _fundAavePool(address(tokenA), borrowAmount);

        vm.prank(owner);
        vm.expectRevert(); // INSUFFICIENT_REPAY
        arbitrage.executeArbitrage(address(tokenA), borrowAmount, path, 0, block.timestamp + 60);
    }

    function test_Revert_InsufficientProfit() public {
        // 使用与 test_TriangularArbitrage_BorrowA 相同的可盈利设置
        address pairAC = _createPair(address(tokenA), address(tokenC), deployer, 100_000 ether, 200_000 ether);
        address pairCB = _createPair(address(tokenC), address(tokenB), alice, 200_000 ether, 50_000 ether);
        address pairBA = _createPair(address(tokenA), address(tokenB), deployer, 200_000 ether, 50_000 ether);

        uint256 borrowAmount = 1 ether;
        address[] memory path = new address[](4);
        path[0] = address(tokenA);
        path[1] = address(tokenC);
        path[2] = address(tokenB);
        path[3] = address(tokenA);

        _fundAavePool(address(tokenA), borrowAmount);

        // 设置远超实际利润的 minProfit
        vm.prank(owner);
        vm.expectRevert(); // INSUFFICIENT_PROFIT
        arbitrage.executeArbitrage(address(tokenA), borrowAmount, path, 1_000_000 ether, block.timestamp + 60);
    }

    function test_Revert_CallerNotPool() public {
        // 直接调用 executeOperation（绕过 Pool）应该被拒绝
        address[] memory path = new address[](3);
        path[0] = address(tokenA);
        path[1] = address(tokenB);
        path[2] = address(tokenA);

        bytes memory params = abi.encode(owner, path, uint256(0), block.timestamp + 60);

        vm.prank(bot);
        vm.expectRevert("CALLER_NOT_POOL");
        arbitrage.executeOperation(address(tokenA), 1 ether, 0, bot, params);
    }

    // ======================================================================
    // ADMIN WITHDRAW
    // ======================================================================

    function test_WithdrawETH() public {
        vm.deal(address(arbitrage), 10 ether);
        uint256 ownerBalanceBefore = owner.balance;

        vm.prank(owner);
        arbitrage.withdrawETH();

        assertEq(address(arbitrage).balance, 0);
        assertEq(owner.balance, ownerBalanceBefore + 10 ether);
    }

    function test_Revert_WithdrawETH_NotOwner() public {
        vm.deal(address(arbitrage), 10 ether);

        vm.prank(bot);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", bot));
        arbitrage.withdrawETH();
    }

    function test_WithdrawToken() public {
        vm.prank(alice);
        tokenA.transfer(address(arbitrage), 100 ether);

        uint256 balanceBefore = tokenA.balanceOf(owner);

        vm.prank(owner);
        arbitrage.withdrawToken(address(tokenA));

        assertEq(tokenA.balanceOf(address(arbitrage)), 0);
        assertEq(tokenA.balanceOf(owner), balanceBefore + 100 ether);
    }

    function test_Revert_WithdrawToken_NoTokens() public {
        vm.prank(owner);
        vm.expectRevert("NO_TOKENS");
        arbitrage.withdrawToken(address(tokenA));
    }
}
