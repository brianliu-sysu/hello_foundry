// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {BaseScript} from "./BaseScript.sol";
import {console2} from "forge-std/console2.sol";
import {FlashArbitrage} from "../src/FlashArbitrage.sol";

/// @notice 部署 FlashArbitrage 合约
///
/// 环境变量（可选）：
///   FLASH_ARBITRAGE_FACTORY  — Uniswap V2 Factory 地址，默认从 deploy/<chainId>/UniswapV2Factory.json 读取
///   FLASH_ARBITRAGE_WETH     — WETH 地址，默认从 deploy/<chainId>/WETH9.json 读取
///
/// 用法：
///   forge script script/DeployFlashArbitrage.s.sol --rpc-url <RPC> --broadcast
contract DeployFlashArbitrageScript is BaseScript {
    FlashArbitrage public arbitrage;

    function run() public {
        // 尝试从已部署记录读取 Factory 和 WETH 地址
        string memory chainId = vm.toString(block.chainid);
        string memory factoryPath = string.concat("deploy/", chainId, "/UniswapV2Factory.json");
        string memory wethPath = string.concat("deploy/", chainId, "/WETH9.json");

        address factoryAddr;
        address wethAddr;

        // 优先从环境变量读取，否则从部署文件读取
        string memory envFactoryStr = vm.envOr("FLASH_ARBITRAGE_FACTORY", string(""));
        string memory envWethStr = vm.envOr("FLASH_ARBITRAGE_WETH", string(""));

        if (bytes(envFactoryStr).length > 0) {
            factoryAddr = vm.parseAddress(envFactoryStr);
        } else {
            string memory factoryJson = vm.readFile(factoryPath);
            factoryAddr = vm.parseJsonAddress(factoryJson, ".address");
        }

        if (bytes(envWethStr).length > 0) {
            wethAddr = vm.parseAddress(envWethStr);
        } else {
            string memory wethJson = vm.readFile(wethPath);
            wethAddr = vm.parseJsonAddress(wethJson, ".address");
        }

        require(factoryAddr != address(0), "Factory address not found");
        require(wethAddr != address(0), "WETH address not found");

        broadcast();

        arbitrage = new FlashArbitrage(factoryAddr, wethAddr);
        saveDeployment("FlashArbitrage", address(arbitrage));

        vm.stopBroadcast();

        console2.log("============================================");
        console2.log("FlashArbitrage Deployment Summary");
        console2.log("============================================");
        console2.log("FlashArbitrage: ", address(arbitrage));
        console2.log("Factory:        ", factoryAddr);
        console2.log("WETH:           ", wethAddr);
        console2.log("Owner:          ", deployer);
    }
}
