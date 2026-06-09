// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {BaseScript} from "./BaseScript.sol";
import {BatchTransferDelegation} from "../src/delegation/BatchTransferDelegation.sol";

contract BatchTransferDelegationScript is BaseScript {
    BatchTransferDelegation public delegation;

    function run() public {
        broadcast();

        delegation = new BatchTransferDelegation();
        saveDeployment("BatchTransferDelegation", address(delegation));

        vm.stopBroadcast();
    }
}
