// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {BaseScript} from "./BaseScript.sol";
import {BrianICOToken} from "../src/token/BrianICOToken.sol";

contract BrianICOTokenScript is BaseScript {
    BrianICOToken public brianICOToken;

    function run() public {
        broadcast();

        brianICOToken = new BrianICOToken(1000000000000000000000000);
        saveDeployment("BrianICOToken", address(brianICOToken));

        vm.stopBroadcast();
    }
}