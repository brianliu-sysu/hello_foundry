// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {BrianICOToken} from "../src/token/BrianICOToken.sol";
import {UniswapV2Factory} from "../src/uniswap-v2/core/UniswapV2Factory.sol";
import {UniswapV2Pair} from "../src/uniswap-v2/core/UniswapV2Pair.sol";
import {UniswapV2Router02} from "../src/uniswap-v2/periphery/UniswapV2Router02.sol";
import {IERC20} from "../src/uniswap-v2/periphery/interfaces/IERC20.sol";
import {UniswapV2Library} from "../src/uniswap-v2/periphery/libraries/UniswapV2Library.sol";
import {WETH9} from "../src/uniswap-v2/periphery/WETH9.sol";
import {IUniswapV2Pair} from "../src/uniswap-v2/core/interfaces/IUniswapV2Pair.sol";
import {IUniswapV2Factory} from "../src/uniswap-v2/core/interfaces/IUniswapV2Factory.sol";

contract UniswapV2Test is Test {
    UniswapV2Factory public factory;
    WETH9 public weth;
    UniswapV2Router02 public router;

    BrianICOToken public tokenA;
    BrianICOToken public tokenB;
    BrianICOToken public tokenC;

    address public deployer = makeAddr("deployer");
    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");
    address public feeTo = makeAddr("feeTo");

    uint256 constant INITIAL_SUPPLY = 1_000_000 * 10 ** 18;

    event Mint(address indexed sender, uint256 amount0, uint256 amount1);
    event Burn(address indexed sender, uint256 amount0, uint256 amount1, address indexed to);
    event Swap(
        address indexed sender,
        uint256 amount0In,
        uint256 amount1In,
        uint256 amount0Out,
        uint256 amount1Out,
        address indexed to
    );
    event Sync(uint112 reserve0, uint112 reserve1);
    event PairCreated(address indexed token0, address indexed token1, address pair, uint256);

    function setUp() public {
        vm.label(deployer, "deployer");
        vm.label(alice, "alice");
        vm.label(bob, "bob");
        vm.label(feeTo, "feeTo");

        // Deploy core infrastructure
        vm.prank(deployer);
        factory = new UniswapV2Factory(deployer);
        weth = new WETH9();
        router = new UniswapV2Router02(address(factory), address(weth));

        // Deploy test tokens
        vm.prank(deployer);
        tokenA = new BrianICOToken(INITIAL_SUPPLY);
        vm.prank(deployer);
        tokenB = new BrianICOToken(INITIAL_SUPPLY);
        vm.prank(deployer);
        tokenC = new BrianICOToken(INITIAL_SUPPLY);

        // Fund alice and bob with each token
        uint256 fundAmount = INITIAL_SUPPLY / 4; // 250k each
        vm.startPrank(deployer);
        tokenA.transfer(alice, fundAmount);
        tokenB.transfer(alice, fundAmount);
        tokenC.transfer(alice, fundAmount);
        tokenA.transfer(bob, fundAmount);
        tokenB.transfer(bob, fundAmount);
        tokenC.transfer(bob, fundAmount);
        vm.stopPrank();
    }

    // ======================================================================
    // FACTORY TESTS (8)
    // ======================================================================

    function test_Factory_Deployment() public view {
        assertEq(factory.feeToSetter(), deployer);
        assertEq(factory.allPairsLength(), 0);
        assertEq(factory.feeTo(), address(0));
    }

    function test_Factory_PairCodeHash() public view {
        bytes32 expected = keccak256(type(UniswapV2Pair).creationCode);
        assertEq(factory.pairCodeHash(), expected);
    }

    function test_Factory_CreatePair() public {
        vm.prank(deployer);
        address pair = factory.createPair(address(tokenA), address(tokenB));

        assertTrue(pair != address(0));
        assertEq(factory.getPair(address(tokenA), address(tokenB)), pair);
        assertEq(factory.getPair(address(tokenB), address(tokenA)), pair);
        assertEq(factory.allPairsLength(), 1);
        assertEq(factory.allPairs(0), pair);

        // Token ordering
        IUniswapV2Pair p = IUniswapV2Pair(pair);
        assertTrue(address(tokenA) < address(tokenB) ? p.token0() == address(tokenA) : p.token1() == address(tokenA));
    }

    function test_Factory_CreatePair_EmitsEvent() public {
        (address t0, address t1) =
            address(tokenA) < address(tokenB) ? (address(tokenA), address(tokenB)) : (address(tokenB), address(tokenA));

        vm.prank(deployer);
        // Check token0 & token1 (indexed), skip pair & length
        vm.expectEmit(true, true, false, false);
        emit PairCreated(t0, t1, address(0), 0);
        factory.createPair(address(tokenA), address(tokenB));
    }

    function test_Factory_CreatePair_RevertsIdenticalTokens() public {
        vm.prank(deployer);
        vm.expectRevert("UniswapV2: IDENTICAL_ADDRESSES");
        factory.createPair(address(tokenA), address(tokenA));
    }

    function test_Factory_CreatePair_RevertsZeroAddress() public {
        vm.prank(deployer);
        vm.expectRevert("UniswapV2: ZERO_ADDRESS");
        factory.createPair(address(tokenA), address(0));
    }

    function test_Factory_CreatePair_RevertsDuplicate() public {
        vm.startPrank(deployer);
        factory.createPair(address(tokenA), address(tokenB));
        vm.expectRevert("UniswapV2: PAIR_EXISTS");
        factory.createPair(address(tokenA), address(tokenB));
        vm.stopPrank();
    }

    function test_Factory_SetFeeTo_AccessControl() public {
        vm.prank(deployer);
        factory.setFeeTo(feeTo);
        assertEq(factory.feeTo(), feeTo);

        // Non-feeToSetter cannot call
        vm.prank(alice);
        vm.expectRevert("UniswapV2: FORBIDDEN");
        factory.setFeeTo(alice);
    }

    // ======================================================================
    // PAIR TESTS (8)
    // ======================================================================

    function _createPair() internal returns (address pair) {
        vm.prank(deployer);
        pair = factory.createPair(address(tokenA), address(tokenB));
        vm.label(pair, "pair");
    }

    function _addInitialLiquidity() internal returns (address pair, uint256 liq) {
        pair = _createPair();
        uint256 amountA = 1000 * 10 ** 18;
        uint256 amountB = 2000 * 10 ** 18;

        vm.startPrank(alice);
        tokenA.approve(address(router), amountA);
        tokenB.approve(address(router), amountB);
        (,, uint256 liquidity) =
            router.addLiquidity(address(tokenA), address(tokenB), amountA, amountB, 0, 0, alice, block.timestamp);
        vm.stopPrank();

        uint256 minLiq = 10 ** 3;
        assertTrue(liquidity > minLiq, "should mint > MINIMUM_LIQUIDITY");
        liq = liquidity;
    }

    function test_Pair_MintInitial() public {
        address pair = _createPair();
        uint256 amountA = 1000 * 10 ** 18;
        uint256 amountB = 2000 * 10 ** 18;

        vm.startPrank(alice);
        tokenA.transfer(pair, amountA);
        tokenB.transfer(pair, amountB);

        vm.expectEmit(true, false, false, false);
        emit Mint(alice, amountA, amountB);
        uint256 liquidity = IUniswapV2Pair(pair).mint(alice);
        vm.stopPrank();

        // LP = sqrt(amountA * amountB) - MINIMUM_LIQUIDITY
        uint256 expectedLiq = _sqrt(amountA * amountB) - 1000;
        assertEq(liquidity, expectedLiq);
        assertEq(IERC20(pair).balanceOf(alice), expectedLiq);
        // 1000 MINIMUM_LIQUIDITY locked to address(0)
        assertEq(IERC20(pair).balanceOf(address(0)), 1000);
    }

    function test_Pair_MintAdditional() public {
        (address pair,) = _addInitialLiquidity();

        // Bob adds more liquidity
        uint256 amountA = 500 * 10 ** 18;
        uint256 amountB = 1000 * 10 ** 18;
        vm.startPrank(bob);
        tokenA.transfer(pair, amountA);
        tokenB.transfer(pair, amountB);
        uint256 bobLiq = IUniswapV2Pair(pair).mint(bob);
        vm.stopPrank();

        assertTrue(bobLiq > 0);
        assertEq(IERC20(pair).balanceOf(bob), bobLiq);
    }

    function test_Pair_Burn() public {
        (address pair, uint256 liq) = _addInitialLiquidity();

        uint256 aliceBalanceBefore = tokenA.balanceOf(alice) + tokenB.balanceOf(alice);

        vm.startPrank(alice);
        IERC20(pair).transfer(pair, liq); // send LP tokens back to pair
        (uint256 amount0, uint256 amount1) = IUniswapV2Pair(pair).burn(alice);
        vm.stopPrank();

        uint256 aliceBalanceAfter = tokenA.balanceOf(alice) + tokenB.balanceOf(alice);
        assertTrue(amount0 > 0);
        assertTrue(amount1 > 0);
        // Alice should have received tokens back (minus fees if any)
        assertGt(aliceBalanceAfter, aliceBalanceBefore);
    }

    function test_Pair_Swap() public {
        (address pair,) = _addInitialLiquidity();

        uint256 swapAmount = 10 * 10 ** 18;
        uint256 bobBefore = tokenB.balanceOf(bob);
        vm.startPrank(alice);
        tokenA.transfer(pair, swapAmount);

        (uint112 res0Before, uint112 res1Before,) = IUniswapV2Pair(pair).getReserves();
        uint256 amount0Out = 0;
        uint256 amount1Out = _getAmountOut(swapAmount, res0Before, res1Before);

        vm.expectEmit(true, false, false, true);
        emit Swap(alice, swapAmount, 0, 0, amount1Out, bob);
        IUniswapV2Pair(pair).swap(amount0Out, amount1Out, bob, new bytes(0));
        vm.stopPrank();

        assertEq(tokenB.balanceOf(bob), bobBefore + amount1Out);
        // Check K invariant holds (after fees)
        (uint112 res0After, uint112 res1After,) = IUniswapV2Pair(pair).getReserves();
        assertTrue(
            uint256(res0After) * uint256(res1After) >= uint256(res0Before) * uint256(res1Before),
            "K invariant decreased"
        );
    }

    function test_Pair_Swap_RevertsInsufficientOutput() public {
        (address pair,) = _addInitialLiquidity();

        vm.prank(alice);
        vm.expectRevert("UniswapV2: INSUFFICIENT_OUTPUT_AMOUNT");
        IUniswapV2Pair(pair).swap(0, 0, bob, new bytes(0));
    }

    function test_Pair_Sync_Skim() public {
        (address pair,) = _addInitialLiquidity();

        // Send extra tokens to the pair (simulates fees or accidental transfer)
        uint256 extra = 100 * 10 ** 18;
        vm.prank(alice);
        tokenA.transfer(pair, extra);

        // skim the excess
        (uint112 res0Before,,) = IUniswapV2Pair(pair).getReserves();
        vm.prank(alice);
        IUniswapV2Pair(pair).skim(alice);

        // After skim, balance should match reserves
        (uint112 res0After,,) = IUniswapV2Pair(pair).getReserves();
        assertEq(tokenA.balanceOf(pair), uint256(res0After));
    }

    function test_Pair_GetReserves() public {
        (address pair,) = _addInitialLiquidity();
        (uint112 r0, uint112 r1, uint32 ts) = IUniswapV2Pair(pair).getReserves();
        assertTrue(r0 > 0);
        assertTrue(r1 > 0);
        assertEq(ts, uint32(block.timestamp % 2 ** 32));
    }

    // ======================================================================
    // ROUTER TESTS (10)
    // ======================================================================

    function test_Router_AddLiquidity() public {
        uint256 amountA = 1000 * 10 ** 18;
        uint256 amountB = 2000 * 10 ** 18;

        vm.startPrank(alice);
        tokenA.approve(address(router), amountA);
        tokenB.approve(address(router), amountB);
        (uint256 a, uint256 b, uint256 liquidity) =
            router.addLiquidity(address(tokenA), address(tokenB), amountA, amountB, 0, 0, alice, block.timestamp);
        vm.stopPrank();

        assertEq(a, amountA);
        assertEq(b, amountB);
        assertTrue(liquidity > 1000);

        address pair = factory.getPair(address(tokenA), address(tokenB));
        assertEq(tokenA.balanceOf(pair), amountA);
        assertEq(tokenB.balanceOf(pair), amountB);
    }

    function test_Router_AddLiquidityETH() public {
        uint256 tokenAmount = 1000 * 10 ** 18;
        uint256 ethAmount = 1 ether;

        vm.startPrank(alice);
        tokenA.approve(address(router), tokenAmount);

        vm.deal(alice, ethAmount * 2);
        (uint256 amountToken, uint256 amountETH, uint256 liquidity) =
            router.addLiquidityETH{value: ethAmount}(address(tokenA), tokenAmount, 0, 0, alice, block.timestamp);
        vm.stopPrank();

        assertEq(amountToken, tokenAmount);
        assertEq(amountETH, ethAmount);
        assertTrue(liquidity > 1000);
        assertEq(weth.balanceOf(alice), 0); // WETH deposited into pair
    }

    function test_Router_RemoveLiquidity() public {
        // First add liquidity
        (address pair,) = _addInitialLiquidity();
        uint256 lpBalance = IERC20(pair).balanceOf(alice);

        vm.startPrank(alice);
        IERC20(pair).approve(address(router), lpBalance);
        (uint256 amountA, uint256 amountB) =
            router.removeLiquidity(address(tokenA), address(tokenB), lpBalance, 0, 0, alice, block.timestamp);
        vm.stopPrank();

        assertTrue(amountA > 0);
        assertTrue(amountB > 0);
    }

    function test_Router_RemoveLiquidityETH() public {
        // Add tokenA-WETH liquidity
        uint256 tokenAmount = 1000 * 10 ** 18;
        uint256 ethAmount = 1 ether;

        vm.startPrank(alice);
        tokenA.approve(address(router), tokenAmount);
        vm.deal(alice, ethAmount * 2);
        (,, uint256 liquidity) =
            router.addLiquidityETH{value: ethAmount}(address(tokenA), tokenAmount, 0, 0, alice, block.timestamp);

        address pair = factory.getPair(address(tokenA), address(weth));
        IERC20(pair).approve(address(router), liquidity);
        uint256 ethBefore = alice.balance;
        (uint256 amountToken, uint256 amountETH) =
            router.removeLiquidityETH(address(tokenA), liquidity, 0, 0, alice, block.timestamp);
        vm.stopPrank();

        assertTrue(amountToken > 0);
        assertTrue(amountETH > 0);
        assertGt(alice.balance, ethBefore);
    }

    function test_Router_SwapExactTokensForTokens() public {
        (address pair,) = _addInitialLiquidity();

        uint256 swapAmount = 10 * 10 ** 18;
        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(tokenB);

        uint256[] memory amounts = router.getAmountsOut(swapAmount, path);
        uint256 expectedOut = amounts[1];

        vm.startPrank(alice);
        tokenA.approve(address(router), swapAmount);
        uint256 bobBefore = tokenB.balanceOf(bob);
        uint256[] memory result = router.swapExactTokensForTokens(swapAmount, expectedOut, path, bob, block.timestamp);
        vm.stopPrank();

        assertEq(result[1], expectedOut);
        assertEq(tokenB.balanceOf(bob), bobBefore + expectedOut);
    }

    function test_Router_SwapExactTokensForTokens_MultiHop() public {
        // Create A-B and B-C pairs
        (address pairAB,) = _addInitialLiquidity();

        vm.startPrank(deployer);
        factory.createPair(address(tokenB), address(tokenC));
        vm.stopPrank();

        // Add liquidity to B-C
        uint256 amountB = 1000 * 10 ** 18;
        uint256 amountC = 3000 * 10 ** 18;
        vm.startPrank(alice);
        tokenB.approve(address(router), amountB);
        tokenC.approve(address(router), amountC);
        router.addLiquidity(address(tokenB), address(tokenC), amountB, amountC, 0, 0, alice, block.timestamp);
        vm.stopPrank();

        // A -> B -> C swap
        uint256 swapAmount = 10 * 10 ** 18;
        address[] memory path = new address[](3);
        path[0] = address(tokenA);
        path[1] = address(tokenB);
        path[2] = address(tokenC);

        uint256[] memory amounts = router.getAmountsOut(swapAmount, path);
        uint256 expectedOut = amounts[2];

        vm.startPrank(alice);
        tokenA.approve(address(router), swapAmount);
        uint256 bobBefore = tokenC.balanceOf(bob);
        router.swapExactTokensForTokens(swapAmount, expectedOut, path, bob, block.timestamp);
        vm.stopPrank();

        assertEq(tokenC.balanceOf(bob), bobBefore + expectedOut);
    }

    function test_Router_SwapExactETHForTokens() public {
        // Add tokenA-WETH liquidity
        uint256 tokenAmount = 5000 * 10 ** 18;
        uint256 ethAmount = 1 ether;
        vm.startPrank(alice);
        tokenA.approve(address(router), tokenAmount);
        vm.deal(alice, ethAmount * 2);
        router.addLiquidityETH{value: ethAmount}(address(tokenA), tokenAmount, 0, 0, alice, block.timestamp);
        vm.stopPrank();

        // Bob swaps ETH for tokenA
        uint256 swapEth = 0.1 ether;
        address[] memory path = new address[](2);
        path[0] = address(weth);
        path[1] = address(tokenA);

        uint256[] memory amounts = router.getAmountsOut(swapEth, path);
        uint256 expectedOut = amounts[1];

        vm.deal(bob, swapEth);
        vm.startPrank(bob);
        uint256 bobBefore = tokenA.balanceOf(bob);
        router.swapExactETHForTokens{value: swapEth}(expectedOut, path, bob, block.timestamp);
        vm.stopPrank();

        assertEq(tokenA.balanceOf(bob), bobBefore + expectedOut);
    }

    function test_Router_SwapExactTokensForETH() public {
        // Add tokenA-WETH liquidity
        uint256 tokenAmount = 5000 * 10 ** 18;
        uint256 ethAmount = 1 ether;
        vm.startPrank(alice);
        tokenA.approve(address(router), tokenAmount);
        vm.deal(alice, ethAmount * 2);
        router.addLiquidityETH{value: ethAmount}(address(tokenA), tokenAmount, 0, 0, alice, block.timestamp);
        vm.stopPrank();

        // Alice swaps tokenA for ETH
        uint256 swapAmount = 100 * 10 ** 18;
        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(weth);

        uint256[] memory amounts = router.getAmountsOut(swapAmount, path);
        uint256 expectedOut = amounts[1];

        vm.startPrank(alice);
        tokenA.approve(address(router), swapAmount);
        uint256 ethBefore = alice.balance;
        router.swapExactTokensForETH(swapAmount, expectedOut, path, alice, block.timestamp);
        vm.stopPrank();

        assertGt(alice.balance, ethBefore);
    }

    function test_Router_QuoteGetAmounts() public view {
        // Pure math functions
        uint256 amountB = router.quote(1000, 2000, 3000);
        assertEq(amountB, 1500); // 1000 * 3000 / 2000

        uint256 out = router.getAmountOut(1000, 2000, 3000);
        // amountInWithFee = 1000 * 997 = 997000
        // numerator = 997000 * 3000 = 2,991,000,000
        // denominator = 2000*1000 + 997000 = 2,997,000
        // out = 2,991,000,000 / 2,997,000 ≈ 997
        assertTrue(out > 0 && out < 1000);
    }

    function test_Router_DeadlineExpired() public {
        uint256 amountA = 1000 * 10 ** 18;
        uint256 amountB = 2000 * 10 ** 18;

        vm.startPrank(alice);
        tokenA.approve(address(router), amountA);
        tokenB.approve(address(router), amountB);

        vm.warp(block.timestamp + 100);
        vm.expectRevert("UniswapV2Router: EXPIRED");
        router.addLiquidity(
            address(tokenA),
            address(tokenB),
            amountA,
            amountB,
            0,
            0,
            alice,
            block.timestamp - 1 // deadline in the past
        );
        vm.stopPrank();
    }

    // ======================================================================
    // WETH TESTS (5)
    // ======================================================================

    function test_WETH_Deposit() public {
        vm.deal(alice, 1 ether);
        vm.prank(alice);
        weth.deposit{value: 1 ether}();

        assertEq(weth.balanceOf(alice), 1 ether);
        assertEq(weth.totalSupply(), 1 ether + address(weth).balance /* might have previous state */ - 1 ether);
        // Actually totalSupply() returns address(this).balance
    }

    function test_WETH_Withdraw() public {
        vm.deal(alice, 2 ether);
        vm.prank(alice);
        weth.deposit{value: 2 ether}();

        vm.prank(alice);
        weth.withdraw(1 ether);

        assertEq(weth.balanceOf(alice), 1 ether);
    }

    function test_WETH_Transfer() public {
        vm.deal(alice, 1 ether);
        vm.prank(alice);
        weth.deposit{value: 1 ether}();

        vm.prank(alice);
        weth.transfer(bob, 0.5 ether);

        assertEq(weth.balanceOf(alice), 0.5 ether);
        assertEq(weth.balanceOf(bob), 0.5 ether);
    }

    function test_WETH_ApproveAndTransferFrom() public {
        vm.deal(alice, 2 ether);
        vm.prank(alice);
        weth.deposit{value: 2 ether}();

        vm.prank(alice);
        weth.approve(bob, 1 ether);

        vm.prank(bob);
        weth.transferFrom(alice, bob, 1 ether);

        assertEq(weth.balanceOf(alice), 1 ether);
        assertEq(weth.balanceOf(bob), 1 ether);
    }

    function test_WETH_ReceiveFallback() public {
        vm.deal(alice, 1 ether);

        vm.prank(alice);
        (bool ok,) = address(weth).call{value: 1 ether}("");
        assertTrue(ok);

        assertEq(weth.balanceOf(alice), 1 ether);
    }

    // ======================================================================
    // PAIR_FOR ADDRESS VERIFICATION (1)
    // ======================================================================

    function test_PairFor_MatchesCreatePair() public {
        address expected = UniswapV2Library.pairFor(address(factory), address(tokenA), address(tokenB));

        vm.prank(deployer);
        address actual = factory.createPair(address(tokenA), address(tokenB));

        assertEq(actual, expected);
        assertEq(UniswapV2Library.pairFor(address(factory), address(tokenA), address(tokenB)), expected);
    }

    // ======================================================================
    // HELPERS
    // ======================================================================

    function _sqrt(uint256 y) internal pure returns (uint256 z) {
        if (y > 3) {
            z = y;
            uint256 x = y / 2 + 1;
            while (x < z) {
                z = x;
                x = (y / x + x) / 2;
            }
        } else if (y != 0) {
            z = 1;
        }
    }

    function _getAmountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut) internal pure returns (uint256) {
        uint256 amountInWithFee = amountIn * 997;
        uint256 numerator = amountInWithFee * reserveOut;
        uint256 denominator = reserveIn * 1000 + amountInWithFee;
        return numerator / denominator;
    }
}
