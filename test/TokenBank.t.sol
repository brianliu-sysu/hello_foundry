// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {BrianICOToken} from "../src/BrianICOToken.sol";
import {TokenBank} from "../src/TokenBank.sol";
import {IERC1363} from "@openzeppelin/contracts/interfaces/IERC1363.sol";

contract TokenBankTest is Test {
    BrianICOToken public token;
    TokenBank public bank;

    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");

    uint256 constant INITIAL_SUPPLY = 1_000_000 * 10 ** 18;

    function setUp() public {
        // 部署 TokenBank
        bank = new TokenBank();

        // 部署 BrianICOToken，初始供应全部给 alice
        vm.prank(alice);
        token = new BrianICOToken(INITIAL_SUPPLY);
    }

    // =============================================================
    // deploy
    // =============================================================

    function test_Deploy_TokenNameAndSymbol() public view {
        assertEq(token.name(), "BrianICOToken");
        assertEq(token.symbol(), "BIT");
    }

    function test_Deploy_InitialSupplyToDeployer() public view {
        assertEq(token.balanceOf(alice), INITIAL_SUPPLY);
    }

    function test_Deploy_SupportsERC1363Interface() public view {
        assertTrue(token.supportsInterface(type(IERC1363).interfaceId));
    }

    // =============================================================
    // transferAndCall
    // =============================================================

    function test_TransferAndCall_RecordsDepositInBank() public {
        uint256 amount = 1000 * 10 ** 18;

        vm.prank(alice);
        bool ok = token.transferAndCall(address(bank), amount);

        assertTrue(ok);
        // 记录存入即为 bank 收到代币
        assertEq(token.balanceOf(address(bank)), amount);
        // TokenBank 中 alice 对该 token 的存款
        assertEq(bank.deposits(alice, address(token)), amount);
    }

    function test_TransferAndCall_AccumulatesMultipleDeposits() public {
        uint256 amount1 = 1000 * 10 ** 18;
        uint256 amount2 = 500 * 10 ** 18;

        vm.startPrank(alice);
        token.transferAndCall(address(bank), amount1);
        token.transferAndCall(address(bank), amount2);
        vm.stopPrank();

        assertEq(bank.deposits(alice, address(token)), amount1 + amount2);
        assertEq(token.balanceOf(address(bank)), amount1 + amount2);
    }

    function test_TransferAndCall_MultipleUsersIndependentRecords() public {
        uint256 aliceAmount = 1000 * 10 ** 18;
        uint256 bobAmount = 200 * 10 ** 18;

        // 先给 bob 转一些 token
        vm.prank(alice);
        assertTrue(token.transfer(bob, bobAmount));

        vm.prank(alice);
        token.transferAndCall(address(bank), aliceAmount);

        vm.prank(bob);
        token.transferAndCall(address(bank), bobAmount);

        assertEq(bank.deposits(alice, address(token)), aliceAmount);
        assertEq(bank.deposits(bob, address(token)), bobAmount);
        assertEq(token.balanceOf(address(bank)), aliceAmount + bobAmount);
    }

    function test_TransferAndCall_EmitsDepositedEvent() public {
        uint256 amount = 500 * 10 ** 18;

        vm.expectEmit(true, true, false, true);
        emit TokenBank.Deposited(address(token), alice, amount);

        vm.prank(alice);
        token.transferAndCall(address(bank), amount);
    }

    function test_TransferAndCall_WithData() public {
        uint256 amount = 100 * 10 ** 18;

        vm.prank(alice);
        bool ok = token.transferAndCall(address(bank), amount, abi.encode("deposit-ref-42"));

        assertTrue(ok);
        assertEq(bank.deposits(alice, address(token)), amount);
    }

    // =============================================================
    // transferFromAndCall
    // =============================================================

    function test_TransferFromAndCall_ApprovedSpenderCanDeposit() public {
        uint256 amount = 300 * 10 ** 18;

        // alice 授权 bob 花费她的 token
        vm.prank(alice);
        token.approve(bob, amount);

        // bob 调用 transferFromAndCall 将 alice 的 token 转入 bank
        vm.prank(bob);
        bool ok = token.transferFromAndCall(alice, address(bank), amount);

        assertTrue(ok);
        // 存款应记录在 from(alice) 名下
        assertEq(bank.deposits(alice, address(token)), amount);
        assertEq(token.balanceOf(address(bank)), amount);
    }

    function test_TransferFromAndCall_RevertWhenInsufficientAllowance() public {
        uint256 amount = 100 * 10 ** 18;

        // bob 没有授权，无法从 alice 转走 token
        vm.prank(bob);
        vm.expectRevert();
        token.transferFromAndCall(alice, address(bank), amount);
    }

    // =============================================================
    // depositToBank (convenience wrapper)
    // =============================================================

    function test_DepositToBank_EquivalentToTransferAndCall() public {
        uint256 amount = 777 * 10 ** 18;

        vm.prank(alice);
        bool ok = token.depositToBank(address(bank), amount);

        assertTrue(ok);
        assertEq(bank.deposits(alice, address(token)), amount);
        assertEq(token.balanceOf(address(bank)), amount);
    }

    // =============================================================
    // withdraw
    // =============================================================

    function test_Withdraw_ReturnsTokensToUser() public {
        uint256 depositAmount = 500 * 10 ** 18;
        uint256 withdrawAmount = 200 * 10 ** 18;

        vm.prank(alice);
        token.transferAndCall(address(bank), depositAmount);

        vm.prank(alice);
        bank.withdraw(address(token), withdrawAmount);

        assertEq(bank.deposits(alice, address(token)), depositAmount - withdrawAmount);
        assertEq(token.balanceOf(alice), INITIAL_SUPPLY - depositAmount + withdrawAmount);
        assertEq(token.balanceOf(address(bank)), depositAmount - withdrawAmount);
    }

    function test_Withdraw_FullBalance() public {
        uint256 depositAmount = 500 * 10 ** 18;

        vm.prank(alice);
        token.transferAndCall(address(bank), depositAmount);

        vm.prank(alice);
        bank.withdraw(address(token), depositAmount);

        assertEq(bank.deposits(alice, address(token)), 0);
        assertEq(token.balanceOf(alice), INITIAL_SUPPLY);
    }

    function test_Withdraw_RevertWhenInsufficientDeposit() public {
        vm.prank(alice);
        vm.expectRevert("TokenBank: insufficient deposit");
        bank.withdraw(address(token), 1);
    }

    function test_Withdraw_EmitsWithdrawnEvent() public {
        uint256 depositAmount = 100 * 10 ** 18;
        uint256 withdrawAmount = 50 * 10 ** 18;

        vm.prank(alice);
        token.transferAndCall(address(bank), depositAmount);

        vm.expectEmit(true, true, false, true);
        emit TokenBank.Withdrawn(address(token), alice, withdrawAmount);

        vm.prank(alice);
        bank.withdraw(address(token), withdrawAmount);
    }

    // =============================================================
    // Fuzz tests
    // =============================================================

    function testFuzz_TransferAndCall_DepositAmount(
        uint256 amount
    ) public {
        amount = bound(amount, 1, INITIAL_SUPPLY);

        vm.prank(alice);
        token.transferAndCall(address(bank), amount);

        assertEq(bank.deposits(alice, address(token)), amount);
    }

    function testFuzz_DepositThenWithdraw(
        uint256 depositAmount,
        uint256 withdrawAmount
    ) public {
        depositAmount = bound(depositAmount, 1, INITIAL_SUPPLY);
        withdrawAmount = bound(withdrawAmount, 1, depositAmount);

        vm.startPrank(alice);
        token.transferAndCall(address(bank), depositAmount);
        bank.withdraw(address(token), withdrawAmount);
        vm.stopPrank();

        assertEq(bank.deposits(alice, address(token)), depositAmount - withdrawAmount);
    }

    // =============================================================
    // Edge cases: transferAndCall to EOA (non-receiver)
    // =============================================================

    function test_TransferAndCall_RevertWhenReceiverIsEOA() public {
        uint256 amount = 100 * 10 ** 18;

        // EOA 没有实现 IERC1363Receiver，ERC1363 的 transferAndCall 会失败
        vm.prank(alice);
        vm.expectRevert();
        token.transferAndCall(bob, amount);
    }
}
