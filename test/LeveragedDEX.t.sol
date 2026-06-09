// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {LeveragedDEX} from "../src/dex/LeveragedDEX.sol";

contract LeveragedDEXTest is Test {
    LeveragedDEX public dex;

    address public owner = makeAddr("owner");
    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");
    address public carol = makeAddr("carol");

    event PositionOpened(
        uint256 indexed id,
        address indexed trader,
        bool isLong,
        uint256 size,
        uint256 collateral,
        uint256 entryNotional,
        uint256 leverage
    );
    event PositionClosed(uint256 indexed id, address indexed trader, uint256 pnlETH, uint256 returnedETH);
    event Liquidated(uint256 indexed id, address indexed liquidator, uint256 bonusETH);

    // Initial vAMM: 1000 ETH at $2000 = $2,000,000
    uint256 constant INIT_VBASE = 1000 ether;
    uint256 constant INIT_VQUOTE = 2_000_000 ether; // 2 million USD (18 decimals)

    function setUp() public {
        vm.label(owner, "owner");
        vm.label(alice, "alice");
        vm.label(bob, "bob");
        vm.label(carol, "carol");

        vm.prank(owner);
        dex = new LeveragedDEX(INIT_VBASE, INIT_VQUOTE);

        // Fund users with ETH
        vm.deal(alice, 100 ether);
        vm.deal(bob, 100 ether);
        vm.deal(carol, 100 ether);
    }

    // ======================================================================
    // DEPLOYMENT
    // ======================================================================

    function test_Deployment() public view {
        assertEq(dex.vBase(), INIT_VBASE);
        assertEq(dex.vQuote(), INIT_VQUOTE);
        assertEq(dex.getMarkPrice(), INIT_VQUOTE * 1e18 / INIT_VBASE); // $2000
        assertEq(dex.owner(), owner);
    }

    function test_Deployment_InitialPrice() public view {
        // 2,000,000 / 1000 = 2000 USD/ETH
        assertEq(dex.getMarkPrice(), 2000 ether);
    }

    // ======================================================================
    // OPEN LONG
    // ======================================================================

    function test_OpenLong_2x() public {
        uint256 margin = 1 ether;
        vm.prank(alice);
        uint256 id = dex.openPosition{value: margin}(2, true);

        (
            address trader,
            uint256 collateral,
            uint256 size,
            uint256 notional,
            uint256 leverage,
            bool isLong,
            bool isOpen
        ) = dex.positions(id);
        assertTrue(isOpen);
        assertTrue(isLong);
        assertEq(collateral, margin);
        assertEq(leverage, 2);
        assertGt(size, 0);
        assertEq(trader, alice);

        // vAMM price should have moved up slightly (we bought ETH)
        uint256 newPrice = dex.getMarkPrice();
        assertGt(newPrice, 2000 ether, "Price should go up on long open");
    }

    function test_OpenLong_10x() public {
        uint256 margin = 1 ether;
        vm.prank(alice);
        uint256 id = dex.openPosition{value: margin}(10, true);

        (, uint256 c2,,, uint256 lev2,, bool open2) = dex.positions(id);
        assertTrue(open2);
        assertEq(lev2, 10);
        assertEq(c2, margin);
    }

    // ======================================================================
    // OPEN SHORT
    // ======================================================================

    function test_OpenShort_2x() public {
        uint256 margin = 1 ether;
        vm.prank(alice);
        uint256 id = dex.openPosition{value: margin}(2, false);

        (,, uint256 sSize, uint256 sNotional, uint256 sLev, bool sIsLong, bool sOpen) = dex.positions(id);
        assertTrue(sOpen);
        assertFalse(sIsLong);
        assertEq(sSize, 2 ether); // margin * leverage == notional ETH borrowed
        assertGt(sNotional, 0);
        assertEq(sLev, 2);

        // vAMM price should have dropped (we sold ETH)
        uint256 newPrice = dex.getMarkPrice();
        assertLt(newPrice, INIT_VQUOTE * 1e18 / INIT_VBASE, "Price should go down on short open");
    }

    // ======================================================================
    // REVERT: INVALID INPUTS
    // ======================================================================

    function test_Revert_ZeroMargin() public {
        vm.prank(alice);
        vm.expectRevert("ZERO_MARGIN");
        dex.openPosition{value: 0}(2, true);
    }

    function test_Revert_TooLowLeverage() public {
        vm.prank(alice);
        vm.expectRevert("INVALID_LEVERAGE");
        dex.openPosition{value: 1 ether}(1, true);
    }

    function test_Revert_TooHighLeverage() public {
        vm.prank(alice);
        vm.expectRevert("INVALID_LEVERAGE");
        dex.openPosition{value: 1 ether}(11, true);
    }

    // ======================================================================
    // CLOSE LONG — PROFIT (price went up after opening)
    // ======================================================================

    function test_CloseLong_Profit() public {
        // Alice opens a long (buys ETH, price goes up)
        vm.prank(alice);
        uint256 id = dex.openPosition{value: 1 ether}(5, true);

        uint256 priceAfter = dex.getMarkPrice();
        assertGt(priceAfter, 2000 ether, "long should push price up");

        // Bob opens a long too — pushing price even higher
        vm.prank(bob);
        dex.openPosition{value: 10 ether}(10, true); // big long → price up more

        uint256 priceBeforeClose = dex.getMarkPrice();

        // Alice closes with profit
        uint256 aliceBefore = alice.balance;
        vm.prank(alice);
        uint256 returnedETH = dex.closePosition(id);

        // Should have profit (got back more ETH than margin)
        assertGt(alice.balance, aliceBefore - 1 ether + returnedETH);
    }

    // ======================================================================
    // CLOSE LONG — LOSS (price went down after opening)
    // ======================================================================

    function test_CloseLong_Loss() public {
        // Alice opens a long
        vm.prank(alice);
        uint256 id = dex.openPosition{value: 1 ether}(5, true);

        // Bob opens a massive short → pushes price down → Alice's long underwater
        vm.prank(bob);
        dex.openPosition{value: 50 ether}(10, false); // huge short

        // Alice closes at a loss
        vm.prank(alice);
        uint256 returnedETH = dex.closePosition(id);

        // Should get back less than 1 ETH (loss)
        assertLt(returnedETH, 1 ether);
    }

    // ======================================================================
    // CLOSE SHORT — PROFIT
    // ======================================================================

    function test_CloseShort_Profit() public {
        // Alice opens a short
        vm.prank(alice);
        uint256 id = dex.openPosition{value: 1 ether}(5, false);

        uint256 priceAfter = dex.getMarkPrice();
        assertLt(priceAfter, 2000 ether, "short should push price down");

        // Bob opens a bigger short → price down more → Alice's short appreciates
        vm.prank(bob);
        dex.openPosition{value: 50 ether}(10, false);

        // Alice closes with profit
        uint256 aliceBefore = alice.balance;
        vm.prank(alice);
        dex.closePosition(id);

        // Balance should have increased
        assertGt(alice.balance, aliceBefore);
    }

    // ======================================================================
    // CLOSE SHORT — LOSS
    // ======================================================================

    function test_CloseShort_Loss() public {
        // Alice opens a short
        vm.prank(alice);
        uint256 id = dex.openPosition{value: 1 ether}(5, false);

        // Bob opens a massive long → price up → Alice's short underwater
        vm.prank(bob);
        dex.openPosition{value: 30 ether}(10, true);

        // Alice closes at a loss (should get back less than her 1 ETH margin)
        vm.prank(alice);
        uint256 returnedETH = dex.closePosition(id);

        assertLt(returnedETH, 1 ether, "short should lose when price goes up");
    }

    // ======================================================================
    // REVERT: CLOSE
    // ======================================================================

    function test_Revert_CloseNotOwner() public {
        vm.prank(alice);
        uint256 id = dex.openPosition{value: 1 ether}(2, true);

        vm.prank(bob);
        vm.expectRevert("NOT_TRADER");
        dex.closePosition(id);
    }

    function test_Revert_CloseAlreadyClosed() public {
        vm.prank(alice);
        uint256 id = dex.openPosition{value: 1 ether}(2, true);

        vm.prank(alice);
        dex.closePosition(id);

        vm.prank(alice);
        vm.expectRevert("ALREADY_CLOSED");
        dex.closePosition(id);
    }

    // ======================================================================
    // LIQUIDATION
    // ======================================================================

    function test_Liquidate_UnderwaterLong() public {
        // Alice opens a long with 5x leverage (not too extreme)
        vm.prank(alice);
        uint256 aliceId = dex.openPosition{value: 1 ether}(5, true);

        // Bob opens a moderate short to push price down
        vm.prank(bob);
        dex.openPosition{value: 20 ether}(10, false);

        // Alice's long should be liquidatable
        assertTrue(dex.isLiquidatable(aliceId), "should be liquidatable");

        vm.prank(carol);
        dex.liquidate(aliceId);

        (,,,,,, bool isOpen) = dex.positions(aliceId);
        assertFalse(isOpen, "position should be closed after liquidation");
    }

    function test_Liquidate_BonusPaid() public {
        // Open a 10x long — more volatile, easier to liquidate
        vm.prank(alice);
        uint256 aliceId = dex.openPosition{value: 1 ether}(10, true);

        // Deep short to push price way down
        vm.prank(bob);
        dex.openPosition{value: 40 ether}(10, false);

        assertTrue(dex.isLiquidatable(aliceId), "should be liquidatable");

        vm.prank(carol);
        dex.liquidate(aliceId);

        // Position should be closed
        (address t,,,,, bool long, bool open2) = dex.positions(aliceId);
        assertFalse(open2);
    }

    function test_Liquidate_UnderwaterShort() public {
        // Alice opens a small short
        vm.prank(alice);
        uint256 aliceId = dex.openPosition{value: 0.2 ether}(10, false);

        // Bob opens a massive long to pump the price (~40% of vBase)
        vm.prank(bob);
        dex.openPosition{value: 30 ether}(10, true);

        // Alice's 10x short should now be liquidatable
        assertTrue(dex.isLiquidatable(aliceId), "short should be liquidatable");

        vm.prank(carol);
        dex.liquidate(aliceId);
    }

    function test_Revert_LiquidateHealthy() public {
        vm.prank(alice);
        uint256 id = dex.openPosition{value: 1 ether}(2, true);

        // Position is healthy (price barely moved)
        assertFalse(dex.isLiquidatable(id));

        vm.prank(carol);
        vm.expectRevert("HEALTHY");
        dex.liquidate(id);
    }

    function test_Revert_LiquidateAlreadyClosed() public {
        vm.prank(alice);
        uint256 id = dex.openPosition{value: 1 ether}(2, true);

        vm.prank(alice);
        dex.closePosition(id);

        vm.prank(carol);
        vm.expectRevert("ALREADY_CLOSED");
        dex.liquidate(id);
    }

    // ======================================================================
    // VIEW
    // ======================================================================

    function test_GetUserPositions() public {
        vm.prank(alice);
        uint256 id1 = dex.openPosition{value: 1 ether}(2, true);
        vm.prank(alice);
        uint256 id2 = dex.openPosition{value: 2 ether}(5, false);

        uint256[] memory positions = dex.getUserPositions(alice);
        assertEq(positions.length, 2);
        assertEq(positions[0], id1);
        assertEq(positions[1], id2);
    }

    function test_GetUnrealizedPnL_NoPosition() public view {
        assertEq(dex.getUnrealizedPnL(999), 0);
    }

    function test_GetUnrealizedPnL_Long() public {
        vm.prank(alice);
        uint256 id = dex.openPosition{value: 5 ether}(5, true);

        int256 pnlImmediate = dex.getUnrealizedPnL(id);
        // Immediately after opening alone, PnL is 0 (vAMM self-adjusts)
        assertEq(pnlImmediate, 0, "PnL should be 0 immediately after own trade");

        // Bob opens a big short → price moves against Alice's long → PnL changes
        vm.prank(bob);
        dex.openPosition{value: 30 ether}(10, false);

        int256 pnlAfter = dex.getUnrealizedPnL(id);
        // Long loses when price drops from short pressure
        assertLt(pnlAfter, 0, "long should have negative PnL after short pushes price down");
    }

    // ======================================================================
    // POSITION TOO LARGE (short)
    // ======================================================================

    function test_Revert_ShortTooLarge() public {
        // Try to short more than 90% of vBase
        vm.prank(alice);
        vm.expectRevert("POSITION_TOO_LARGE");
        dex.openPosition{value: 100 ether}(10, false); // 100 * 10 = 1000 ETH > 90% of 1000
    }

    // ======================================================================
    // MULTIPLE POSITIONS
    // ======================================================================

    function test_MultiplePositions_DifferentDirections() public {
        // Alice opens long, Bob opens short
        vm.prank(alice);
        uint256 longId = dex.openPosition{value: 1 ether}(5, true);

        vm.prank(bob);
        uint256 shortId = dex.openPosition{value: 2 ether}(3, false);

        (,,,,, bool lIsLong, bool lOpen) = dex.positions(longId);
        (,,,,, bool sIsLong2, bool sOpen2) = dex.positions(shortId);
        assertTrue(lOpen);
        assertTrue(sOpen2);
        assertTrue(lIsLong);
        assertFalse(sIsLong2);
    }
}
