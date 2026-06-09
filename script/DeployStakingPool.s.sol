// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {BaseScript} from "./BaseScript.sol";
import {console2} from "forge-std/console2.sol";
import {KKToken} from "../src/KKToken.sol";
import {StakingPool} from "../src/StakingPool.sol";

/// @notice 部署 KKToken + StakingPool
///
/// 需要已部署的合约：
///   - WETH9            （读取 deploy/<chainId>/WETH9.json）
///   - LendingMarket    （读取 deploy/<chainId>/LendingMarket.json）
///
/// 环境变量（可选）：
///   WETH_ADDRESS         WETH 地址，默认从 deploy 文件读取
///   LENDINGMARKET_ADDRESS LendingMarket 地址，默认从 deploy 文件读取
///
/// 用法：
///   forge script script/DeployStakingPool.s.sol --rpc-url <RPC> --broadcast
contract DeployStakingPoolScript is BaseScript {
    KKToken public kk;
    StakingPool public pool;

    function run() public {
        string memory chainId = vm.toString(block.chainid);

        // 读取 WETH 地址
        string memory wethPath = string.concat("deploy/", chainId, "/WETH9.json");
        address wethAddr;
        string memory envWeth = vm.envOr("WETH_ADDRESS", string(""));
        if (bytes(envWeth).length > 0) {
            wethAddr = vm.parseAddress(envWeth);
        } else {
            wethAddr = vm.parseJsonAddress(vm.readFile(wethPath), ".address");
        }
        require(wethAddr != address(0), "WETH address not found");

        // 读取 LendingMarket 地址
        string memory marketPath = string.concat("deploy/", chainId, "/LendingMarket.json");
        address marketAddr;
        string memory envMarket = vm.envOr("LENDINGMARKET_ADDRESS", string(""));
        if (bytes(envMarket).length > 0) {
            marketAddr = vm.parseAddress(envMarket);
        } else {
            marketAddr = vm.parseJsonAddress(vm.readFile(marketPath), ".address");
        }
        require(marketAddr != address(0), "LendingMarket address not found");

        broadcast();

        // 1. Deploy KKToken
        kk = new KKToken();
        saveDeployment("KKToken", address(kk));

        // 2. Deploy StakingPool（以 deployer 为 Owner）
        pool = new StakingPool(wethAddr, address(kk), marketAddr);
        saveDeployment("StakingPool", address(pool));

        // 3. 将 KKToken 的 Owner 转移给 StakingPool
        kk.transferOwnership(address(pool));

        vm.stopBroadcast();

        console2.log("============================================");
        console2.log("StakingPool Deployment Summary");
        console2.log("============================================");
        console2.log("KKToken:     ", address(kk));
        console2.log("StakingPool: ", address(pool));
        console2.log("WETH:        ", wethAddr);
        console2.log("LendingMkt:  ", marketAddr);
        console2.log("Deployer:    ", deployer);
    }
}
