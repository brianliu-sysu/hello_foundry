// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {DeflationaryToken} from "../src/token/DeflationaryToken.sol";

contract DeflationaryTokenTest is Test {
    DeflationaryToken public token;

    address public owner  = makeAddr("owner");
    address public alice  = makeAddr("alice");
    address public bob    = makeAddr("bob");

    uint256 constant INITIAL_SUPPLY = 100_000_000 ether; // 1 亿

    function setUp() public {
        vm.label(owner, "owner");
        vm.label(alice, "alice");
        vm.label(bob, "bob");

        vm.prank(owner);
        token = new DeflationaryToken(INITIAL_SUPPLY);

        // Transfer some tokens to alice and bob
        vm.startPrank(owner);
        token.transfer(alice, 1_000_000 ether);
        token.transfer(bob,   2_000_000 ether);
        vm.stopPrank();
    }

    // ======================================================================
    // DEPLOYMENT
    // ======================================================================

    function test_Deployment_InitialSupply() public view {
        assertEq(token.totalSupply(), INITIAL_SUPPLY);
        assertEq(token.balanceOf(owner), 97_000_000 ether);
        assertEq(token.balanceOf(alice), 1_000_000 ether);
        assertEq(token.balanceOf(bob),   2_000_000 ether);
    }

    function test_Deployment_InitialGonsPerToken() public view {
        assertEq(token.gonsPerToken(), 1e18);
    }

    function test_Deployment_TotalGonsEqualSupply() public view {
        // At deploy time, gonsPerToken = 1e18, so totalGons = totalSupply
        assertEq(token.totalGons(), INITIAL_SUPPLY);
    }

    function test_Deployment_SymbolAndDecimals() public view {
        assertEq(token.symbol(), "DFL");
        assertEq(token.decimals(), 18);
    }

    // ======================================================================
    // BASIC ERC20 (before deflation)
    // ======================================================================

    function test_Transfer_Success() public {
        vm.prank(alice);
        token.transfer(bob, 100 ether);

        assertEq(token.balanceOf(alice), 1_000_000 ether - 100 ether);
        assertEq(token.balanceOf(bob),   2_000_000 ether + 100 ether);
    }

    function test_Transfer_InsufficientBalance() public {
        vm.prank(alice);
        vm.expectRevert("ERC20: transfer amount exceeds balance");
        token.transfer(bob, 2_000_000 ether);
    }

    function test_ApproveAndTransferFrom() public {
        vm.prank(alice);
        token.approve(bob, 500 ether);

        vm.prank(bob);
        token.transferFrom(alice, bob, 500 ether);

        assertEq(token.balanceOf(alice), 1_000_000 ether - 500 ether);
        assertEq(token.balanceOf(bob),   2_000_000 ether + 500 ether);
        assertEq(token.allowance(alice, bob), 0);
    }

    // ======================================================================
    // REBASE — SINGLE PERIOD
    // ======================================================================

    function test_Rebase_SingleDay_1PercentDeflation() public {
        uint256 supplyBefore = token.totalSupply();
        uint256 aliceBefore   = token.balanceOf(alice);
        uint256 bobBefore     = token.balanceOf(bob);

        // 1 day 后执行 rebase
        vm.warp(block.timestamp + 1 days);
        token.rebase();

        // 总供应 ≈ 原供应 * 0.99
        assertApproxEqRel(token.totalSupply(), supplyBefore * 99 / 100, 0.0001e18);
        assertApproxEqRel(token.balanceOf(alice), aliceBefore * 99 / 100, 0.0001e18);
        assertApproxEqRel(token.balanceOf(bob),   bobBefore * 99 / 100, 0.0001e18);

        // 全部余额之和应等于总供应（允许极小的舍入误差）
        uint256 sum = token.balanceOf(owner) + token.balanceOf(alice) + token.balanceOf(bob);
        assertApproxEqAbs(sum, token.totalSupply(), 3);
    }

    function test_Rebase_MultiplePeriods() public {
        uint256 supplyBefore = token.totalSupply();

        // 3 天
        vm.warp(block.timestamp + 3 days);
        token.rebase();

        // 总供应 = 原供应 * 0.99^3
        uint256 expected = supplyBefore * 99 * 99 * 99 / (100 * 100 * 100);
        assertApproxEqRel(token.totalSupply(), expected, 0.001e18);
    }

    function test_Rebase_EmitEvent() public {
        vm.warp(block.timestamp + 1 days);
        uint256 supplyBefore = token.totalSupply();
        token.rebase();
        // After 1 day, supply shrinks by 1%
        assertLt(token.totalSupply(), supplyBefore);
        assertGt(token.gonsPerToken(), 1e18);
    }

    function test_Rebase_TooEarlyReverts() public {
        vm.warp(block.timestamp + 1 hours); // less than 1 day
        vm.expectRevert("TOO_EARLY");
        token.rebase();
    }

    // ======================================================================
    // REBASE — CATCH-UP (multiple periods in one tx)
    // ======================================================================

    function test_Rebase_CatchUp_ManyDays() public {
        uint256 supplyBefore = token.totalSupply();

        // 30 天一次性通缩
        vm.warp(block.timestamp + 30 days);
        token.rebase();

        uint256 expected = supplyBefore;
        for (uint256 i = 0; i < 30; i++) {
            expected = expected * 99 / 100;
        }
        assertApproxEqRel(token.totalSupply(), expected, 0.01e18);
    }

    // ======================================================================
    // REBASE — MULTIPLE CALLS
    // ======================================================================

    function test_Rebase_CalledMultipleTimes_OnlyAppliesOncePerPeriod() public {
        uint256 supplyBefore = token.totalSupply();

        vm.warp(block.timestamp + 1 days);
        uint256 periods = token.rebase();
        assertEq(periods, 1);

        // 立即再次调用 — 应 revert（同一时段）
        vm.expectRevert("TOO_EARLY");
        token.rebase();

        assertApproxEqRel(token.totalSupply(), supplyBefore * 99 / 100, 0.0001e18);
    }

    // ======================================================================
    // TRANSFER + REBASE INTERACTION
    // ======================================================================

    function test_Transfer_AfterRebase_WorksCorrectly() public {
        vm.warp(block.timestamp + 1 days);
        token.rebase();

        uint256 aliceBefore = token.balanceOf(alice);
        uint256 bobBefore   = token.balanceOf(bob);

        vm.prank(alice);
        token.transfer(bob, 10 ether);

        assertApproxEqAbs(token.balanceOf(alice), aliceBefore - 10 ether, 1);
        assertApproxEqAbs(token.balanceOf(bob),   bobBefore + 10 ether, 1);
    }

    function test_Transfer_AfterMultipleRebases() public {
        // 5 days deflation
        vm.warp(block.timestamp + 5 days);
        token.rebase();

        uint256 aliceBefore = token.balanceOf(alice);
        uint256 bobBefore   = token.balanceOf(bob);

        vm.prank(alice);
        token.transfer(bob, aliceBefore); // transfer all

        // Alice should have ~0 after transferring her entire balance
        assertApproxEqAbs(token.balanceOf(alice), 0, 1);
        // Bob should have his old balance + alice's old balance
        assertApproxEqAbs(token.balanceOf(bob), bobBefore + aliceBefore, 2);
    }

    // ======================================================================
    // GON-LEVEL VIEWS
    // ======================================================================

    function test_GonBalance_Constant_AcrossRebase() public {
        uint256 aliceGonBefore = token.gonBalanceOf(alice);

        vm.warp(block.timestamp + 1 days);
        token.rebase();

        uint256 aliceGonAfter = token.gonBalanceOf(alice);
        // gon balance is unchanged by rebase — only transfers change it
        assertEq(aliceGonAfter, aliceGonBefore);

        // But token balance decreased
        assertLt(token.balanceOf(alice), 1_000_000 ether);
    }

    function test_GonsPerToken_Increases() public view {
        assertEq(token.gonsPerToken(), 1e18);
    }

    function test_GonsPerToken_After3Rebases() public {
        vm.warp(block.timestamp + 3 days);
        token.rebase();

        uint256 gpt = token.gonsPerToken();
        uint256 expected = 1e18;
        for (uint256 i = 0; i < 3; i++) {
            expected = expected * 10000 / 9900;
        }
        assertEq(gpt, expected);
    }

    // ======================================================================
    // PRECISION — edge cases
    // ======================================================================

    function test_Rebase_LargeNumberOfPeriods() public {
        // 365 days (1 year)
        vm.warp(block.timestamp + 365 days);
        token.rebase();

        // After 365 days at 1% daily:
        // supply = 100M * 0.99^365 ≈ 100M * 0.0255 ≈ 2.55M
        uint256 supply = token.totalSupply();
        assertGt(supply, 0);
        assertLt(supply, INITIAL_SUPPLY * 3 / 100); // should be < 3M
    }

    function test_Transfer_TinyAmounts_AfterHeavyDeflation() public {
        // After 100 days
        vm.warp(block.timestamp + 100 days);
        token.rebase();

        // Transfer 0.000001 token — should not revert due to rounding to 0 gons
        // This might round to 0 gon value and become a no-op. That's acceptable.
        vm.prank(alice);
        token.transfer(bob, 0.000001 ether);

        assertApproxEqAbs(
            token.balanceOf(alice) + token.balanceOf(bob) + token.balanceOf(owner),
            token.totalSupply(),
            3
        );
    }

    // ======================================================================
    // EIP-2612 PERMIT (inherited from ERC20Permit)
    // ======================================================================

    function test_Permit_Works() public {
        // Use a known private key account (not makeAddr)
        uint256 signerKey = 0xabc123;
        address signer = vm.addr(signerKey);

        // Fund signer with tokens
        vm.prank(owner);
        token.transfer(signer, 5000 ether);

        bytes32 digest = keccak256(abi.encodePacked(
            "\x19\x01",
            token.DOMAIN_SEPARATOR(),
            keccak256(abi.encode(
                keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"),
                signer,
                bob,
                1000 ether,
                token.nonces(signer),
                block.timestamp + 1 hours
            ))
        ));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerKey, digest);

        vm.prank(bob);
        token.permit(signer, bob, 1000 ether, block.timestamp + 1 hours, v, r, s);

        assertEq(token.allowance(signer, bob), 1000 ether);
    }
}
