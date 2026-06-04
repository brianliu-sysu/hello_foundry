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

    // ── EIP-2612 permit helpers ──
    bytes32 private constant PERMIT_TYPEHASH =
        keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");

    uint256 private alicePrivateKey = 0xA11CE;

    function setUp() public {
        // 给 makeAddr("alice") 分配一个已知私钥，才能签名 permit
        alice = vm.addr(alicePrivateKey);
        vm.label(alice, "alice");

        // 部署 TokenBank
        bank = new TokenBank();

        // 部署 BrianICOToken，初始供应全部给 alice
        vm.prank(alice);
        token = new BrianICOToken(INITIAL_SUPPLY);
    }

    /// @dev 构建 EIP-712 permit 签名
    function _signPermit(
        uint256 signerPrivateKey,
        address owner,
        address spender,
        uint256 value,
        uint256 nonce,
        uint256 deadline
    ) internal view returns (uint8 v, bytes32 r, bytes32 s) {
        bytes32 domainSeparator = token.DOMAIN_SEPARATOR();
        bytes32 structHash = keccak256(
            abi.encode(PERMIT_TYPEHASH, owner, spender, value, nonce, deadline)
        );
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
        return vm.sign(signerPrivateKey, digest);
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

    // =============================================================
    // EIP-2612 permit on BrianICOToken
    // =============================================================

    function test_Permit_SetsAllowance() public {
        uint256 amount = 500 * 10 ** 18;
        uint256 deadline = block.timestamp + 1 hours;
        uint256 nonce = token.nonces(alice);

        (uint8 v, bytes32 r, bytes32 s) = _signPermit(
            alicePrivateKey, alice, address(bank), amount, nonce, deadline
        );

        // Anyone can call permit (alice herself in this case)
        vm.prank(alice);
        token.permit(alice, address(bank), amount, deadline, v, r, s);

        assertEq(token.allowance(alice, address(bank)), amount);
    }

    function test_Permit_RevertWhenExpired() public {
        uint256 amount = 100 * 10 ** 18;
        uint256 deadline = block.timestamp + 1;
        uint256 nonce = token.nonces(alice);

        (uint8 v, bytes32 r, bytes32 s) = _signPermit(
            alicePrivateKey, alice, address(bank), amount, nonce, deadline
        );

        // 快进到 deadline 之后
        vm.warp(block.timestamp + 2);

        vm.prank(alice);
        vm.expectRevert(); // ERC20Permit: expired deadline
        token.permit(alice, address(bank), amount, deadline, v, r, s);
    }

    function test_Permit_NonceIncrementsAfterUse() public {
        uint256 amount = 100 * 10 ** 18;
        uint256 deadline = block.timestamp + 1 hours;

        assertEq(token.nonces(alice), 0);

        (uint8 v, bytes32 r, bytes32 s) = _signPermit(
            alicePrivateKey, alice, address(bank), amount, 0, deadline
        );
        vm.prank(alice);
        token.permit(alice, address(bank), amount, deadline, v, r, s);

        assertEq(token.nonces(alice), 1);
    }

    function test_Permit_DOMAIN_SEPARATOR() public view {
        // 验证 DOMAIN_SEPARATOR 存在且非零
        assertTrue(token.DOMAIN_SEPARATOR() != bytes32(0));
    }

    // =============================================================
    // TokenBank permitDeposit
    // =============================================================

    function test_PermitDeposit_GaslessDeposit() public {
        uint256 amount = 500 * 10 ** 18;
        uint256 deadline = block.timestamp + 1 hours;
        uint256 nonce = token.nonces(alice);

        // alice 离线签名，授权 bank 花费她的 token
        (uint8 v, bytes32 r, bytes32 s) = _signPermit(
            alicePrivateKey, alice, address(bank), amount, nonce, deadline
        );

        // 任何人（如 relayer）都可以代为提交
        vm.prank(address(0x5E1a6e5eA1ab));
        bank.permitDeposit(alice, address(token), amount, deadline, v, r, s);

        // 验证：存款记录在 alice（owner）名下
        assertEq(bank.deposits(alice, address(token)), amount);
        assertEq(token.balanceOf(address(bank)), amount);
    }

    function test_PermitDeposit_RecordsUnderOwnerNotCaller() public {
        uint256 amount = 300 * 10 ** 18;
        uint256 deadline = block.timestamp + 1 hours;
        uint256 nonce = token.nonces(alice);

        (uint8 v, bytes32 r, bytes32 s) = _signPermit(
            alicePrivateKey, alice, address(bank), amount, nonce, deadline
        );

        // relayer 调用，但存款应归属 alice
        vm.prank(bob);
        bank.permitDeposit(alice, address(token), amount, deadline, v, r, s);

        assertEq(bank.deposits(alice, address(token)), amount);
        // bob 没有存款
        assertEq(bank.deposits(bob, address(token)), 0);
    }

    function test_PermitDeposit_EmitsDepositedEvent() public {
        uint256 amount = 200 * 10 ** 18;
        uint256 deadline = block.timestamp + 1 hours;
        uint256 nonce = token.nonces(alice);

        (uint8 v, bytes32 r, bytes32 s) = _signPermit(
            alicePrivateKey, alice, address(bank), amount, nonce, deadline
        );

        vm.expectEmit(true, true, false, true);
        emit TokenBank.Deposited(address(token), alice, amount);

        bank.permitDeposit(alice, address(token), amount, deadline, v, r, s);
    }

    function test_PermitDeposit_RevertWhenAmountIsZero() public {
        uint256 deadline = block.timestamp + 1 hours;
        uint256 nonce = token.nonces(alice);

        (uint8 v, bytes32 r, bytes32 s) = _signPermit(
            alicePrivateKey, alice, address(bank), 0, nonce, deadline
        );

        vm.expectRevert("TokenBank: amount must be > 0");
        bank.permitDeposit(alice, address(token), 0, deadline, v, r, s);
    }

    function test_PermitDeposit_RevertWhenExpired() public {
        uint256 amount = 100 * 10 ** 18;
        uint256 deadline = block.timestamp + 1;
        uint256 nonce = token.nonces(alice);

        (uint8 v, bytes32 r, bytes32 s) = _signPermit(
            alicePrivateKey, alice, address(bank), amount, nonce, deadline
        );

        vm.warp(block.timestamp + 2);

        vm.expectRevert(); // ERC20Permit: expired deadline
        bank.permitDeposit(alice, address(token), amount, deadline, v, r, s);
    }

    function test_PermitDeposit_MultiplePermits() public {
        uint256 amount1 = 200 * 10 ** 18;
        uint256 amount2 = 300 * 10 ** 18;
        uint256 deadline = block.timestamp + 1 hours;

        // 第一笔
        (uint8 v1, bytes32 r1, bytes32 s1) = _signPermit(
            alicePrivateKey, alice, address(bank), amount1, 0, deadline
        );
        bank.permitDeposit(alice, address(token), amount1, deadline, v1, r1, s1);

        // 第二笔（nonce 自动增加）
        (uint8 v2, bytes32 r2, bytes32 s2) = _signPermit(
            alicePrivateKey, alice, address(bank), amount2, 1, deadline
        );
        bank.permitDeposit(alice, address(token), amount2, deadline, v2, r2, s2);

        assertEq(bank.deposits(alice, address(token)), amount1 + amount2);
        assertEq(token.balanceOf(address(bank)), amount1 + amount2);
    }

    function testFuzz_PermitDeposit(uint256 amount) public {
        amount = bound(amount, 1, INITIAL_SUPPLY);
        uint256 deadline = block.timestamp + 1 hours;
        uint256 nonce = token.nonces(alice);

        (uint8 v, bytes32 r, bytes32 s) = _signPermit(
            alicePrivateKey, alice, address(bank), amount, nonce, deadline
        );

        bank.permitDeposit(alice, address(token), amount, deadline, v, r, s);

        assertEq(bank.deposits(alice, address(token)), amount);
    }
}
