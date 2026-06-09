// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {BaseScript} from "./BaseScript.sol";
import {GasSponsorDelegation} from "../src/delegation/GasSponsorDelegation.sol";

contract GasSponsorDelegationScript is BaseScript {
    GasSponsorDelegation public delegation;

    function run() public {
        broadcast();

        delegation = new GasSponsorDelegation();
        saveDeployment("GasSponsorDelegation", address(delegation));

        vm.stopBroadcast();
    }
}
