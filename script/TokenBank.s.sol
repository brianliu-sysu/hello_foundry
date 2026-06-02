// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {BaseScript} from "./BaseScript.sol";
import {TokenBank} from "../src/TokenBank.sol";

contract TokenBankScript is BaseScript {
    TokenBank public tokenBank;

    function run() public {
        broadcast();

        tokenBank = new TokenBank();

        vm.stopBroadcast();
    }
}
