// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {Faucet} from "../src/Faucet.sol";
import {GasSponsorDelegation} from "../src/GasSponsorDelegation.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @notice 简易 Mock ERC20，供 GasSponsor token 测试使用
contract MockERC20 is IERC20 {
    mapping(address => uint256) public override balanceOf;
    mapping(address => mapping(address => uint256)) public override allowance;
    uint256 public override totalSupply;

    string public name = "Mock";
    string public symbol = "MCK";
    uint8 public decimals = 18;

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
        totalSupply += amount;
        emit Transfer(address(0), to, amount);
    }

    function transfer(address to, uint256 amount) external override returns (bool) {
        require(balanceOf[msg.sender] >= amount, "ERC20: insufficient balance");
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        emit Transfer(msg.sender, to, amount);
        return true;
    }

    function approve(address spender, uint256 amount) external override returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external override returns (bool) {
        require(allowance[from][msg.sender] >= amount, "ERC20: insufficient allowance");
        require(balanceOf[from] >= amount, "ERC20: insufficient balance");
        allowance[from][msg.sender] -= amount;
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        emit Transfer(from, to, amount);
        return true;
    }
}

contract GasSponsorDelegationTest is Test {
    GasSponsorDelegation public delegation;
    Faucet public faucet;
    MockERC20 public mockToken;

    // Anvil default account #0
    uint256 internal alicePrivateKey = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;
    address internal alice;

    address internal relayer = makeAddr("relayer");
    address internal bob = makeAddr("bob");

    uint256 constant FAUCET_ETH = 1 ether;
    uint256 constant FAUCET_TOKENS = 1000 ether; // 1000 tokens for testing

    function setUp() public {
        alice = vm.addr(alicePrivateKey);
        vm.label(alice, "alice");
        vm.label(relayer, "relayer");
        vm.label(bob, "bob");

        // Deploy GasSponsorDelegation
        delegation = new GasSponsorDelegation();
        vm.label(address(delegation), "GasSponsorDelegation");

        // Deploy Faucet with ETH
        vm.deal(address(this), 10 ether);
        faucet = new Faucet{value: FAUCET_ETH}();
        vm.label(address(faucet), "Faucet");

        // Deploy MockERC20 and configure faucet
        mockToken = new MockERC20();
        mockToken.mint(address(faucet), FAUCET_TOKENS);
        faucet.setToken(address(mockToken));
        vm.label(address(mockToken), "MockERC20");
    }

    /// @dev Helper: sign and attach EIP-7702 delegation for alice
    function _delegateToAlice() internal {
        vm.signAndAttachDelegation(address(delegation), alicePrivateKey);
    }

    // ═══════════════════════════════════════════════════════════════
    // Deployment & EIP-7702 delegation
    // ═══════════════════════════════════════════════════════════════

    function test_Deploy() public view {
        assertTrue(address(delegation) != address(0));
        assertEq(delegation.ETH_CLAIM_LIMIT(), 0.01 ether);
        assertEq(delegation.TOKEN_CLAIM_LIMIT(), 10 ether);
        assertEq(delegation.MAX_FEE_BPS(), 1000);
    }

    function test_AttachDelegation_SetsEIP7702Code() public {
        assertEq(address(alice).code.length, 0, "EOA should have no code");
        _delegateToAlice();
        assertGt(address(alice).code.length, 0, "EOA should have delegation code");
        // 7702 prefix: 0xef0100
        bytes memory code = address(alice).code;
        assertEq(code[0], bytes1(0xef));
        assertEq(code[1], bytes1(0x01));
        assertEq(code[2], bytes1(0x00));
    }

    // ═══════════════════════════════════════════════════════════════
    // claimETH
    // ═══════════════════════════════════════════════════════════════

    function test_ClaimETH_Success() public {
        _delegateToAlice();
        uint256 feeBps = 100; // 1%

        uint256 aliceBefore = alice.balance;
        uint256 relayerBefore = relayer.balance;

        // Relayer calls alice's EOA to claim
        vm.prank(relayer);
        GasSponsorDelegation(payable(alice)).claimETH(address(faucet), relayer, feeBps);

        uint256 claimed = 0.01 ether;
        uint256 fee = (claimed * feeBps) / 10000; // 0.0001 ETH
        uint256 net = claimed - fee;

        assertEq(alice.balance - aliceBefore, net, "alice should receive net claim");
        assertEq(relayer.balance - relayerBefore, fee, "relayer should receive fee");
        assertEq(address(faucet).balance, FAUCET_ETH - claimed, "faucet balance reduced");
    }

    function test_ClaimETH_ZeroFee() public {
        _delegateToAlice();
        uint256 aliceBefore = alice.balance;

        vm.prank(relayer);
        GasSponsorDelegation(payable(alice)).claimETH(address(faucet), relayer, 0);

        // alice gets full 0.01 ETH
        assertEq(alice.balance - aliceBefore, 0.01 ether);
    }

    function test_ClaimETH_MaxFee() public {
        _delegateToAlice();
        uint256 feeBps = 1000; // 10% max

        vm.prank(relayer);
        GasSponsorDelegation(payable(alice)).claimETH(address(faucet), relayer, feeBps);

        uint256 fee = (0.01 ether * feeBps) / 10000;
        assertEq(relayer.balance, fee); // relayer had 0 before
    }

    function test_ClaimETH_EmitsEvent() public {
        _delegateToAlice();

        vm.expectEmit(true, true, true, true);
        uint256 fee = (0.01 ether * 50) / 10000;
        emit GasSponsorDelegation.ETHClaimed(alice, 0.01 ether, relayer, fee);

        vm.prank(relayer);
        GasSponsorDelegation(payable(alice)).claimETH(address(faucet), relayer, 50);
    }

    function test_ClaimETH_RevertsWhenFeeTooHigh() public {
        _delegateToAlice();

        vm.prank(relayer);
        vm.expectRevert("fee too high");
        GasSponsorDelegation(payable(alice)).claimETH(address(faucet), relayer, 1001);
    }

    function test_ClaimETH_RevertsWhenRelayerIsZero() public {
        _delegateToAlice();

        vm.prank(relayer);
        vm.expectRevert("relayer is zero");
        GasSponsorDelegation(payable(alice)).claimETH(address(faucet), address(0), 0);
    }

    function test_ClaimETH_CooldownEnforced() public {
        _delegateToAlice();

        // First claim: success
        vm.prank(relayer);
        GasSponsorDelegation(payable(alice)).claimETH(address(faucet), relayer, 0);

        // Second claim within cooldown: reverts
        vm.prank(relayer);
        vm.expectRevert("Withdraw limited to once per day");
        GasSponsorDelegation(payable(alice)).claimETH(address(faucet), relayer, 0);
    }

    function test_ClaimETH_SucceedsAfterCooldown() public {
        _delegateToAlice();

        vm.prank(relayer);
        GasSponsorDelegation(payable(alice)).claimETH(address(faucet), relayer, 0);

        // Warp 1 day forward
        vm.warp(block.timestamp + 1 days);

        // Second claim now succeeds
        vm.prank(relayer);
        GasSponsorDelegation(payable(alice)).claimETH(address(faucet), relayer, 0);
    }

    function test_ClaimETH_DifferentUsersIndependent() public {
        _delegateToAlice(); // Only alice delegates

        // Alice claims through delegation
        vm.prank(relayer);
        GasSponsorDelegation(payable(alice)).claimETH(address(faucet), relayer, 0);

        // Bob has a different EOA (no delegation), can still call withdraw directly
        vm.deal(bob, 0.1 ether); // bob needs some gas ETH to make the call
        vm.prank(bob);
        faucet.withdraw(0.01 ether, payable(bob));
    }

    function test_ClaimETH_NonDelegatedEOACannotCall() public {
        // bob has no delegation — calling claimETH on his address should do nothing
        vm.prank(relayer);
        (bool ok, bytes memory ret) = address(bob).call(
            abi.encodeWithSelector(GasSponsorDelegation.claimETH.selector, address(faucet), relayer, 0)
        );
        assertTrue(ok, "call to non-delegated EOA should succeed (no-op)");
        assertEq(ret.length, 0, "non-delegated EOA returns empty data");
    }

    function test_ClaimETH_RevertsWhenFaucetHasInsufficientBalance() public {
        // Deploy a faucet with very little ETH
        Faucet tinyFaucet = new Faucet{value: 0.001 ether}();

        _delegateToAlice();

        vm.prank(relayer);
        vm.expectRevert(); // transfer fails (0.01 > 0.001)
        GasSponsorDelegation(payable(alice)).claimETH(address(tinyFaucet), relayer, 0);
    }

    // ═══════════════════════════════════════════════════════════════
    // claimToken
    // ═══════════════════════════════════════════════════════════════

    function test_ClaimToken_Success() public {
        _delegateToAlice();
        uint256 feeBps = 200; // 2%

        // Relayer claims tokens on alice's behalf
        vm.prank(relayer);
        GasSponsorDelegation(payable(alice)).claimToken(address(faucet), relayer, feeBps);

        uint256 claimed = 10 ether;
        uint256 fee = (claimed * feeBps) / 10000;
        uint256 net = claimed - fee;

        assertEq(mockToken.balanceOf(alice), net, "alice should receive net tokens");
        assertEq(mockToken.balanceOf(relayer), fee, "relayer should receive fee");
        assertEq(mockToken.balanceOf(address(faucet)), FAUCET_TOKENS - claimed, "faucet reduced");
    }

    function test_ClaimToken_ZeroFee() public {
        _delegateToAlice();

        vm.prank(relayer);
        GasSponsorDelegation(payable(alice)).claimToken(address(faucet), relayer, 0);

        assertEq(mockToken.balanceOf(alice), 10 ether);
        assertEq(mockToken.balanceOf(relayer), 0);
    }

    function test_ClaimToken_EmitsEvent() public {
        _delegateToAlice();

        uint256 feeBps = 50;
        uint256 fee = (10 ether * feeBps) / 10000;

        vm.expectEmit(true, true, true, true);
        emit GasSponsorDelegation.TokenClaimed(alice, 10 ether, relayer, fee);

        vm.prank(relayer);
        GasSponsorDelegation(payable(alice)).claimToken(address(faucet), relayer, feeBps);
    }

    function test_ClaimToken_RevertsWhenFeeTooHigh() public {
        _delegateToAlice();

        vm.prank(relayer);
        vm.expectRevert("fee too high");
        GasSponsorDelegation(payable(alice)).claimToken(address(faucet), relayer, 1001);
    }

    function test_ClaimToken_RevertsWhenRelayerIsZero() public {
        _delegateToAlice();

        vm.prank(relayer);
        vm.expectRevert("relayer is zero");
        GasSponsorDelegation(payable(alice)).claimToken(address(faucet), address(0), 0);
    }

    function test_ClaimToken_CooldownEnforced() public {
        _delegateToAlice();

        vm.prank(relayer);
        GasSponsorDelegation(payable(alice)).claimToken(address(faucet), relayer, 0);

        vm.prank(relayer);
        vm.expectRevert("Token withdraw limited to once per day");
        GasSponsorDelegation(payable(alice)).claimToken(address(faucet), relayer, 0);
    }

    function test_ClaimToken_SucceedsAfterCooldown() public {
        _delegateToAlice();

        vm.prank(relayer);
        GasSponsorDelegation(payable(alice)).claimToken(address(faucet), relayer, 0);

        vm.warp(block.timestamp + 1 days);

        vm.prank(relayer);
        GasSponsorDelegation(payable(alice)).claimToken(address(faucet), relayer, 0);
    }

    function test_ClaimToken_RevertsWhenFaucetTokenNotSet() public {
        // Deploy a faucet without token configured
        Faucet faucet2 = new Faucet{value: 0 ether}();

        _delegateToAlice();

        vm.prank(relayer);
        vm.expectRevert("faucet token not set");
        GasSponsorDelegation(payable(alice)).claimToken(address(faucet2), relayer, 0);
    }

    // ═══════════════════════════════════════════════════════════════
    // ETH + Token independence (cooldowns are separate)
    // ═══════════════════════════════════════════════════════════════

    function test_ClaimETHAndClaimToken_IndependentCooldowns() public {
        _delegateToAlice();

        // Claim ETH
        vm.prank(relayer);
        GasSponsorDelegation(payable(alice)).claimETH(address(faucet), relayer, 0);

        // Claim Token immediately — should work (different cooldown)
        vm.prank(relayer);
        GasSponsorDelegation(payable(alice)).claimToken(address(faucet), relayer, 0);

        assertEq(mockToken.balanceOf(alice), 10 ether);
    }

    // ═══════════════════════════════════════════════════════════════
    // receive ETH
    // ═══════════════════════════════════════════════════════════════

    function test_ReceiveETH_WhileDelegated() public {
        _delegateToAlice();

        vm.deal(bob, 1 ether);
        uint256 beforeBalance = alice.balance;
        vm.prank(bob);
        (bool ok,) = address(alice).call{value: 1 ether}("");
        assertTrue(ok);
        assertEq(alice.balance, beforeBalance + 1 ether);
    }

    // ═══════════════════════════════════════════════════════════════
    // Fuzz tests
    // ═══════════════════════════════════════════════════════════════

    function testFuzz_ClaimETH_FeeBps(uint256 feeBps) public {
        feeBps = bound(feeBps, 0, 1000);
        _delegateToAlice();

        uint256 aliceBefore = alice.balance;

        vm.prank(relayer);
        GasSponsorDelegation(payable(alice)).claimETH(address(faucet), relayer, feeBps);

        uint256 claimed = 0.01 ether;
        uint256 fee = (claimed * feeBps) / 10000;
        assertEq(alice.balance - aliceBefore, claimed - fee);
    }

    function testFuzz_ClaimToken_FeeBps(uint256 feeBps) public {
        feeBps = bound(feeBps, 0, 1000);
        _delegateToAlice();

        vm.prank(relayer);
        GasSponsorDelegation(payable(alice)).claimToken(address(faucet), relayer, feeBps);

        uint256 claimed = 10 ether;
        uint256 fee = (claimed * feeBps) / 10000;
        assertEq(mockToken.balanceOf(alice), claimed - fee);
    }
}
