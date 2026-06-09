// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {BaseScript} from "./BaseScript.sol";
import {console2} from "forge-std/console2.sol";
import {LendingMarket} from "../src/lending/LendingMarket.sol";

/// @notice 部署 LendingMarket 合约并初始化 WETH 作为首个准备金资产
///
/// 环境变量（可选）：
///   WETH_ADDRESS — WETH 地址，默认从 deploy/<chainId>/WETH9.json 读取
///
/// 用法：
///   forge script script/DeployLendingMarket.s.sol --rpc-url <RPC> --broadcast
contract DeployLendingMarketScript is BaseScript {
    LendingMarket public market;

    function run() public {
        string memory chainId = vm.toString(block.chainid);

        // 读取 WETH 地址
        string memory wethPath = string.concat("deploy/", chainId, "/WETH9.json");
        address wethAddr;
        string memory envWeth = vm.envOr("WETH_ADDRESS", string(""));
        if (bytes(envWeth).length > 0) {
            wethAddr = vm.parseAddress(envWeth);
        } else {
            string memory wethJson = vm.readFile(wethPath);
            wethAddr = vm.parseJsonAddress(wethJson, ".address");
        }
        require(wethAddr != address(0), "WETH address not found");

        broadcast();

        // 1. Deploy LendingMarket
        market = new LendingMarket();
        saveDeployment("LendingMarket", address(market));

        // 2. 初始化 WETH 准备金
        market.initReserve(
            wethAddr, // asset
            7500, // collateralFactor: 75%
            8500, // liquidationThreshold: 85%
            10500, // liquidationBonus: 5%
            9, // flashLoanPremium: 0.09%
            3000e8, // price: $3000 USD (1e8)
            0.8e27, // optimalUtilizationRate: 80%
            0.02e27, // baseBorrowRate: 2%
            0.06e27, // slope1: 6%
            3.0e27 // slope2: 300% (jump rate)
        );

        vm.stopBroadcast();

        console2.log("============================================");
        console2.log("LendingMarket Deployment Summary");
        console2.log("============================================");
        console2.log("Market: ", address(market));
        console2.log("WETH:   ", wethAddr);
        console2.log("Owner:  ", deployer);
    }
}
