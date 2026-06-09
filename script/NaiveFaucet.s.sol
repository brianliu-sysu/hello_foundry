// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script} from "forge-std/Script.sol";
import {NaiveFaucet} from "../src/token/NaiveFaucet.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract NaiveFaucetScript is Script {
    NaiveFaucet public naiveFaucet;

    function setUp() public {}

    function run() public {
        vm.startBroadcast();

        naiveFaucet = new NaiveFaucet(
            IERC20(0x6A4D5E39973b172143E94f73916E681B2F3aA639), 0xbf39fED2aEFDA4e90cBfce3BD536932A0C18CA58
        );
        _save("NaiveFaucet", address(naiveFaucet));

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
