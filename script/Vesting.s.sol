// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {BaseScript} from "./BaseScript.sol";
import {console2} from "forge-std/console2.sol";
import {BrianICOToken} from "../src/token/BrianICOToken.sol";
import {Vesting} from "../src/token/Vesting.sol";

/// @notice 部署 Vesting 合约 + 配套 BrianICOToken，并向合约转入 100 万代币
///
/// 环境变量（均可选，未设置时使用默认值）：
///   TOKEN_ADDRESS      — 已部署的 ERC20 代币地址。留空则自动部署新的 BrianICOToken
///   BENEFICIARY        — 受益人地址。留空则使用部署者地址
///   TOTAL_VESTING      — 释放总量（代币最小单位，默认 100 万 * 1e18）
///   CLIFF_DURATION     — 锁定期秒数（默认 12 * 30 days ≈ 31104000）
///   UNLOCK_PERIOD      — 每期间隔秒数（默认 30 days = 2592000）
///
/// 用法：
///   forge script script/Vesting.s.sol --rpc-url <RPC> --broadcast
///   BENEFICIARY=0x... forge script script/Vesting.s.sol --rpc-url <RPC> --broadcast
contract VestingScript is BaseScript {
    BrianICOToken public token;
    Vesting public vesting;

    uint256 constant DEFAULT_TOTAL_VESTING = 1_000_000 * 1e18;
    uint256 constant DEFAULT_CLIFF_DURATION = 12 * 30 days;
    uint256 constant DEFAULT_UNLOCK_PERIOD = 30 days;

    function run() public {
        // ---------- 读取参数 ----------
        address tokenAddr = vm.envOr("TOKEN_ADDRESS", address(0));
        address beneficiary = vm.envOr("BENEFICIARY", deployer);

        uint256 totalVesting = _envUintOr("TOTAL_VESTING", DEFAULT_TOTAL_VESTING);
        uint256 cliffDuration = _envUintOr("CLIFF_DURATION", DEFAULT_CLIFF_DURATION);
        uint256 unlockPeriod = _envUintOr("UNLOCK_PERIOD", DEFAULT_UNLOCK_PERIOD);

        // ---------- 开始广播 ----------
        broadcast();

        // 部署或引用代币
        if (tokenAddr == address(0)) {
            // 多铸造一些给部署者，方便后续测试和转移
            token = new BrianICOToken(totalVesting * 2);
            tokenAddr = address(token);
            saveDeployment("BrianICOToken", tokenAddr);
        } else {
            token = BrianICOToken(payable(tokenAddr));
        }

        // 部署 Vesting 合约
        vesting = new Vesting(tokenAddr, beneficiary, totalVesting, cliffDuration, unlockPeriod);
        saveDeployment("Vesting", address(vesting));

        // 向 Vesting 合约转入 100 万代币（模拟"创建合约后打入 100 万 token"）
        token.transfer(address(vesting), totalVesting);

        vm.stopBroadcast();

        // ---------- 日志 ----------
        console2.log("============================================");
        console2.log("Vesting Deployment Summary");
        console2.log("============================================");
        console2.log("Token:            ", tokenAddr);
        console2.log("Vesting Contract: ", address(vesting));
        console2.log("Beneficiary:      ", beneficiary);
        console2.log("Total Vesting:    ", vm.toString(totalVesting));
        console2.log("Cliff Duration:   ", vm.toString(cliffDuration), "seconds");
        console2.log("Unlock Period:    ", vm.toString(unlockPeriod), "seconds");
        console2.log("Max Releases:     ", vesting.MAX_RELEASES());
        console2.log("Vesting Balance:  ", vm.toString(token.balanceOf(address(vesting))));
        console2.log("Owner:            ", vesting.owner());
    }

    /// @notice 读取 uint256 环境变量，未设置时返回默认值
    function _envUintOr(string memory key, uint256 defaultVal) internal view returns (uint256) {
        try vm.envUint(key) returns (uint256 v) {
            return v;
        } catch {
            return defaultVal;
        }
    }
}
