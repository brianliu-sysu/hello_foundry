// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {BaseScript} from "./BaseScript.sol";
import {BrianNFT} from "../src/BrianNFT.sol";

contract BrianNFTScript is BaseScript {
    BrianNFT public brianNft;

    function run() public {
        broadcast();

        brianNft = new BrianNFT(
            "BrianNFT",                        // name
            "BNFT",                            // symbol
            "ipfs://",                         // baseTokenURI
            10000                              // maxSupply（0 表示无上限）
        );
        saveDeployment("BrianNFT", address(brianNft));

        vm.stopBroadcast();
    }
}
