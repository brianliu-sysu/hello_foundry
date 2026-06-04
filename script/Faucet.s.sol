// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script} from "forge-std/Script.sol";
import {Faucet} from "../src/faucet.sol";

contract FaucetScript is Script {
    Faucet public faucet;

    function setUp() public {}

    function run() public {
        vm.startBroadcast();

        faucet = new Faucet();
        _save("Faucet", address(faucet));

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