// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {BaseScript} from "./BaseScript.sol";
import {console2} from "forge-std/console2.sol";
import {AaveFlashArbitrage} from "../src/arbitrage/AaveFlashArbitrage.sol";

/// @notice 部署 AaveFlashArbitrage 合约
///
/// 环境变量（可选）：
///   AAVE_POOL_ADDRESSES_PROVIDER  — Aave v3 PoolAddressesProvider 地址
///   UNISWAP_V2_FACTORY           — Uniswap V2 Factory 地址，默认从 deploy/<chainId>/UniswapV2Factory.json 读取
///
/// Aave v3 PoolAddressesProvider 在各链上的地址：
///   Sepolia:  0x012bAC54348C0E635dCAc9D5FB99f06F24136C9A
///   Mainnet:  0x2f39d218133AFaB8F2B819B1066c7E434Ad94E9e
///
/// 用法：
///   forge script script/DeployAaveFlashArbitrage.s.sol --rpc-url <RPC> --broadcast
contract DeployAaveFlashArbitrageScript is BaseScript {
    AaveFlashArbitrage public arbitrage;

    function run() public {
        string memory chainId = vm.toString(block.chainid);

        // 读取 Uniswap V2 Factory 地址
        string memory factoryPath = string.concat("deploy/", chainId, "/UniswapV2Factory.json");
        string memory envFactoryStr = vm.envOr("UNISWAP_V2_FACTORY", string(""));
        address factoryAddr;
        if (bytes(envFactoryStr).length > 0) {
            factoryAddr = vm.parseAddress(envFactoryStr);
        } else {
            string memory factoryJson = vm.readFile(factoryPath);
            factoryAddr = vm.parseJsonAddress(factoryJson, ".address");
        }
        require(factoryAddr != address(0), "Factory address not found");

        // 读取 Aave v3 PoolAddressesProvider 地址
        address providerAddr = vm.envAddress("AAVE_POOL_ADDRESSES_PROVIDER");
        require(providerAddr != address(0), "AAVE_POOL_ADDRESSES_PROVIDER not set");

        broadcast();

        arbitrage = new AaveFlashArbitrage(providerAddr, factoryAddr);
        saveDeployment("AaveFlashArbitrage", address(arbitrage));

        vm.stopBroadcast();

        console2.log("============================================");
        console2.log("AaveFlashArbitrage Deployment Summary");
        console2.log("============================================");
        console2.log("Contract:   ", address(arbitrage));
        console2.log("Pool:       ", address(arbitrage.POOL()));
        console2.log("Factory:    ", factoryAddr);
        console2.log("Owner:      ", deployer);
    }
}
