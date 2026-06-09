// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {BatchTransferDelegation} from "../src/delegation/BatchTransferDelegation.sol";
import {BrianICOToken} from "../src/token/BrianICOToken.sol";

contract BatchTransferDelegationTest is Test {
    BatchTransferDelegation public delegation;
    BrianICOToken public token;

    // Anvil default account #0 (0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266)
    uint256 internal alicePrivateKey = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;
    address internal alice;

    address internal bob = makeAddr("bob");
    address internal carol = makeAddr("carol");

    uint256 constant INITIAL_SUPPLY = 1_000_000 * 10 ** 18;

    function setUp() public {
        alice = vm.addr(alicePrivateKey);
        vm.label(alice, "alice");
        vm.label(bob, "bob");
        vm.label(carol, "carol");

        // Deploy delegation contract
        delegation = new BatchTransferDelegation();
        vm.label(address(delegation), "BatchTransferDelegation");

        // Deploy token — alice gets all initial supply
        vm.prank(alice);
        token = new BrianICOToken(INITIAL_SUPPLY);
        vm.label(address(token), "BrianICOToken");

        // Give bob and carol some ETH for gas
        vm.deal(bob, 100 ether);
        vm.deal(carol, 100 ether);
    }

    /// @dev Helper: sign and attach EIP-7702 delegation for alice
    function _delegateToAlice() internal {
        vm.signAndAttachDelegation(address(delegation), alicePrivateKey);
    }

    // =============================================================
    // Deployment & delegation
    // =============================================================

    function test_Deploy_DelegationContract() public view {
        // Just verify the contract deploys
        assertTrue(address(delegation) != address(0));
    }

    function test_Delegation_SetsCodeOnEOA() public {
        // Before delegation, alice has no code
        assertEq(address(alice).code.length, 0, "EOA should have no code");

        _delegateToAlice();

        // After delegation, alice has delegation code (0xef0100 || impl)
        bytes memory code = address(alice).code;
        assertGt(code.length, 0, "EOA should have delegation code");

        // Verify the 7702 delegation prefix
        assertEq(code[0], bytes1(0xef), "prefix byte 0");
        assertEq(code[1], bytes1(0x01), "prefix byte 1");
        assertEq(code[2], bytes1(0x00), "prefix byte 2");
    }

    function test_Delegation_AcceptETH() public {
        _delegateToAlice();

        // Send ETH to alice while delegated
        uint256 beforeBalance = address(alice).balance;
        vm.prank(bob);
        (bool ok,) = address(alice).call{value: 1 ether}("");
        assertTrue(ok, "ETH send to delegated EOA should succeed (receive fallback)");
        assertEq(address(alice).balance, beforeBalance + 1 ether);
    }

    // =============================================================
    // batchTransfer — ERC20
    // =============================================================

    function test_BatchTransfer_SingleTransfer() public {
        uint256 amount = 100 * 10 ** 18;

        _delegateToAlice();

        address[] memory tokens = new address[](1);
        tokens[0] = address(token);
        address[] memory recipients = new address[](1);
        recipients[0] = bob;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = amount;

        vm.prank(alice);
        bool[] memory results = BatchTransferDelegation(payable(alice)).batchTransfer(tokens, recipients, amounts);

        assertTrue(results[0], "transfer should succeed");
        assertEq(token.balanceOf(bob), amount);
        assertEq(token.balanceOf(alice), INITIAL_SUPPLY - amount);
    }

    function test_BatchTransfer_MultipleTransfers() public {
        uint256 amount1 = 100 * 10 ** 18;
        uint256 amount2 = 200 * 10 ** 18;
        uint256 amount3 = 50 * 10 ** 18;

        _delegateToAlice();

        address[] memory tokens = new address[](3);
        tokens[0] = address(token);
        tokens[1] = address(token);
        tokens[2] = address(token);

        address[] memory recipients = new address[](3);
        recipients[0] = bob;
        recipients[1] = carol;
        recipients[2] = bob; // bob gets twice

        uint256[] memory amounts = new uint256[](3);
        amounts[0] = amount1;
        amounts[1] = amount2;
        amounts[2] = amount3;

        vm.prank(alice);
        bool[] memory results = BatchTransferDelegation(payable(alice)).batchTransfer(tokens, recipients, amounts);

        assertTrue(results[0], "transfer 0");
        assertTrue(results[1], "transfer 1");
        assertTrue(results[2], "transfer 2");
        assertEq(token.balanceOf(bob), amount1 + amount3);
        assertEq(token.balanceOf(carol), amount2);
        assertEq(token.balanceOf(alice), INITIAL_SUPPLY - amount1 - amount2 - amount3);
    }

    function test_BatchTransfer_EmitsEvent() public {
        uint256 amount = 50 * 10 ** 18;

        _delegateToAlice();

        address[] memory tokens = new address[](1);
        tokens[0] = address(token);
        address[] memory recipients = new address[](1);
        recipients[0] = bob;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = amount;

        vm.expectEmit(true, false, false, true);
        emit BatchTransferDelegation.BatchTransferExecuted(alice, 1);

        vm.prank(alice);
        BatchTransferDelegation(payable(alice)).batchTransfer(tokens, recipients, amounts);
    }

    function test_BatchTransfer_LengthMismatchReverts() public {
        _delegateToAlice();

        address[] memory tokens = new address[](2);
        tokens[0] = address(token);
        tokens[1] = address(token);
        address[] memory recipients = new address[](1);
        recipients[0] = bob;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 100;

        vm.prank(alice);
        vm.expectRevert("BatchTransfer: length mismatch");
        BatchTransferDelegation(payable(alice)).batchTransfer(tokens, recipients, amounts);
    }

    function test_BatchTransfer_ZeroAmountSucceeds() public {
        _delegateToAlice();

        address[] memory tokens = new address[](1);
        tokens[0] = address(token);
        address[] memory recipients = new address[](1);
        recipients[0] = bob;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 0;

        vm.prank(alice);
        bool[] memory results = BatchTransferDelegation(payable(alice)).batchTransfer(tokens, recipients, amounts);

        // ERC20 transfer of 0 succeeds
        assertTrue(results[0], "zero transfer should succeed");
        assertEq(token.balanceOf(alice), INITIAL_SUPPLY);
    }

    function test_BatchTransfer_InsufficientBalanceReturnsFalse() public {
        uint256 tooMuch = INITIAL_SUPPLY + 1;

        _delegateToAlice();

        address[] memory tokens = new address[](1);
        tokens[0] = address(token);
        address[] memory recipients = new address[](1);
        recipients[0] = bob;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = tooMuch;

        vm.prank(alice);
        bool[] memory results = BatchTransferDelegation(payable(alice)).batchTransfer(tokens, recipients, amounts);

        // ERC20 transfer reverting would be caught; false means it didn't revert within the call
        assertFalse(results[0], "insufficient balance should fail");
    }

    // =============================================================
    // batchTransferETH
    // =============================================================

    function test_BatchTransferETH_SingleTransfer() public {
        uint256 amount = 1 ether;

        _delegateToAlice();

        // Give alice some ETH
        vm.deal(alice, 10 ether);

        address[] memory recipients = new address[](1);
        recipients[0] = bob;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = amount;

        uint256 bobBefore = address(bob).balance;

        vm.prank(alice);
        bool[] memory results = BatchTransferDelegation(payable(alice)).batchTransferETH(recipients, amounts);

        assertTrue(results[0], "ETH transfer should succeed");
        assertEq(address(bob).balance, bobBefore + amount);
    }

    function test_BatchTransferETH_MultipleTransfers() public {
        _delegateToAlice();
        vm.deal(alice, 10 ether);

        address[] memory recipients = new address[](3);
        recipients[0] = bob;
        recipients[1] = carol;
        recipients[2] = bob;

        uint256[] memory amounts = new uint256[](3);
        amounts[0] = 1 ether;
        amounts[1] = 2 ether;
        amounts[2] = 0.5 ether;

        uint256 bobBefore = address(bob).balance;
        uint256 carolBefore = address(carol).balance;

        vm.prank(alice);
        bool[] memory results = BatchTransferDelegation(payable(alice)).batchTransferETH(recipients, amounts);

        assertTrue(results[0], "transfer 0");
        assertTrue(results[1], "transfer 1");
        assertTrue(results[2], "transfer 2");
        assertEq(address(bob).balance, bobBefore + 1.5 ether);
        assertEq(address(carol).balance, carolBefore + 2 ether);
    }

    function test_BatchTransferETH_EmitsEvent() public {
        _delegateToAlice();
        vm.deal(alice, 10 ether);

        address[] memory recipients = new address[](1);
        recipients[0] = bob;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 1 ether;

        vm.expectEmit(true, false, false, true);
        emit BatchTransferDelegation.BatchTransferETHExecuted(alice, 1);

        vm.prank(alice);
        BatchTransferDelegation(payable(alice)).batchTransferETH(recipients, amounts);
    }

    function test_BatchTransferETH_InsufficientBalanceReturnsFalse() public {
        _delegateToAlice();
        // No ETH given to alice

        address[] memory recipients = new address[](1);
        recipients[0] = bob;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 1 ether;

        vm.prank(alice);
        bool[] memory results = BatchTransferDelegation(payable(alice)).batchTransferETH(recipients, amounts);

        assertFalse(results[0], "insufficient ETH should fail");
    }

    function test_BatchTransferETH_LengthMismatchReverts() public {
        _delegateToAlice();

        address[] memory recipients = new address[](2);
        recipients[0] = bob;
        recipients[1] = carol;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 1 ether;

        vm.prank(alice);
        vm.expectRevert("BatchTransfer: length mismatch");
        BatchTransferDelegation(payable(alice)).batchTransferETH(recipients, amounts);
    }

    // =============================================================
    // batchCall — arbitrary batch calls
    // =============================================================

    function test_BatchCall_SingleERC20Transfer() public {
        uint256 amount = 100 * 10 ** 18;

        _delegateToAlice();

        address[] memory targets = new address[](1);
        targets[0] = address(token);
        uint256[] memory values = new uint256[](1);
        values[0] = 0;
        bytes[] memory payloads = new bytes[](1);
        payloads[0] = abi.encodeWithSignature("transfer(address,uint256)", bob, amount);

        vm.prank(alice);
        bool[] memory results = BatchTransferDelegation(payable(alice)).batchCall(targets, values, payloads);

        assertTrue(results[0], "call should succeed");
        assertEq(token.balanceOf(bob), amount);
        assertEq(token.balanceOf(alice), INITIAL_SUPPLY - amount);
    }

    function test_BatchCall_SingleETHTransfer() public {
        uint256 amount = 1 ether;

        _delegateToAlice();
        vm.deal(alice, 10 ether);

        address[] memory targets = new address[](1);
        targets[0] = bob;
        uint256[] memory values = new uint256[](1);
        values[0] = amount;
        bytes[] memory payloads = new bytes[](1);
        payloads[0] = "";

        uint256 bobBefore = address(bob).balance;

        vm.prank(alice);
        bool[] memory results = BatchTransferDelegation(payable(alice)).batchCall(targets, values, payloads);

        assertTrue(results[0], "ETH transfer should succeed");
        assertEq(address(bob).balance, bobBefore + amount);
    }

    function test_BatchCall_MixedERC20AndETH() public {
        uint256 tokenAmount = 50 * 10 ** 18;
        uint256 ethAmount = 2 ether;

        _delegateToAlice();
        vm.deal(alice, 10 ether);

        address[] memory targets = new address[](2);
        targets[0] = address(token); // ERC20 transfer
        targets[1] = bob; // ETH transfer

        uint256[] memory values = new uint256[](2);
        values[0] = 0;
        values[1] = ethAmount;

        bytes[] memory payloads = new bytes[](2);
        payloads[0] = abi.encodeWithSignature("transfer(address,uint256)", bob, tokenAmount);
        payloads[1] = "";

        uint256 bobEthBefore = address(bob).balance;

        vm.prank(alice);
        bool[] memory results = BatchTransferDelegation(payable(alice)).batchCall(targets, values, payloads);

        assertTrue(results[0], "ERC20 call should succeed");
        assertTrue(results[1], "ETH call should succeed");
        assertEq(token.balanceOf(bob), tokenAmount);
        assertEq(address(bob).balance, bobEthBefore + ethAmount);
    }

    function test_BatchCall_ApproveAndTransfer() public {
        uint256 transferAmount = 30 * 10 ** 18;
        uint256 approveAmount = 100 * 10 ** 18;

        _delegateToAlice();

        // Batch two independent ERC20 operations:
        //   Call 1: transfer tokens to bob directly
        //   Call 2: approve carol to spend tokens (e.g. for a later DEX swap)
        address[] memory targets = new address[](2);
        targets[0] = address(token);
        targets[1] = address(token);
        uint256[] memory values = new uint256[](2);
        values[0] = 0;
        values[1] = 0;
        bytes[] memory payloads = new bytes[](2);
        payloads[0] = abi.encodeWithSignature("transfer(address,uint256)", bob, transferAmount);
        payloads[1] = abi.encodeWithSignature("approve(address,uint256)", carol, approveAmount);

        vm.prank(alice);
        bool[] memory results = BatchTransferDelegation(payable(alice)).batchCall(targets, values, payloads);

        assertTrue(results[0], "transfer should succeed");
        assertTrue(results[1], "approve should succeed");
        assertEq(token.balanceOf(bob), transferAmount);
        assertEq(token.allowance(alice, carol), approveAmount);
    }

    function test_BatchCall_EmitsEvent() public {
        _delegateToAlice();

        address[] memory targets = new address[](1);
        targets[0] = address(token);
        uint256[] memory values = new uint256[](1);
        values[0] = 0;
        bytes[] memory payloads = new bytes[](1);
        payloads[0] = abi.encodeWithSignature("transfer(address,uint256)", bob, 50 * 10 ** 18);

        vm.expectEmit(true, false, false, true);
        emit BatchTransferDelegation.BatchCallExecuted(alice, 1);

        vm.prank(alice);
        BatchTransferDelegation(payable(alice)).batchCall(targets, values, payloads);
    }

    function test_BatchCall_LengthMismatchReverts() public {
        _delegateToAlice();

        address[] memory targets = new address[](2);
        targets[0] = address(token);
        targets[1] = address(token);
        uint256[] memory values = new uint256[](1);
        values[0] = 0;
        bytes[] memory payloads = new bytes[](1);
        payloads[0] = "";

        vm.prank(alice);
        vm.expectRevert("BatchCall: length mismatch");
        BatchTransferDelegation(payable(alice)).batchCall(targets, values, payloads);
    }

    function test_BatchCall_PartialFailure() public {
        uint256 tooMuch = INITIAL_SUPPLY + 1;
        uint256 validAmount = 50 * 10 ** 18;

        _delegateToAlice();
        vm.deal(alice, 10 ether);

        address[] memory targets = new address[](3);
        targets[0] = address(token); // will succeed
        targets[1] = address(token); // will fail (insufficient balance)
        targets[2] = bob; // ETH — will succeed

        uint256[] memory values = new uint256[](3);
        values[0] = 0;
        values[1] = 0;
        values[2] = 1 ether;

        bytes[] memory payloads = new bytes[](3);
        payloads[0] = abi.encodeWithSignature("transfer(address,uint256)", bob, validAmount);
        payloads[1] = abi.encodeWithSignature("transfer(address,uint256)", bob, tooMuch);
        payloads[2] = "";

        uint256 bobEthBefore = address(bob).balance;

        vm.prank(alice);
        bool[] memory results = BatchTransferDelegation(payable(alice)).batchCall(targets, values, payloads);

        assertTrue(results[0], "call 0 should succeed");
        assertFalse(results[1], "call 1 should fail (insufficient balance)");
        assertTrue(results[2], "call 2 should succeed (ETH)");

        assertEq(token.balanceOf(bob), validAmount);
        assertEq(address(bob).balance, bobEthBefore + 1 ether);
    }

    function test_BatchCall_ZeroCallsSucceeds() public {
        _delegateToAlice();

        address[] memory targets = new address[](0);
        uint256[] memory values = new uint256[](0);
        bytes[] memory payloads = new bytes[](0);

        vm.prank(alice);
        bool[] memory results = BatchTransferDelegation(payable(alice)).batchCall(targets, values, payloads);

        assertEq(results.length, 0);
    }

    // =============================================================
    // Non-delegated EOA cannot execute batch transfer
    // =============================================================

    function test_NonDelegatedEOA_CannotCallBatchTransfer() public {
        // bob has no delegation — calling batchTransfer on his address should fail
        // (no code to execute)
        address[] memory tokens = new address[](1);
        tokens[0] = address(token);
        address[] memory recipients = new address[](1);
        recipients[0] = carol;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 100;

        vm.prank(bob);
        // Calling a non-delegated EOA with calldata should succeed but do nothing
        // (CALL to EOA always succeeds, returns empty data)
        (bool ok, bytes memory ret) = address(bob)
            .call(abi.encodeWithSelector(BatchTransferDelegation.batchTransfer.selector, tokens, recipients, amounts));
        // CALL to EOA succeeds but returns no data
        assertTrue(ok);
        assertEq(ret.length, 0);
    }

    // =============================================================
    // Fuzz tests
    // =============================================================

    function testFuzz_BatchTransferERC20_Amount(uint256 amount) public {
        amount = bound(amount, 1, INITIAL_SUPPLY);

        _delegateToAlice();

        address[] memory tokens = new address[](1);
        tokens[0] = address(token);
        address[] memory recipients = new address[](1);
        recipients[0] = bob;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = amount;

        vm.prank(alice);
        bool[] memory results = BatchTransferDelegation(payable(alice)).batchTransfer(tokens, recipients, amounts);

        assertTrue(results[0]);
        assertEq(token.balanceOf(bob), amount);
    }

    function testFuzz_BatchTransferETH_Amount(uint256 amount) public {
        amount = bound(amount, 0, 10 ether);

        _delegateToAlice();
        vm.deal(alice, 10 ether);

        address[] memory recipients = new address[](1);
        recipients[0] = bob;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = amount;

        uint256 aliceBefore = address(alice).balance;
        uint256 bobBefore = address(bob).balance;

        vm.prank(alice);
        bool[] memory results = BatchTransferDelegation(payable(alice)).batchTransferETH(recipients, amounts);

        // Check against pre-transfer balance, not post-transfer
        assertEq(results[0], amount <= aliceBefore ? true : false);
        if (results[0]) {
            assertEq(address(bob).balance, bobBefore + amount);
        }
    }
}
