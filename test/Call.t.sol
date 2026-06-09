// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {Caller, CalledContract, CalledLibrary} from "../src/utils/Call.sol";

contract CallerTest is Test {
    Caller public caller;
    CalledContract public calledContract;

    function setUp() public {
        caller = new Caller();
        calledContract = new CalledContract();
    }

    // =============================================================
    // CalledContract
    // =============================================================

    function test_CalledContract_ReturnsCorrectSender() public {
        (address sender, , address from) = calledContract.calledFunction();
        assertEq(sender, address(this));
        assertEq(from, address(calledContract));
    }

    function test_CalledContract_ReturnsTxOrigin() public {
        ( , address origin, ) = calledContract.calledFunction();
        assertEq(origin, tx.origin);
    }

    function test_CalledContract_EmitsCallEvent() public {
        vm.expectEmit(true, true, false, true);
        emit CalledContract.callEvent(address(this), tx.origin, address(calledContract));
        calledContract.calledFunction();
    }

    // =============================================================
    // Caller.makeCalls
    // =============================================================

    function test_Caller_MakeCalls_DoesNotRevert() public {
        // makeCalls 内部依次执行: normal call → low-level call → delegatecall → library call
        caller.makeCalls(calledContract);
    }

    function test_Caller_MakeCalls_ThroughPrank() public {
        vm.prank(address(this));
        caller.makeCalls(calledContract);
    }

    // =============================================================
    // Library — msg.sender 和 address(this) 在 library 内部是调用方的上下文
    // =============================================================

    function test_CalledLibrary_ReturnsCallersContext() public view {
        (address sender, address origin, address from) = CalledLibrary.calledFunction();
        // 测试环境中的默认 msg.sender（DefaultSender）
        assertEq(sender, msg.sender);
        assertEq(origin, tx.origin);
        // library 内部 address(this) == 调用合约（即本测试合约）
        assertEq(from, address(this));
    }
}
