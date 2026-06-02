// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script} from "forge-std/Script.sol";
import {CalledContract, Caller} from "../src/Call.sol";

contract CallScript is Script {
    CalledContract public calledContract;
    Caller public caller;

    function setUp() public {}

    function run() public {
        vm.startBroadcast();

        calledContract = new CalledContract();
        caller = new Caller();

        vm.stopBroadcast();
    }
}
