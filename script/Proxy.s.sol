// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {BaseScript} from "./BaseScript.sol";
import {Proxy} from "../src/proxy.sol";
import {Counter} from "../src/Counter.sol";

contract ProxyScript is BaseScript {
    Proxy public proxy;
    Counter public counter;

    function run() public {
        broadcast();

        counter = new Counter();
        saveDeployment("Counter", address(counter));


        proxy = new Proxy(address(counter));
        saveDeployment("Proxy", address(proxy));

        vm.stopBroadcast();
    }
}