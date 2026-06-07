// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {CounterV1Upgradeable} from "../src/CounterV1Upgradeable.sol";
import {CounterV2Upgradeable} from "../src/CounterV2Upgradeable.sol";

contract CounterUUPSTest is Test {
    CounterV1Upgradeable public implV1;
    CounterV2Upgradeable public implV2;
    ERC1967Proxy public proxy;
    CounterV1Upgradeable public proxyAsV1; // proxy 当作 V1 交互
    CounterV2Upgradeable public proxyAsV2; // proxy 当作 V2 交互

    address public owner = makeAddr("owner");
    address public attacker = makeAddr("attacker");

    function setUp() public {
        // 1. 部署 V1 实现
        implV1 = new CounterV1Upgradeable();
        // 2. 部署 ERC1967Proxy，指向 V1，传入 initialize() calldata
        vm.prank(owner);
        proxy = new ERC1967Proxy(
            address(implV1),
            abi.encodeCall(CounterV1Upgradeable.initialize, ())
        );
        proxyAsV1 = CounterV1Upgradeable(address(proxy));
        proxyAsV2 = CounterV2Upgradeable(address(proxy));
    }

    // ═══════════════════════════════════════════════════════════════
    // V1 基础功能
    // ═══════════════════════════════════════════════════════════════

    function test_V1_InitializeSetsOwner() public view {
        assertEq(proxyAsV1.owner(), owner);
    }

    function test_V1_InitialNumberIsZero() public view {
        assertEq(proxyAsV1.number(), 0);
    }

    function test_V1_SetNumber() public {
        proxyAsV1.setNumber(42);
        assertEq(proxyAsV1.number(), 42);
    }

    function test_V1_Increment() public {
        proxyAsV1.setNumber(10);
        proxyAsV1.increment();
        assertEq(proxyAsV1.number(), 11);
    }

    function test_V1_ImplementationIsV1() public view {
        // 代理的 implementation slot 指向 V1
        bytes32 implSlot = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
        bytes32 value = vm.load(address(proxy), implSlot);
        assertEq(address(uint160(uint256(value))), address(implV1));
    }

    // ═══════════════════════════════════════════════════════════════
    // UUPS 升级
    // ═══════════════════════════════════════════════════════════════

    function test_Upgrade_ChangesImplementation() public {
        // 部署 V2
        implV2 = new CounterV2Upgradeable();

        vm.prank(owner);
        proxyAsV1.upgradeToAndCall(address(implV2), "");

        // 验证 implementation slot 变为 V2
        bytes32 implSlot = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
        bytes32 value = vm.load(address(proxy), implSlot);
        assertEq(address(uint160(uint256(value))), address(implV2));
    }

    function test_Upgrade_PreservesState() public {
        // V1 中 setNumber
        proxyAsV1.setNumber(77);
        proxyAsV1.increment(); // 78

        // 升级到 V2
        implV2 = new CounterV2Upgradeable();
        vm.prank(owner);
        proxyAsV1.upgradeToAndCall(address(implV2), "");

        // 状态保留
        assertEq(proxyAsV2.number(), 78);
        assertEq(proxyAsV2.owner(), owner);
    }

    function test_Upgrade_V2MethodsWorkAfterUpgrade() public {
        proxyAsV1.setNumber(50);

        // 升级
        implV2 = new CounterV2Upgradeable();
        vm.prank(owner);
        proxyAsV1.upgradeToAndCall(address(implV2), "");

        // V2 新增方法
        proxyAsV2.add(20);
        assertEq(proxyAsV2.number(), 70);

        proxyAsV2.decrement();
        assertEq(proxyAsV2.number(), 69);

        // V1 原有方法仍然可用
        proxyAsV2.increment();
        assertEq(proxyAsV2.number(), 70);
    }

    function test_Upgrade_RevertsWhenNotOwner() public {
        implV2 = new CounterV2Upgradeable();

        vm.prank(attacker);
        vm.expectRevert(); // OwnableUnauthorizedAccount
        proxyAsV1.upgradeToAndCall(address(implV2), "");
    }

    function test_Upgrade_RevertsWhenUpgradingToNonUUPS() public {
        // 不能升级到一个没有实现 UUPS 的地址
        vm.prank(owner);
        vm.expectRevert();
        proxyAsV1.upgradeToAndCall(address(0xdead), "");
    }

    // ═══════════════════════════════════════════════════════════════
    // V2 特定方法在升级前不可用
    // ═══════════════════════════════════════════════════════════════

    function test_V1_CannotCallDecrement() public {
        proxyAsV1.setNumber(5);
        // V1 没有 decrement→ eth_call 会 revert
        vm.expectRevert();
        proxyAsV2.decrement();
    }

    function test_V1_CannotCallAdd() public {
        // V1 没有 add → eth_call 会 revert
        vm.expectRevert();
        proxyAsV2.add(10);
    }

    // ═══════════════════════════════════════════════════════════════
    // 完整流程
    // ═══════════════════════════════════════════════════════════════

    function test_FullUpgradeFlow() public {
        // 1. V1: 操作
        proxyAsV1.setNumber(100);
        proxyAsV1.increment();
        assertEq(proxyAsV1.number(), 101);

        // 2. 升级到 V2
        implV2 = new CounterV2Upgradeable();
        vm.prank(owner);
        proxyAsV1.upgradeToAndCall(address(implV2), "");

        // 3. V2: 状态保留 + 新方法可用
        assertEq(proxyAsV2.number(), 101);        // 状态保留
        proxyAsV2.add(50);
        assertEq(proxyAsV2.number(), 151);        // V2 add 可用
        proxyAsV2.decrement();
        assertEq(proxyAsV2.number(), 150);        // V2 decrement 可用
        proxyAsV2.increment();
        assertEq(proxyAsV2.number(), 151);        // V1 旧方法仍可用
    }
}
