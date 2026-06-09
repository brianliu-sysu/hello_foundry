// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {Test, console} from "forge-std/Test.sol";
import {BrianICOToken} from "../src/token/BrianICOToken.sol";
import {Vesting} from "../src/token/Vesting.sol";

contract TestVesting is Test {
    Vesting public vesting;
    BrianICOToken public token;

    address public owner = makeAddr("owner");
    address public beneficiary = makeAddr("beneficiary");
    address public stranger = makeAddr("stranger");

    uint256 constant TOTAL_VESTING = 1_000_000 * 1e18; // 1M tokens (18 decimals)
    uint256 constant CLIFF_DURATION = 12 * 30 days; // ~360 days
    uint256 constant UNLOCK_PERIOD = 30 days;

    event Released(address indexed beneficiary, uint256 amount);

    /// @notice Helper: compute vested amount for N completed periods.
    ///          Uses same formula as the contract: (totalVestingAmount * periods) / 24
    function vestedForPeriods(uint256 periods) internal pure returns (uint256) {
        return (TOTAL_VESTING * periods) / 24;
    }

    /// -----------------------------------------------------------------------
    /// Setup
    /// -----------------------------------------------------------------------

    function setUp() public {
        // Owner deploys the ERC20 token with 3M supply (leaves room for extra tests)
        vm.prank(owner);
        token = new BrianICOToken(TOTAL_VESTING * 3);

        // Owner deploys the vesting contract
        vm.prank(owner);
        vesting = new Vesting(address(token), beneficiary, TOTAL_VESTING, CLIFF_DURATION, UNLOCK_PERIOD);

        // Transfer 1M tokens into the vesting contract (模拟"创建合约后打入100万token")
        vm.prank(owner);
        token.transfer(address(vesting), TOTAL_VESTING);

        // Give stranger some tokens for surplus-deposit tests
        vm.prank(owner);
        token.transfer(stranger, 10_000 * 1e18);
    }

    /// -----------------------------------------------------------------------
    /// Deployment
    /// -----------------------------------------------------------------------

    function test_Deployment_SetsCorrectParams() public view {
        assertEq(vesting.beneficiary(), beneficiary);
        assertEq(address(vesting.token()), address(token));
        assertEq(vesting.totalVestingAmount(), TOTAL_VESTING);
        assertEq(vesting.cliffDuration(), CLIFF_DURATION);
        assertEq(vesting.unlockPeriod(), UNLOCK_PERIOD);
        assertEq(vesting.totalReleased(), 0);
        assertEq(vesting.owner(), owner);
        assertEq(token.balanceOf(address(vesting)), TOTAL_VESTING);
    }

    function test_Deployment_RevertsOn_ZeroTokenAddress() public {
        vm.expectRevert("Invalid token address");
        new Vesting(address(0), beneficiary, TOTAL_VESTING, CLIFF_DURATION, UNLOCK_PERIOD);
    }

    function test_Deployment_RevertsOn_ZeroBeneficiary() public {
        vm.expectRevert("Invalid beneficiary address");
        new Vesting(address(token), address(0), TOTAL_VESTING, CLIFF_DURATION, UNLOCK_PERIOD);
    }

    function test_Deployment_RevertsOn_ZeroVestingAmount() public {
        vm.expectRevert("Invalid vesting amount");
        new Vesting(address(token), beneficiary, 0, CLIFF_DURATION, UNLOCK_PERIOD);
    }

    function test_Deployment_RevertsOn_ZeroCliffDuration() public {
        vm.expectRevert("Invalid cliff duration");
        new Vesting(address(token), beneficiary, TOTAL_VESTING, 0, UNLOCK_PERIOD);
    }

    function test_Deployment_RevertsOn_ZeroUnlockPeriod() public {
        vm.expectRevert("Invalid unlock period");
        new Vesting(address(token), beneficiary, TOTAL_VESTING, CLIFF_DURATION, 0);
    }

    /// -----------------------------------------------------------------------
    /// Cliff period
    /// -----------------------------------------------------------------------

    function test_Release_RevertsInCliffPeriod() public {
        // At deploy time (elapsed = 0) — inside cliff
        vm.expectRevert(Vesting.InCliffTimePeriod.selector);
        vesting.release();

        // 1 second before cliff ends
        vm.warp(block.timestamp + CLIFF_DURATION - 1);
        vm.expectRevert(Vesting.InCliffTimePeriod.selector);
        vesting.release();
    }

    function test_Release_RevertsAtExactCliffEnd_NoPeriodPassed() public {
        // At exact cliff end, 0 full unlock periods have passed since cliff
        vm.warp(block.timestamp + CLIFF_DURATION);
        vm.expectRevert(Vesting.NotReachedReleaseTime.selector);
        vesting.release();
    }

    /// -----------------------------------------------------------------------
    /// Linear vesting — single period
    /// -----------------------------------------------------------------------

    function test_Release_FirstPeriod() public {
        // 1 full period after cliff ends
        vm.warp(block.timestamp + CLIFF_DURATION + UNLOCK_PERIOD);

        uint256 beneficiaryBefore = token.balanceOf(beneficiary);
        uint256 expected = vestedForPeriods(1); // (1M * 1) / 24

        vm.expectEmit(true, true, false, true);
        emit Released(beneficiary, expected);
        vesting.release();

        assertEq(token.balanceOf(beneficiary), beneficiaryBefore + expected);
        assertEq(vesting.totalReleased(), expected);
    }

    function test_Release_SecondPeriod() public {
        // Period 1
        vm.warp(block.timestamp + CLIFF_DURATION + UNLOCK_PERIOD);
        vesting.release();

        // Period 2
        vm.warp(block.timestamp + UNLOCK_PERIOD);
        vesting.release();

        uint256 total2 = vestedForPeriods(2);
        assertEq(vesting.totalReleased(), total2);
        assertEq(token.balanceOf(beneficiary), total2);
    }

    /// -----------------------------------------------------------------------
    /// Multi-period catch-up
    /// -----------------------------------------------------------------------

    function test_Release_MultiPeriodCatchUp() public {
        // Skip first 3 periods entirely, claim all at once
        vm.warp(block.timestamp + CLIFF_DURATION + UNLOCK_PERIOD * 3);
        uint256 expected = vestedForPeriods(3);

        vm.expectEmit(true, true, false, true);
        emit Released(beneficiary, expected);
        vesting.release();

        assertEq(token.balanceOf(beneficiary), expected);
        assertEq(vesting.totalReleased(), expected);
    }

    function test_Release_ClaimSomeThenCatchUp() public {
        // Claim period 1
        vm.warp(block.timestamp + CLIFF_DURATION + UNLOCK_PERIOD);
        vesting.release();
        uint256 afterFirst = vestedForPeriods(1);
        assertEq(vesting.totalReleased(), afterFirst);

        // Skip to period 5 (periods 2,3,4,5 cumulative)
        vm.warp(block.timestamp + UNLOCK_PERIOD * 4);
        vesting.release();

        uint256 total5 = vestedForPeriods(5);
        assertEq(vesting.totalReleased(), total5);
        assertEq(token.balanceOf(beneficiary), total5);
    }

    /// -----------------------------------------------------------------------
    /// Full vesting (24/24)
    /// -----------------------------------------------------------------------

    function test_Release_FullVesting_All24Periods() public {
        vm.warp(block.timestamp + CLIFF_DURATION + UNLOCK_PERIOD * 24);
        vesting.release();

        assertEq(token.balanceOf(beneficiary), TOTAL_VESTING);
        assertEq(vesting.totalReleased(), TOTAL_VESTING);
        assertEq(token.balanceOf(address(vesting)), 0);
    }

    function test_Release_Beyond24Periods_NothingToRelease() public {
        // Fully vest first
        vm.warp(block.timestamp + CLIFF_DURATION + UNLOCK_PERIOD * 24);
        vesting.release();

        // Advance further — nothing new to release
        vm.warp(block.timestamp + UNLOCK_PERIOD * 10);
        vm.expectRevert(Vesting.NothingToRelease.selector);
        vesting.release();
    }

    function test_Release_AfterFullVesting_TotalReleasedUnchanged() public {
        vm.warp(block.timestamp + CLIFF_DURATION + UNLOCK_PERIOD * 24);
        vesting.release();

        uint256 releasedBefore = vesting.totalReleased();

        vm.warp(block.timestamp + UNLOCK_PERIOD * 10);
        vm.expectRevert(Vesting.NothingToRelease.selector);
        vesting.release();

        assertEq(vesting.totalReleased(), releasedBefore);
    }

    /// -----------------------------------------------------------------------
    /// Nothing to release (same period called twice, or mid-period)
    /// -----------------------------------------------------------------------

    function test_Release_RevertsWhenNothingNew() public {
        vm.warp(block.timestamp + CLIFF_DURATION + UNLOCK_PERIOD);
        vesting.release();

        // Same timestamp — no new period has passed
        vm.expectRevert(Vesting.NothingToRelease.selector);
        vesting.release();
    }

    function test_Release_RevertsWhenPartiallyThroughPeriod() public {
        vm.warp(block.timestamp + CLIFF_DURATION + UNLOCK_PERIOD);
        vesting.release();

        // Move forward but not enough for next full period
        vm.warp(block.timestamp + UNLOCK_PERIOD - 1);
        vm.expectRevert(Vesting.NothingToRelease.selector);
        vesting.release();
    }

    /// -----------------------------------------------------------------------
    /// Anyone can call release (not restricted to beneficiary/owner)
    /// -----------------------------------------------------------------------

    function test_Release_CallerReceivesNothing_TokensGoToBeneficiary() public {
        // 2 periods passed
        vm.warp(block.timestamp + CLIFF_DURATION + UNLOCK_PERIOD * 2);

        uint256 strangerBefore = token.balanceOf(stranger);

        vm.prank(stranger);
        vesting.release();

        uint256 total2 = vestedForPeriods(2);

        // Stranger balance unchanged; beneficiary received tokens
        assertEq(token.balanceOf(stranger), strangerBefore);
        assertEq(token.balanceOf(beneficiary), total2);
    }

    /// -----------------------------------------------------------------------
    /// withdraw() — owner
    /// -----------------------------------------------------------------------

    function test_Withdraw_OwnerCanWithdrawSurplus() public {
        // Send extra tokens into the vesting contract (simulating accidental transfer)
        uint256 extraAmount = 1000 * 1e18;
        vm.prank(stranger);
        token.transfer(address(vesting), extraAmount);

        // No vesting has happened yet, so full TOTAL_VESTING is still owed
        // surplus = (TOTAL_VESTING + extraAmount) - (TOTAL_VESTING - 0) = extraAmount
        uint256 ownerBefore = token.balanceOf(owner);

        vm.prank(owner);
        vesting.withdraw();

        assertEq(token.balanceOf(owner), ownerBefore + extraAmount);
    }

    function test_Withdraw_CannotWithdrawVestedTokens() public {
        // 6 periods vested
        vm.warp(block.timestamp + CLIFF_DURATION + UNLOCK_PERIOD * 6);
        vesting.release();

        uint256 released = vestedForPeriods(6);
        uint256 remaining = TOTAL_VESTING - released; // still owed to beneficiary

        // Contract has exactly `remaining` tokens — no surplus
        assertEq(token.balanceOf(address(vesting)), remaining);

        vm.prank(owner);
        vm.expectRevert("No surplus to withdraw");
        vesting.withdraw();
    }

    function test_Withdraw_AfterPartialVesting_OnlySurplus() public {
        // 6 periods vested
        vm.warp(block.timestamp + CLIFF_DURATION + UNLOCK_PERIOD * 6);
        vesting.release();

        // Send extra tokens
        uint256 extraAmount = 500 * 1e18;
        vm.prank(stranger);
        token.transfer(address(vesting), extraAmount);

        uint256 ownerBefore = token.balanceOf(owner);
        vm.prank(owner);
        vesting.withdraw();

        assertEq(token.balanceOf(owner), ownerBefore + extraAmount);
    }

    function test_Withdraw_RevertsWhenNoSurplus() public {
        // No extra tokens — only the exact vesting amount
        vm.prank(owner);
        vm.expectRevert("No surplus to withdraw");
        vesting.withdraw();
    }

    function test_Withdraw_RevertsForNonOwner() public {
        vm.prank(stranger);
        vm.expectRevert(); // Ownable: caller is not the owner
        vesting.withdraw();
    }

    function test_Withdraw_FullyVestedNoSurplus() public {
        vm.warp(block.timestamp + CLIFF_DURATION + UNLOCK_PERIOD * 24);
        vesting.release();

        // Contract empty, nothing to withdraw
        vm.prank(owner);
        vm.expectRevert("No surplus to withdraw");
        vesting.withdraw();
    }

    /// -----------------------------------------------------------------------
    /// Precision / rounding
    /// -----------------------------------------------------------------------

    function test_Release_HandlesNonDivisibleAmount() public {
        // Use an amount not cleanly divisible by 24
        uint256 oddAmount = 1_000_000 * 1e18 + 23; // remainder 23 wei
        vm.prank(owner);
        Vesting vesting2 = new Vesting(address(token), beneficiary, oddAmount, CLIFF_DURATION, UNLOCK_PERIOD);
        vm.prank(owner);
        token.transfer(address(vesting2), oddAmount);

        // Release just 1 period — precision loss shows here
        vm.warp(block.timestamp + CLIFF_DURATION + UNLOCK_PERIOD);
        vesting2.release();

        // 1-period vested = floor(oddAmount / 24)
        uint256 expected1 = oddAmount / 24;
        assertEq(vesting2.totalReleased(), expected1);

        // Release remaining 23 periods
        vm.warp(block.timestamp + UNLOCK_PERIOD * 23);
        vesting2.release();

        // (oddAmount * 24) / 24 = oddAmount exactly — no dust at full vesting
        assertEq(vesting2.totalReleased(), oddAmount);
        assertEq(token.balanceOf(address(vesting2)), 0);
    }

    /// -----------------------------------------------------------------------
    /// Custom cliff / unlock period
    /// -----------------------------------------------------------------------

    function test_Release_CustomShortCliff() public {
        uint256 shortCliff = 7 days;
        uint256 shortPeriod = 1 days;

        vm.prank(owner);
        Vesting vestingShort = new Vesting(address(token), beneficiary, TOTAL_VESTING, shortCliff, shortPeriod);
        vm.prank(owner);
        token.transfer(address(vestingShort), TOTAL_VESTING);

        uint256 deployAt = vestingShort.deployTime();

        // Before cliff
        vm.warp(deployAt + shortCliff - 1);
        vm.expectRevert(Vesting.InCliffTimePeriod.selector);
        vestingShort.release();

        // After cliff + 1 period
        vm.warp(deployAt + shortCliff + shortPeriod);
        vestingShort.release();

        uint256 expected = vestedForPeriods(1);
        assertEq(vestingShort.totalReleased(), expected);
    }

    /// -----------------------------------------------------------------------
    /// ETH handling — Vesting has no receive(), so ETH transfers fail
    /// -----------------------------------------------------------------------

    function test_CannotSendETH() public {
        vm.deal(stranger, 1 ether);
        vm.prank(stranger);
        // Low-level call to a contract without receive() — internal revert caught
        (bool ok,) = address(vesting).call{value: 1 ether}("");
        assertFalse(ok);
        assertEq(address(vesting).balance, 0);
    }
}
