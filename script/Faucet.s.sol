// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {BaseScript} from "./BaseScript.sol";
import {Faucet} from "../src/Faucet.sol";

contract FaucetScript is BaseScript {
    Faucet public faucet;

    function run() public {
        broadcast();

        faucet = new Faucet{value: 0.05 ether}();
        saveDeployment("Faucet", address(faucet));

        vm.stopBroadcast();
    }
}
