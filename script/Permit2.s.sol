// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {BaseScript} from "./BaseScript.sol";
import {Permit2} from "../src/Permit2.sol";

/// @notice Deploy Permit2 contract.
/// @dev    For local Anvil, use `vm.etch()` to place it at the canonical address
///         (0x000000000022D473030F116dDEE9F6B43aC78BA3). On testnets, the real
///         Uniswap Permit2 is already deployed at that address — this script
///         deploys a standalone instance for custom networks.
contract Permit2Script is BaseScript {
    Permit2 public permit2;

    function run() public {
        broadcast();

        permit2 = new Permit2(deployer);
        saveDeployment("Permit2", address(permit2));

        vm.stopBroadcast();
    }
}
