// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {Counter} from "../src/Counter.sol";
import {Proxy} from "../src/proxy.sol";

contract CounterV2 {
    uint256 public number;

    function setNumber(uint256 newNumber) public {
        number = newNumber;
    }

    function increment() public {
        number++;
    }

    function add(uint256 i) public {
        number = number +i;
    }
}

contract ProxyTest is Test {
    Counter public counter;
    Proxy public proxy;
    CounterV2 public counterV2;

    address public owner;

    function setUp() external {
        owner = makeAddr("owner");

        counter = new Counter();
        counterV2 = new CounterV2();

        vm.prank(owner);
        proxy = new Proxy(address(counter));
    }

    function test_UpgradeContract() public {
        // Proxy delegates to Counter — wrap proxy address as Counter to interact
        Counter proxyAsCounter = Counter(payable(address(proxy)));

        assertEq(proxyAsCounter.number(), 0);
        proxyAsCounter.setNumber(1);
        assertEq(proxyAsCounter.number(), 1);
        proxyAsCounter.increment();
        assertEq(proxyAsCounter.number(), 2);

        vm.prank(owner);
        proxy.upgrade(address(counterV2));

        CounterV2 proxyAsCounterV2 = CounterV2(payable(address(proxy)));
        proxyAsCounterV2.add(2);
        assertEq(proxyAsCounter.number(), 4);
    }
}