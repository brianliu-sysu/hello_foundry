// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {BaseScript} from "./BaseScript.sol";
import {console2} from "forge-std/console2.sol";
import {LeveragedDEX} from "../src/dex/LeveragedDEX.sol";

/// @notice 部署 LeveragedDEX
///
/// 用法：
///   forge script script/DeployLeveragedDEX.s.sol --rpc-url <RPC> --broadcast
///
/// 默认初始化：
///   vBase  = 1000 ETH    （虚拟 ETH 储备）
///   vQuote = 2,000,000   （虚拟 USD 储备，对应 $2000/ETH）
contract DeployLeveragedDEXScript is BaseScript {
    LeveragedDEX public dex;

    function run() public {
        broadcast();

        uint256 initialVBase = 1000 ether; // 1000 ETH
        uint256 initialVQuote = 2_000_000 * 1e18; // $2,000,000 (18 decimals) → $2000/ETH

        dex = new LeveragedDEX(initialVBase, initialVQuote);
        saveDeployment("LeveragedDEX", address(dex));

        vm.stopBroadcast();

        console2.log("============================================");
        console2.log("LeveragedDEX Deployment Summary");
        console2.log("============================================");
        console2.log("Contract:  ", address(dex));
        console2.log("vBase:     ", dex.vBase());
        console2.log("vQuote:    ", dex.vQuote());
        console2.log("Price:     ", dex.getMarkPrice());
    }
}
