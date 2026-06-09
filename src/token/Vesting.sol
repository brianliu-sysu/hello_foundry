// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.26;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract Vesting is Ownable {
    using SafeERC20 for IERC20;

    address public beneficiary;
    IERC20 public token;
    uint256 public totalVestingAmount;
    uint256 public deployTime;
    uint256 public cliffDuration;
    uint256 public unlockPeriod;
    uint256 public totalReleased;

    uint256 public constant MAX_RELEASES = 24;

    error InCliffTimePeriod();
    error NotReachedReleaseTime();
    error NothingToRelease();
    error ReleaseFailed();
    error MaxReleasesReached();

    event Released(address indexed beneficiary, uint256 amount);

    constructor(
        address token_,
        address beneficiary_,
        uint256 totalVestingAmount_,
        uint256 cliffDuration_,
        uint256 unlockPeriod_
    ) Ownable(msg.sender) {
        require(token_ != address(0), "Invalid token address");
        require(beneficiary_ != address(0), "Invalid beneficiary address");
        require(totalVestingAmount_ > 0, "Invalid vesting amount");
        require(cliffDuration_ > 0, "Invalid cliff duration");
        require(unlockPeriod_ > 0, "Invalid unlock period");

        token = IERC20(token_);
        beneficiary = beneficiary_;
        totalVestingAmount = totalVestingAmount_;
        deployTime = block.timestamp;
        cliffDuration = cliffDuration_;
        unlockPeriod = unlockPeriod_;
    }

    /// @notice Release vested tokens to the beneficiary.
    ///         Supports multi-period catch-up: if multiple periods have passed,
    ///         all missed releases are claimed at once.
    function release() external {
        uint256 elapsedTime = block.timestamp - deployTime;

        // 1. Still in cliff — nothing is vested yet
        if (elapsedTime < cliffDuration) {
            revert InCliffTimePeriod();
        }

        // 2. How many full unlock periods have passed since the cliff ended
        uint256 periodsSinceCliff = (elapsedTime - cliffDuration) / unlockPeriod;
        if (periodsSinceCliff == 0) {
            revert NotReachedReleaseTime();
        }

        // 3. Cap at 24 monthly releases
        uint256 releasablePeriods = periodsSinceCliff;
        if (releasablePeriods > MAX_RELEASES) {
            releasablePeriods = MAX_RELEASES;
        }

        // 4. Total amount that should have been vested so far (linear, 1/24 per period)
        uint256 vestedAmount = (totalVestingAmount * releasablePeriods) / MAX_RELEASES;

        // 5. Subtract what was already released
        uint256 releasableAmount = vestedAmount - totalReleased;
        if (releasableAmount == 0) {
            revert NothingToRelease();
        }

        // 6. Transfer and update state before external call
        totalReleased += releasableAmount;
        token.safeTransfer(beneficiary, releasableAmount);

        emit Released(beneficiary, releasableAmount);
    }

    /// @notice Owner can withdraw tokens that exceed what is still owed to the beneficiary.
    ///         Protects beneficiary: unvested + unreleased tokens cannot be taken.
    function withdraw() external onlyOwner {
        uint256 balance = token.balanceOf(address(this));

        // Calculate the maximum amount that could still need to be paid out
        uint256 remainingVested = totalVestingAmount - totalReleased;

        // Only withdraw the surplus beyond what is still owed
        uint256 surplus = balance > remainingVested ? balance - remainingVested : 0;
        require(surplus > 0, "No surplus to withdraw");

        token.safeTransfer(owner(), surplus);
    }
}
