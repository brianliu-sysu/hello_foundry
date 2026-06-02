// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script} from "forge-std/Script.sol";

/// @notice 所有部署脚本的基类。
///         从 .env 文件中读取 MNEMONIC 环境变量，派生出部署账户。
///         子合约通过 `broadcast()` 方法使用该账户发起交易。
abstract contract BaseScript is Script {
    /// @notice 部署账户的私钥（由助记词派生）
    uint256 internal deployerPrivateKey;

    /// @notice 部署账户地址
    address internal deployer;

    /// @notice 从 .env 读取 MNEMONIC，派生第 0 个账户（m/44'/60'/0'/0/0）
    function setUp() public virtual {
        string memory mnemonic = vm.envString("MNEMONIC");
        deployerPrivateKey = vm.deriveKey(mnemonic, 0);
        deployer = vm.addr(deployerPrivateKey);
    }

    /// @notice 使用派生出的部署账户开始广播交易，替代 vm.startBroadcast()
    function broadcast() internal {
        vm.startBroadcast(deployerPrivateKey);
    }
}
