// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {BrianICOToken} from "../src/token/BrianICOToken.sol";
import {TokenBank} from "../src/token/TokenBank.sol";
import {Permit2} from "../src/utils/Permit2.sol";
import {ISignatureTransfer} from "../src/utils/ISignatureTransfer.sol";

contract Permit2Test is Test {
    BrianICOToken public token;
    TokenBank public bank;

    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");
    address public owner;

    uint256 constant INITIAL_SUPPLY = 1_000_000 * 10 ** 18;
    address private constant PERMIT2_ADDRESS = 0x000000000022D473030F116dDEE9F6B43aC78BA3;

    uint256 private alicePrivateKey = 0xA11CE;

    function setUp() public {
        alice = vm.addr(alicePrivateKey);
        vm.label(alice, "alice");
        owner = makeAddr("owner");

        // Deploy Permit2, then etch to canonical address
        Permit2 permit2 = new Permit2(alice);
        vm.etch(PERMIT2_ADDRESS, address(permit2).code);
        vm.label(PERMIT2_ADDRESS, "Permit2");

        // Deploy TokenBank (uses PERMIT2 constant internally)
        bank = new TokenBank();

        // Deploy token, all supply to alice
        vm.prank(alice);
        token = new BrianICOToken(INITIAL_SUPPLY);

        // alice pre-approves Permit2 (one-time setup)
        vm.prank(alice);
        token.approve(PERMIT2_ADDRESS, type(uint256).max);
    }

    // ── Helpers ────────────────────────────────────────────────

    /// @dev Sign a PermitTransferFrom message, using the Permit2's own DOMAIN_SEPARATOR
    function _signPermit2(
        uint256 signerPrivateKey,
        address tokenAddr,
        uint256 amount,
        uint256 nonce,
        uint256 deadline
    ) internal view returns (bytes memory signature) {
        bytes32 domainSeparator = Permit2(payable(PERMIT2_ADDRESS)).DOMAIN_SEPARATOR();

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

    function _permit(address tokenAddr, uint256 amount, uint256 nonce, uint256 deadline)
        internal pure
        returns (ISignatureTransfer.PermitTransferFrom memory)
    {
        return ISignatureTransfer.PermitTransferFrom({
            permitted: ISignatureTransfer.TokenPermissions({token: tokenAddr, amount: amount}),
            nonce: nonce,
            deadline: deadline
        });
    }

    function _details(address to, uint256 amount)
        internal pure
        returns (ISignatureTransfer.SignatureTransferDetails memory)
    {
        return ISignatureTransfer.SignatureTransferDetails({to: to, requestedAmount: amount});
    }

    // =============================================================
    // Permit2: DOMAIN_SEPARATOR
    // =============================================================

    function test_DomainSeparator_IsSet() public view {
        bytes32 ds = Permit2(payable(PERMIT2_ADDRESS)).DOMAIN_SEPARATOR();
        assertTrue(ds != bytes32(0));
    }

    function test_DomainSeparator_MatchesComputed() public view {
        bytes32 expected = keccak256(abi.encode(
            keccak256("EIP712Domain(string name,uint256 chainId,address verifyingContract)"),
            keccak256("Permit2"),
            block.chainid,
            PERMIT2_ADDRESS
        ));
        assertEq(Permit2(payable(PERMIT2_ADDRESS)).DOMAIN_SEPARATOR(), expected);
    }

    // =============================================================
    // Permit2: permitTransferFrom (direct)
    // =============================================================

    function test_PermitTransferFrom_TransfersTokens() public {
        uint256 amount = 500 * 10 ** 18;
        uint256 deadline = block.timestamp + 1 hours;

        bytes memory sig = _signPermit2(alicePrivateKey, address(token), amount, 0, deadline);

        ISignatureTransfer(PERMIT2_ADDRESS).permitTransferFrom(
            _permit(address(token), amount, 0, deadline),
            _details(bob, amount),
            alice,
            sig
        );

        assertEq(token.balanceOf(bob), amount);
        assertEq(token.balanceOf(alice), INITIAL_SUPPLY - amount);
    }

    function test_PermitTransferFrom_MarksNonceUsed() public {
        uint256 amount = 100 * 10 ** 18;
        uint256 deadline = block.timestamp + 1 hours;

        bytes memory sig = _signPermit2(alicePrivateKey, address(token), amount, 0, deadline);

        ISignatureTransfer(PERMIT2_ADDRESS).permitTransferFrom(
            _permit(address(token), amount, 0, deadline),
            _details(bob, amount),
            alice,
            sig
        );

        assertTrue(Permit2(payable(PERMIT2_ADDRESS)).nonceUsed(alice, 0));
    }

    function test_PermitTransferFrom_RevertExpiredDeadline() public {
        uint256 amount = 100 * 10 ** 18;
        uint256 deadline = block.timestamp + 1;

        bytes memory sig = _signPermit2(alicePrivateKey, address(token), amount, 0, deadline);

        vm.warp(block.timestamp + 2);

        vm.expectRevert("Permit2: deadline expired");
        ISignatureTransfer(PERMIT2_ADDRESS).permitTransferFrom(
            _permit(address(token), amount, 0, deadline),
            _details(bob, amount),
            alice,
            sig
        );
    }

    function test_PermitTransferFrom_RevertNonceReuse() public {
        uint256 amount = 100 * 10 ** 18;
        uint256 deadline = block.timestamp + 1 hours;

        bytes memory sig = _signPermit2(alicePrivateKey, address(token), amount, 0, deadline);

        // First use succeeds
        ISignatureTransfer(PERMIT2_ADDRESS).permitTransferFrom(
            _permit(address(token), amount, 0, deadline),
            _details(bob, amount),
            alice,
            sig
        );

        // Second use with same nonce fails
        vm.expectRevert("Permit2: nonce already used");
        ISignatureTransfer(PERMIT2_ADDRESS).permitTransferFrom(
            _permit(address(token), amount, 0, deadline),
            _details(bob, amount),
            alice,
            sig
        );
    }

    function test_PermitTransferFrom_RevertInvalidSignature() public {
        uint256 amount = 100 * 10 ** 18;
        uint256 deadline = block.timestamp + 1 hours;

        // bob signs with his own key, but we pass alice as owner
        bytes memory sig = _signPermit2(uint256(0xB0B), address(token), amount, 0, deadline);

        vm.expectRevert("Permit2: invalid signature");
        ISignatureTransfer(PERMIT2_ADDRESS).permitTransferFrom(
            _permit(address(token), amount, 0, deadline),
            _details(bob, amount),
            alice, // alice did NOT sign this
            sig
        );
    }

    // =============================================================
    // Integration: Permit2 → TokenBank.depositPermit2
    // =============================================================

    function test_Integration_DepositPermit2ThroughBank() public {
        uint256 amount = 500 * 10 ** 18;
        uint256 deadline = block.timestamp + 1 hours;

        bytes memory sig = _signPermit2(alicePrivateKey, address(token), amount, 0, deadline);

        vm.prank(address(0x5E1a6e5eA1ab));
        bank.depositPermit2(alice, address(token), amount, 0, deadline, sig);

        assertEq(bank.deposits(alice, address(token)), amount);
        assertEq(token.balanceOf(address(bank)), amount);
    }

    function test_Integration_RecordsUnderOwnerNotRelayer() public {
        uint256 amount = 300 * 10 ** 18;
        uint256 deadline = block.timestamp + 1 hours;

        bytes memory sig = _signPermit2(alicePrivateKey, address(token), amount, 0, deadline);

        vm.prank(bob);
        bank.depositPermit2(alice, address(token), amount, 0, deadline, sig);

        assertEq(bank.deposits(alice, address(token)), amount);
        assertEq(bank.deposits(bob, address(token)), 0);
    }

    function testFuzz_Integration_DepositPermit2(uint256 amount) public {
        amount = bound(amount, 1, INITIAL_SUPPLY);
        uint256 deadline = block.timestamp + 1 hours;

        bytes memory sig = _signPermit2(alicePrivateKey, address(token), amount, 0, deadline);

        bank.depositPermit2(alice, address(token), amount, 0, deadline, sig);

        assertEq(bank.deposits(alice, address(token)), amount);
    }
}
