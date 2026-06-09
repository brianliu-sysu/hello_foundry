// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Owner, Pausable, Faucet} from "../src/token/Faucet.sol";

/// @notice 简易 Mock ERC20，供 Faucet token 提款测试使用
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
        MockERC20 public mockToken;

        address public alice = makeAddr("alice");
        address public bob = makeAddr("bob");

        // withdraw 上限为 0.01 ether，每个地址每天限提款一次
        uint256 constant MAX_WITHDRAW = 0.01 ether;
        // token withdraw 上限为 10 枚代币
        uint256 constant MAX_TOKEN_WITHDRAW = 10 ether;

        function setUp() public {
            vm.deal(address(this), 10 ether);
            faucet = new Faucet{value: 1 ether}();

            // 部署 MockERC20 并配置 Faucet
            mockToken = new MockERC20();
            faucet.setToken(address(mockToken));

            // 给 Faucet 转入 1000 枚代币
            mockToken.mint(address(faucet), 1000 ether);
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
        // withdraw（限额 0.01 ether，每个地址每天一次）
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

        function testFuzz_Faucet_Withdraw_Amount(uint256 amount) public {
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

        function test_Faucet_Withdraw_RevertsWhenWithinCooldown() public {
            uint256 amount = 0.005 ether;

            // 第一次提款 — 成功
            vm.prank(alice);
            faucet.withdraw(amount, payable(alice));

            // 同一地址同一天内第二次提款 — 失败
            vm.prank(alice);
            vm.expectRevert("Withdraw limited to once per day");
            faucet.withdraw(amount, payable(alice));
        }

        function test_Faucet_Withdraw_DifferentAddressesIndependent() public {
            uint256 amount = 0.005 ether;

            // alice 提款 — 成功
            vm.prank(alice);
            faucet.withdraw(amount, payable(alice));

            // bob 提款 — 不受 alice 影响，也成功
            vm.prank(bob);
            faucet.withdraw(amount, payable(bob));
        }

        function test_Faucet_Withdraw_SucceedsAfterCooldown() public {
            uint256 amount = 0.005 ether;

            // 第一次提款
            vm.prank(alice);
            faucet.withdraw(amount, payable(alice));

            // 快进一天
            vm.warp(block.timestamp + 1 days);

            // 同一地址可以再次提款
            vm.prank(alice);
            faucet.withdraw(amount, payable(alice));
        }

        function test_Faucet_Withdraw_RevertsStillInCooldownAfter23Hours() public {
            uint256 amount = 0.005 ether;

            vm.prank(alice);
            faucet.withdraw(amount, payable(alice));

            // 快进 23 小时 — 还不够
            vm.warp(block.timestamp + 23 hours);

            vm.prank(alice);
            vm.expectRevert("Withdraw limited to once per day");
            faucet.withdraw(amount, payable(alice));
        }

        // =============================================================
        // withdrawToken（上限 10 枚，每个地址每天一次）
        // =============================================================

        function test_Faucet_WithdrawToken_SendsTokens() public {
            uint256 amount = 5 ether;

            vm.prank(bob);
            faucet.withdrawToken(amount);

            assertEq(mockToken.balanceOf(bob), amount);
            assertEq(mockToken.balanceOf(address(faucet)), 1000 ether - amount);
        }

        function test_Faucet_WithdrawToken_MaxAmount() public {
            uint256 amount = MAX_TOKEN_WITHDRAW; // 10 tokens

            vm.prank(bob);
            faucet.withdrawToken(amount);

            assertEq(mockToken.balanceOf(bob), amount);
        }

        function test_Faucet_WithdrawToken_EmitsEvent() public {
            uint256 amount = 3 ether;

            vm.expectEmit(true, true, false, true);
            emit Faucet.TokenWithdrawal(bob, amount);

            vm.prank(bob);
            faucet.withdrawToken(amount);
        }

        function test_Faucet_WithdrawToken_RevertsWhenAmountTooLarge() public {
            vm.prank(bob);
            vm.expectRevert("Token withdraw amount exceeds limit");
            faucet.withdrawToken(MAX_TOKEN_WITHDRAW + 1);
        }

        function test_Faucet_WithdrawToken_RevertsWhenWithinCooldown() public {
            uint256 amount = 3 ether;

            vm.prank(bob);
            faucet.withdrawToken(amount); // 第一次成功

            vm.prank(bob);
            vm.expectRevert("Token withdraw limited to once per day");
            faucet.withdrawToken(amount); // 第二次失败
        }

        function test_Faucet_WithdrawToken_DifferentAddressesIndependent() public {
            uint256 amount = 5 ether;

            vm.prank(alice);
            faucet.withdrawToken(amount); // alice 成功

            vm.prank(bob);
            faucet.withdrawToken(amount); // bob 不受 alice 影响
        }

        function test_Faucet_WithdrawToken_SucceedsAfterCooldown() public {
            uint256 amount = 4 ether;

            vm.prank(bob);
            faucet.withdrawToken(amount);

            vm.warp(block.timestamp + 1 days);

            vm.prank(bob);
            faucet.withdrawToken(amount); // 一天后可再提
        }

        function test_Faucet_WithdrawToken_RevertsStillInCooldownAfter23Hours() public {
            uint256 amount = 2 ether;

            vm.prank(bob);
            faucet.withdrawToken(amount);

            vm.warp(block.timestamp + 23 hours);

            vm.prank(bob);
            vm.expectRevert("Token withdraw limited to once per day");
            faucet.withdrawToken(amount);
        }

        function test_Faucet_WithdrawToken_ETHCooldownIndependent() public {
            uint256 ethAmount = 0.005 ether;
            uint256 tokenAmount = 3 ether;

            // bob 提 ETH 后仍可立即提代币（冷却独立）
            vm.prank(bob);
            faucet.withdraw(ethAmount, payable(bob));

            vm.prank(bob);
            faucet.withdrawToken(tokenAmount); // 不应被 ETH 冷却阻止

            assertEq(mockToken.balanceOf(bob), tokenAmount);
        }

        function test_Faucet_WithdrawToken_RevertsWhenPaused() public {
            faucet.pause();

            vm.prank(bob);
            vm.expectRevert("Contract is paused");
            faucet.withdrawToken(1 ether);
        }

        function test_Faucet_WithdrawToken_RevertsWhenTokenNotSet() public {
            Faucet faucet2 = new Faucet{value: 0 ether}();

            vm.expectRevert("Token not set");
            faucet2.withdrawToken(1 ether);
        }

        // =============================================================
        // adminWithdrawToken
        // =============================================================

        function test_Faucet_AdminWithdrawToken_RecoversAllTokens() public {
            uint256 faucetBalance = mockToken.balanceOf(address(faucet));

            faucet.adminWithdrawToken();

            assertEq(mockToken.balanceOf(address(faucet)), 0);
            assertEq(mockToken.balanceOf(address(this)), faucetBalance);
        }

        function test_Faucet_AdminWithdrawToken_RevertsWhenNotOwner() public {
            vm.prank(bob);
            vm.expectRevert("Only owner can call this function");
            faucet.adminWithdrawToken();
        }

        function test_Faucet_AdminWithdrawToken_RevertsWhenZeroBalance() public {
            // 先提回所有代币，再调用就应为 0
            faucet.adminWithdrawToken();

            vm.expectRevert("No tokens to withdraw");
            faucet.adminWithdrawToken();
        }

        function test_Faucet_SetToken_RevertsWhenNotOwner() public {
            vm.prank(bob);
            vm.expectRevert("Only owner can call this function");
            faucet.setToken(address(0x123));
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
            (bool ok,) = address(faucet).call{value: 0.5 ether}("");
            assertTrue(ok);
        }

        function test_Faucet_Fallback_AcceptsEtherWithData() public {
            vm.deal(alice, 0.1 ether);

            vm.prank(alice);
            (bool ok,) = address(faucet).call{value: 0.1 ether}(abi.encodeWithSignature("randomFunction()"));
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
