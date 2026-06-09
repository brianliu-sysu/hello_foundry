// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script} from "forge-std/Script.sol";
import {CalledContract, Caller} from "../src/utils/Call.sol";

contract CallScript is Script {
    CalledContract public calledContract;
    Caller public caller;

    function setUp() public {}

    function run() public {
        vm.startBroadcast();

        calledContract = new CalledContract();
        _save("CalledContract", address(calledContract));
        caller = new Caller();
        _save("Caller", address(caller));

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
