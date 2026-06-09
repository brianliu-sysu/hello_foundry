// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {BaseScript} from "./BaseScript.sol";
import {console2} from "forge-std/console2.sol";
import {DeflationaryToken} from "../src/token/DeflationaryToken.sol";

/// @notice 部署 DeflationaryToken（初始 1 亿 DFL，每日通缩 1%）
///
/// 用法：
///   forge script script/DeployDeflationaryToken.s.sol --rpc-url <RPC> --broadcast
contract DeployDeflationaryTokenScript is BaseScript {
    DeflationaryToken public token;

    function run() public {
        broadcast();

        uint256 initialSupply = 100_000_000 ether; // 1 亿
        token = new DeflationaryToken(initialSupply);
        saveDeployment("DeflationaryToken", address(token));

        vm.stopBroadcast();

        console2.log("============================================");
        console2.log("DeflationaryToken Deployment Summary");
        console2.log("============================================");
        console2.log("Token:   ", address(token));
        console2.log("Supply:  ", token.totalSupply());
        console2.log("Symbol:  ", token.symbol());
    }
}
