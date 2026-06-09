// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {NaiveFaucet} from "../src/token/NaiveFaucet.sol";
import {BrianICOToken} from "../src/token/BrianICOToken.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract NaiveFaucetTest is Test {
    BrianICOToken public token;
    NaiveFaucet public faucet;

    address public owner = makeAddr("owner");
    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");

    uint256 constant INITIAL_SUPPLY = 1_000_000 * 10 ** 18;

    function setUp() public {
        // owner 持有全部初始供应
        vm.prank(owner);
        token = new BrianICOToken(INITIAL_SUPPLY);

        // owner 部署 NaiveFaucet
        // 注意：NaiveFaucet 构造器中的 token.approve 实际是以 NaiveFaucet 的地址
        // 作为 msg.sender 调用的，因此不会给 owner 的额度授权。
        // 部署后需由 owner 主动 approve。
        vm.prank(owner);
        faucet = new NaiveFaucet(token, owner);

        // owner 授权 NaiveFaucet 支配其代币
        vm.prank(owner);
        token.approve(address(faucet), type(uint256).max);
    }

    // =============================================================
    // 部署
    // =============================================================

    function test_NaiveFaucet_Deploy_TokenSet() public view {
        assertEq(address(faucet.token()), address(token));
    }

    function test_NaiveFaucet_Deploy_OwnerSet() public view {
        assertEq(faucet.owner(), owner);
    }

    function test_NaiveFaucet_Deploy_AllowanceAfterPreApprove() public view {
        // 部署后由 owner 主动授权，所以有额度
        assertEq(token.allowance(owner, address(faucet)), type(uint256).max);
    }

    // =============================================================
    // withdraw
    // =============================================================

    function test_NaiveFaucet_Withdraw_TransfersTokens() public {
        uint256 amount = 1000 * 10 ** 18;

        vm.prank(alice);
        faucet.withdraw(amount);

        assertEq(token.balanceOf(alice), amount);
        assertEq(token.balanceOf(owner), INITIAL_SUPPLY - amount);
    }

    function test_NaiveFaucet_Withdraw_EmitsWithdrawalEvent() public {
        uint256 amount = 500 * 10 ** 18;

        vm.expectEmit(true, true, false, true);
        emit NaiveFaucet.Withdrawal(alice, amount);

        vm.prank(alice);
        faucet.withdraw(amount);
    }

    function test_NaiveFaucet_Withdraw_RevertsWhenAmountTooLarge() public {
        // 单次提取上限为 100_000 * 10^18
        uint256 tooLarge = 100_000 * 10 ** 18 + 1;

        vm.prank(alice);
        vm.expectRevert("Amount is too large");
        faucet.withdraw(tooLarge);
    }

    function test_NaiveFaucet_Withdraw_MaxAmount() public {
        uint256 maxAmount = 100_000 * 10 ** 18;

        vm.prank(alice);
        faucet.withdraw(maxAmount);

        assertEq(token.balanceOf(alice), maxAmount);
    }

    function test_NaiveFaucet_Withdraw_RevertsWhenInsufficientOwnerBalance() public {
        // 先将 owner 的余额转走，使余额不足
        uint256 drainAmount = INITIAL_SUPPLY - 500 * 10 ** 18; // 留 500
        vm.prank(owner);
        token.transfer(bob, drainAmount);

        // 尝试提取超过 owner 余额的量（但不超过上限）
        uint256 tooMuch = 501 * 10 ** 18;

        vm.prank(alice);
        vm.expectRevert("Insufficient balance");
        faucet.withdraw(tooMuch);
    }

    function test_NaiveFaucet_Withdraw_MultipleUsers() public {
        uint256 aliceAmount = 500 * 10 ** 18;
        uint256 bobAmount = 200 * 10 ** 18;

        vm.prank(alice);
        faucet.withdraw(aliceAmount);

        vm.prank(bob);
        faucet.withdraw(bobAmount);

        assertEq(token.balanceOf(alice), aliceAmount);
        assertEq(token.balanceOf(bob), bobAmount);
        assertEq(token.balanceOf(owner), INITIAL_SUPPLY - aliceAmount - bobAmount);
    }

    // =============================================================
    // Fuzz tests
    // =============================================================

    function testFuzz_NaiveFaucet_Withdraw_Amount(uint256 amount) public {
        amount = bound(amount, 1, 100_000 * 10 ** 18);

        address recipient = makeAddr("recipient");
        vm.prank(recipient);
        faucet.withdraw(amount);

        assertEq(token.balanceOf(recipient), amount);
    }
}
