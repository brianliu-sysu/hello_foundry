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

        vm.stopBroadcast();
    }
}