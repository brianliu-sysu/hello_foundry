// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {Faucet, Token} from "../src/token/Token.sol";

contract TokenTest is Test {
    Faucet public parentFaucet;
    Token public token;

    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");

    // Faucet.withdraw 单次上限
    uint256 constant MAX_WITHDRAW = 0.01 ether;

    function setUp() public {
        // 部署父 Faucet 并充值
        vm.deal(address(this), 10 ether);
        parentFaucet = new Faucet{value: 5 ether}();

        // 部署 Token，构造器中会从 parentFaucet 提取 MAX_WITHDRAW (0.01 ether)
        token = new Token{value: 0}(payable(address(parentFaucet)));

        // 将 parentFaucet 的 owner 设为 Token 合约，这样 Token.changeFaucetOwner 才能工作
        parentFaucet.changeOwner(address(token));
    }

    // =============================================================
    // 部署
    // =============================================================

    function test_Token_Deploy_SetsFaucet() public view {
        assertEq(address(token.faucet()), address(parentFaucet));
    }

    function test_Token_Deploy_DeployerIsOwner() public view {
        // Token 的 owner（继承自 Faucet）是部署者
        assertEq(token.owner(), address(this));
    }

    function test_Token_Deploy_WithdrawsFromParentFaucet() public view {
        // Token 构造器中调用了 parentFaucet.withdraw(MAX_WITHDRAW, ...)
        // Token 持有从父 Faucet 提取的 ether
        assertEq(address(token).balance, MAX_WITHDRAW);
        assertEq(address(parentFaucet).balance, 5 ether - MAX_WITHDRAW);
    }

    // =============================================================
    // changeFaucetOwner
    // =============================================================

    function test_Token_ChangeFaucetOwner_Succeeds() public {
        // setUp 中已将 parentFaucet.owner 设为 address(token)
        // Token.changeFaucetOwner 调用 parentFaucet.changeOwner(newOwner)
        token.changeFaucetOwner(alice);
        assertEq(parentFaucet.owner(), alice);
    }

    function test_Token_ChangeFaucetOwner_RevertsWhenNotTokenOwner() public {
        vm.prank(alice);
        vm.expectRevert("Only owner can call this function");
        token.changeFaucetOwner(bob);
    }

    // =============================================================
    // 继承自 Faucet 的功能
    // =============================================================

    function test_Token_InheritedWithdraw_Succeeds() public {
        // Token 本身也是一个 Faucet，可以提现
        vm.deal(address(token), 1 ether);

        uint256 amount = MAX_WITHDRAW;
        uint256 bobBalanceBefore = bob.balance;

        token.withdraw(amount, payable(bob));

        assertEq(bob.balance, bobBalanceBefore + amount);
    }

    function test_Token_InheritedWithdraw_RevertsWhenTooLarge() public {
        vm.deal(address(token), 1 ether);

        vm.expectRevert();
        token.withdraw(MAX_WITHDRAW + 1, payable(bob));
    }

    function test_Token_InheritedPause_Succeeds() public {
        token.pause();
        assertTrue(token.paused());
    }

    function test_Token_Receive_EmitsDeposit() public {
        vm.deal(alice, 0.5 ether);

        vm.expectEmit(true, false, false, true);
        emit Faucet.Deposit(alice, 0.5 ether);

        vm.prank(alice);
        (bool ok, ) = address(token).call{value: 0.5 ether}("");
        assertTrue(ok);
    }

    // =============================================================
    // 完整流程测试
    // =============================================================

    function test_Token_FullFlow() public {
        // 1. Token owner 通过 changeFaucetOwner 修改 parent faucet 的 owner
        token.changeFaucetOwner(alice);
        assertEq(parentFaucet.owner(), alice);

        // 2. 新 owner(alice) 可以操作 parent faucet
        vm.prank(alice);
        parentFaucet.pause();
        assertTrue(parentFaucet.paused());

        // 3. Token 本身独立运作，不受 parent faucet pause 影响
        vm.deal(address(token), 0.1 ether);
        token.withdraw(500, payable(bob));
        assertEq(bob.balance, 500);
    }
}
