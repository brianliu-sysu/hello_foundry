// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {Owner, Pausable, Faucet} from "../src/Faucet.sol";

contract OwnerTest is Test {
    Owner public ownerContract;

    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");

    function setUp() public {
        ownerContract = new Owner();
    }

    function test_Owner_DeployerIsOwner() public view {
        assertEq(ownerContract.owner(), address(this));
    }

    function test_Owner_ChangeOwner_Succeeds() public {
        ownerContract.changeOwner(alice);
        assertEq(ownerContract.owner(), alice);
    }

    function test_Owner_ChangeOwner_RevertsWhenNotOwner() public {
        vm.prank(alice);
        vm.expectRevert("Only owner can call this function");
        ownerContract.changeOwner(bob);
    }

    function testFuzz_Owner_ChangeOwner_SucceedsForAnyAddress(address newOwner) public {
        vm.assume(newOwner != address(0));
        ownerContract.changeOwner(newOwner);
        assertEq(ownerContract.owner(), newOwner);
    }
}

contract PausableTest is Test {
    Pausable public pausable;

    address public alice = makeAddr("alice");

    function setUp() public {
        pausable = new Pausable();
    }

    function test_Pausable_InitiallyUnpaused() public view {
        assertFalse(pausable.paused());
    }

    function test_Pausable_Pause_SucceedsByOwner() public {
        pausable.pause();
        assertTrue(pausable.paused());
    }

    function test_Pausable_Pause_RevertsWhenNotOwner() public {
        vm.prank(alice);
        vm.expectRevert("Only owner can call this function");
        pausable.pause();
    }

    function test_Pausable_Unpause_SucceedsByOwner() public {
        pausable.pause();
        pausable.unpause();
        assertFalse(pausable.paused());
    }

    function test_Pausable_Unpause_RevertsWhenNotOwner() public {
        vm.prank(alice);
        vm.expectRevert("Only owner can call this function");
        pausable.unpause();
    }
}

contract FaucetTest is Test {
    Faucet public faucet;

    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");

    // withdraw 上限为 1_000_000_000_000 wei
    uint256 constant MAX_WITHDRAW = 1_000_000_000_000;

    function setUp() public {
        vm.deal(address(this), 10 ether);
        faucet = new Faucet{value: 1 ether}();
    }

    // =============================================================
    // 部署
    // =============================================================

    function test_Faucet_DeployerIsOwner() public view {
        assertEq(faucet.owner(), address(this));
    }

    function test_Faucet_InitialBalance() public view {
        assertEq(address(faucet).balance, 1 ether);
    }

    function test_Faucet_InitiallyUnpaused() public view {
        assertFalse(faucet.paused());
    }

    // =============================================================
    // withdraw（限额 1_000_000_000_000 wei）
    // =============================================================

    function test_Faucet_Withdraw_SendsEther() public {
        uint256 bobBalanceBefore = bob.balance;
        uint256 amount = MAX_WITHDRAW;

        faucet.withdraw(amount, payable(bob));

        assertEq(bob.balance, bobBalanceBefore + amount);
        assertEq(address(faucet).balance, 1 ether - amount);
    }

    function test_Faucet_Withdraw_EmitsWithdrawalEvent() public {
        uint256 amount = 500;

        vm.expectEmit(true, true, false, true);
        emit Faucet.Withdrawal(bob, amount);

        faucet.withdraw(amount, payable(bob));
    }

    function testFuzz_Faucet_Withdraw_Amount(
        uint256 amount
    ) public {
        amount = bound(amount, 1, MAX_WITHDRAW);

        uint256 bobBalanceBefore = bob.balance;
        faucet.withdraw(amount, payable(bob));
        assertEq(bob.balance, bobBalanceBefore + amount);
    }

    function test_Faucet_Withdraw_RevertsWhenAmountTooLarge() public {
        uint256 largeAmount = MAX_WITHDRAW + 1;

        vm.expectRevert();
        faucet.withdraw(largeAmount, payable(bob));
    }

    function test_Faucet_Withdraw_RevertsWhenPaused() public {
        faucet.pause();

        vm.expectRevert("Contract is paused");
        faucet.withdraw(100, payable(bob));
    }

    // =============================================================
    // pause（继承自 Pausable）
    // =============================================================

    function test_Faucet_Pause_Succeeds() public {
        faucet.pause();
        assertTrue(faucet.paused());
    }

    function test_Faucet_Pause_RevertsWhenNotOwner() public {
        vm.prank(alice);
        vm.expectRevert("Only owner can call this function");
        faucet.pause();
    }

    function test_Faucet_Unpause_AlwaysReverts() public {
        // Faucet 重写了 unpause，始终 revert
        vm.expectRevert("Faucet is not paused");
        faucet.unpause();
    }

    // =============================================================
    // receive / deposit
    // =============================================================

    function test_Faucet_Receive_EmitsDeposit() public {
        vm.deal(alice, 0.5 ether);

        vm.expectEmit(true, false, false, true);
        emit Faucet.Deposit(alice, 0.5 ether);

        vm.prank(alice);
        (bool ok, ) = address(faucet).call{value: 0.5 ether}("");
        assertTrue(ok);
    }

    function test_Faucet_Fallback_AcceptsEtherWithData() public {
        vm.deal(alice, 0.1 ether);

        vm.prank(alice);
        (bool ok, ) = address(faucet).call{value: 0.1 ether}(
            abi.encodeWithSignature("randomFunction()")
        );
        assertTrue(ok);
        assertEq(address(faucet).balance, 1.1 ether);
    }

    // =============================================================
    // changeOwner（继承自 Owner）
    // =============================================================

    function test_Faucet_ChangeOwner_Succeeds() public {
        faucet.changeOwner(alice);
        assertEq(faucet.owner(), alice);

        // 新 owner 可以操作
        vm.prank(alice);
        faucet.pause();
        assertTrue(faucet.paused());
    }

    function test_Faucet_ChangeOwner_RevertsWhenNotOwner() public {
        vm.prank(alice);
        vm.expectRevert("Only owner can call this function");
        faucet.changeOwner(bob);
    }
}
