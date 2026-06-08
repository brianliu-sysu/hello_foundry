// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {BaseScript} from "./BaseScript.sol";
import {console2} from "forge-std/console2.sol";
import {UniswapV2Factory} from "../src/uniswap-v2/core/UniswapV2Factory.sol";
import {WETH9} from "../src/uniswap-v2/periphery/WETH9.sol";
import {UniswapV2Router02} from "../src/uniswap-v2/periphery/UniswapV2Router02.sol";

/// @notice 部署 Uniswap V2 核心基础设施：Factory → WETH9 → Router02
///
/// 环境变量（可选）：
///   FEE_TO_SETTER  — feeTo setter 地址，默认使用部署者地址
///
/// 用法：
///   forge script script/DeployUniswapV2.s.sol --rpc-url <RPC> --broadcast
contract DeployUniswapV2Script is BaseScript {
    UniswapV2Factory public factory;
    WETH9 public weth;
    UniswapV2Router02 public router;

    function run() public {
        address feeToSetter = vm.envOr("FEE_TO_SETTER", deployer);

        broadcast();

        // 1. Factory
        factory = new UniswapV2Factory(feeToSetter);
        saveDeployment("UniswapV2Factory", address(factory));

        // 2. WETH9
        weth = new WETH9();
        saveDeployment("WETH9", address(weth));

        // 3. Router02
        router = new UniswapV2Router02(address(factory), address(weth));
        saveDeployment("UniswapV2Router02", address(router));

        vm.stopBroadcast();

        console2.log("============================================");
        console2.log("Uniswap V2 Deployment Summary");
        console2.log("============================================");
        console2.log("Factory:  ", address(factory));
        console2.log("WETH9:    ", address(weth));
        console2.log("Router02: ", address(router));
        console2.log("Pair Code Hash:");
        console2.logBytes32(factory.pairCodeHash());
    }
}
