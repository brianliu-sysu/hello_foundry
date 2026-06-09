// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script} from "forge-std/Script.sol";
import {Counter} from "../src/counter/Counter.sol";

contract CounterScript is Script {
    Counter public counter;

    function setUp() public {}

    function run() public {
        vm.startBroadcast();

        counter = new Counter();
        _save("Counter", address(counter));

        vm.stopBroadcast();
    }

    function _save(string memory name, address addr) internal {
        string memory chainId = vm.toString(block.chainid);
        string memory dir = string.concat("deploy/", chainId);
        vm.createDir(dir, true);
        string memory objKey = "deployment";
        vm.serializeString(objKey, "name", name);
        vm.serializeString(objKey, "address", vm.toString(addr));
        string memory json = vm.serializeString(objKey, "chainId", chainId);
        vm.writeJson(json, string.concat(dir, "/", name, ".json"));
    }
}
