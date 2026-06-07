// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {BrianICOToken} from "../src/BrianICOToken.sol";
import {TokenBank} from "../src/TokenBank.sol";
import {ISignatureTransfer} from "../src/ISignatureTransfer.sol";
import {IERC1363} from "@openzeppelin/contracts/interfaces/IERC1363.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// ── Minimal Permit2 mock for testing ──
// Only implements permitTransferFrom with EIP-712 signature verification.
contract MockPermit2 {
    mapping(address user => mapping(uint256 nonce => bool used)) public nonceUsed;

    // EIP-712 type: PermitTransferFrom(TokenPermissions permitted,uint256 nonce,uint256 deadline)
    //                 TokenPermissions(address token,uint256 amount)
    bytes32 private constant _PERMIT_TRANSFER_FROM_TYPEHASH = keccak256(
        "PermitTransferFrom(TokenPermissions permitted,uint256 nonce,uint256 deadline)TokenPermissions(address token,uint256 amount)"
    );

    function permitTransferFrom(
        ISignatureTransfer.PermitTransferFrom memory permit,
        ISignatureTransfer.SignatureTransferDetails calldata transferDetails,
        address owner,
        bytes calldata signature
    ) external {
        require(block.timestamp <= permit.deadline, "Permit2: deadline expired");
        require(!nonceUsed[owner][permit.nonce], "Permit2: nonce already used");

        bytes32 domainSeparator = keccak256(abi.encode(
            keccak256("EIP712Domain(string name,uint256 chainId,address verifyingContract)"),
            keccak256("Permit2"),
            block.chainid,
            address(this)
        ));

        bytes32 tokenPermissionsHash = keccak256(abi.encode(
            keccak256("TokenPermissions(address token,uint256 amount)"),
            permit.permitted.token,
            permit.permitted.amount
        ));

        bytes32 structHash = keccak256(abi.encode(
            _PERMIT_TRANSFER_FROM_TYPEHASH,
            tokenPermissionsHash,
            permit.nonce,
            permit.deadline
        ));

        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));

        // Recover signer from 65-byte signature (r || s || v)
        address recovered = ecrecover(digest, uint8(signature[64]), bytes32(signature[0:32]), bytes32(signature[32:64]));
        require(recovered == owner && recovered != address(0), "Permit2: invalid signature");

        nonceUsed[owner][permit.nonce] = true;

        require(
            IERC20(permit.permitted.token).transferFrom(owner, transferDetails.to, transferDetails.requestedAmount),
            "Permit2: transferFrom failed"
        );
    }
}

contract TokenBankTest is Test {
    BrianICOToken public token;
    TokenBank public bank;

    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");

    uint256 constant INITIAL_SUPPLY = 1_000_000 * 10 ** 18;

    // Permit2 singleton address (same on all EVM chains)
    address private constant PERMIT2_ADDRESS = 0x000000000022D473030F116dDEE9F6B43aC78BA3;

    // ── EIP-2612 permit helpers ──
    bytes32 private constant PERMIT_TYPEHASH =
        keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");

    uint256 private alicePrivateKey = 0xA11CE;

    function setUp() public {
        // 给 makeAddr("alice") 分配一个已知私钥，才能签名 permit
        alice = vm.addr(alicePrivateKey);
        vm.label(alice, "alice");

        // 部署 MockPermit2 到 Permit2 单例地址
        MockPermit2 mockPermit2 = new MockPermit2();
        vm.etch(PERMIT2_ADDRESS, address(mockPermit2).code);
        vm.label(PERMIT2_ADDRESS, "Permit2");

        // 部署 TokenBank
        bank = new TokenBank();

        // 部署 BrianICOToken，初始供应全部给 alice
        vm.prank(alice);
        token = new BrianICOToken(INITIAL_SUPPLY);

        // alice 预先 approve Permit2 合约（Permit2 SignatureTransfer 的前置条件）
        vm.prank(alice);
        token.approve(PERMIT2_ADDRESS, type(uint256).max);
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

    /// @dev 构建 Permit2 PermitTransferFrom EIP-712 签名（返回 r||s||v 的 bytes）
    function _signPermit2(
        uint256 signerPrivateKey,
        address tokenAddr,
        uint256 amount,
        uint256 nonce,
        uint256 deadline
    ) internal view returns (bytes memory signature) {
        bytes32 domainSeparator = keccak256(abi.encode(
            keccak256("EIP712Domain(string name,uint256 chainId,address verifyingContract)"),
            keccak256("Permit2"),
            block.chainid,
            PERMIT2_ADDRESS
        ));

        bytes32 tokenPermissionsHash = keccak256(abi.encode(
            keccak256("TokenPermissions(address token,uint256 amount)"),
            tokenAddr,
            amount
        ));

        bytes32 structHash = keccak256(abi.encode(
            keccak256("PermitTransferFrom(TokenPermissions permitted,uint256 nonce,uint256 deadline)TokenPermissions(address token,uint256 amount)"),
            tokenPermissionsHash,
            nonce,
            deadline
        ));

        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPrivateKey, digest);
        signature = abi.encodePacked(r, s, v);
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

    // =============================================================
    // TokenBank depositPermit2 (Uniswap Permit2 SignatureTransfer)
    // =============================================================

    function test_DepositPermit2_Success() public {
        uint256 amount = 500 * 10 ** 18;
        uint256 deadline = block.timestamp + 1 hours;
        uint256 nonce = 0;

        bytes memory signature = _signPermit2(alicePrivateKey, address(token), amount, nonce, deadline);

        // Anyone (relayer) can submit
        vm.prank(address(0x5E1a6e5eA1ab));
        bank.depositPermit2(alice, address(token), amount, nonce, deadline, signature);

        assertEq(bank.deposits(alice, address(token)), amount);
        assertEq(token.balanceOf(address(bank)), amount);
    }

    function test_DepositPermit2_RecordsUnderOwner() public {
        uint256 amount = 300 * 10 ** 18;
        uint256 deadline = block.timestamp + 1 hours;
        uint256 nonce = 0;

        bytes memory signature = _signPermit2(alicePrivateKey, address(token), amount, nonce, deadline);

        // bob submits on alice's behalf — deposit should still record under alice
        vm.prank(bob);
        bank.depositPermit2(alice, address(token), amount, nonce, deadline, signature);

        assertEq(bank.deposits(alice, address(token)), amount);
        assertEq(bank.deposits(bob, address(token)), 0);
    }

    function test_DepositPermit2_EmitsEvent() public {
        uint256 amount = 200 * 10 ** 18;
        uint256 deadline = block.timestamp + 1 hours;
        uint256 nonce = 0;

        bytes memory signature = _signPermit2(alicePrivateKey, address(token), amount, nonce, deadline);

        vm.expectEmit(true, true, false, true);
        emit TokenBank.Deposited(address(token), alice, amount);

        bank.depositPermit2(alice, address(token), amount, nonce, deadline, signature);
    }

    function test_DepositPermit2_RevertZeroAmount() public {
        uint256 deadline = block.timestamp + 1 hours;
        uint256 nonce = 0;

        bytes memory signature = _signPermit2(alicePrivateKey, address(token), 0, nonce, deadline);

        vm.expectRevert("TokenBank: amount must be > 0");
        bank.depositPermit2(alice, address(token), 0, nonce, deadline, signature);
    }

    function test_DepositPermit2_RevertExpired() public {
        uint256 amount = 100 * 10 ** 18;
        uint256 deadline = block.timestamp + 1;
        uint256 nonce = 0;

        bytes memory signature = _signPermit2(alicePrivateKey, address(token), amount, nonce, deadline);

        vm.warp(block.timestamp + 2);

        vm.expectRevert("Permit2: deadline expired");
        bank.depositPermit2(alice, address(token), amount, nonce, deadline, signature);
    }

    function test_DepositPermit2_RevertNonceReuse() public {
        uint256 amount = 100 * 10 ** 18;
        uint256 deadline = block.timestamp + 1 hours;
        uint256 nonce = 0;

        bytes memory signature = _signPermit2(alicePrivateKey, address(token), amount, nonce, deadline);

        // First use succeeds
        bank.depositPermit2(alice, address(token), amount, nonce, deadline, signature);

        // Second use with same nonce should fail
        vm.expectRevert("Permit2: nonce already used");
        bank.depositPermit2(alice, address(token), amount, nonce, deadline, signature);
    }

    function test_DepositPermit2_MultiplePermits() public {
        uint256 amount1 = 200 * 10 ** 18;
        uint256 amount2 = 300 * 10 ** 18;
        uint256 deadline = block.timestamp + 1 hours;

        bytes memory sig1 = _signPermit2(alicePrivateKey, address(token), amount1, 0, deadline);
        bank.depositPermit2(alice, address(token), amount1, 0, deadline, sig1);

        bytes memory sig2 = _signPermit2(alicePrivateKey, address(token), amount2, 1, deadline);
        bank.depositPermit2(alice, address(token), amount2, 1, deadline, sig2);

        assertEq(bank.deposits(alice, address(token)), amount1 + amount2);
        assertEq(token.balanceOf(address(bank)), amount1 + amount2);
    }

    function testFuzz_DepositPermit2(uint256 amount) public {
        amount = bound(amount, 1, INITIAL_SUPPLY);
        uint256 deadline = block.timestamp + 1 hours;
        uint256 nonce = 0;

        bytes memory signature = _signPermit2(alicePrivateKey, address(token), amount, nonce, deadline);

        bank.depositPermit2(alice, address(token), amount, nonce, deadline, signature);

        assertEq(bank.deposits(alice, address(token)), amount);
    }

    // =============================================================
    // BrianICOToken — admin withdraw
    // =============================================================

    function test_AdminWithdrawETH_SendsETHToOwner() public {
        // 向 token 合约转入 ETH（模拟误转入）
        vm.deal(address(token), 5 ether);

        uint256 ownerBefore = alice.balance;

        vm.prank(alice);
        token.adminWithdrawETH();

        assertEq(address(token).balance, 0);
        assertEq(alice.balance, ownerBefore + 5 ether);
    }

    function test_AdminWithdrawETH_RevertsWhenNotOwner() public {
        vm.deal(address(token), 1 ether);

        vm.prank(bob);
        vm.expectRevert(); // OwnableUnauthorizedAccount
        token.adminWithdrawETH();
    }

    function test_AdminWithdrawETH_RevertsWhenZeroBalance() public {
        vm.prank(alice);
        vm.expectRevert("No ETH to withdraw");
        token.adminWithdrawETH();
    }

    function test_AdminWithdrawToken_RecoversERC20() public {
        // 向 token 合约转入其他 ERC20 代币（模拟误转入 BIT 到自己）
        vm.prank(alice);
        token.transfer(address(token), 1000 * 10 ** 18);

        uint256 ownerBefore = token.balanceOf(alice);

        vm.prank(alice);
        token.adminWithdrawToken(address(token));

        assertEq(token.balanceOf(address(token)), 0);
        assertEq(token.balanceOf(alice), ownerBefore + 1000 * 10 ** 18);
    }

    function test_AdminWithdrawToken_RevertsWhenNotOwner() public {
        vm.prank(alice);
        token.transfer(address(token), 100 * 10 ** 18);

        vm.prank(bob);
        vm.expectRevert(); // OwnableUnauthorizedAccount
        token.adminWithdrawToken(address(token));
    }

    function test_AdminWithdrawToken_RevertsWhenZeroBalance() public {
        vm.prank(alice);
        vm.expectRevert("No tokens to withdraw");
        token.adminWithdrawToken(address(token));
    }
}
