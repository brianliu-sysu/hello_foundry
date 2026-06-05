// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {BaseScript} from "./BaseScript.sol";
import {MemeToken} from "../src/MemeToken.sol";
import {MemeFactory} from "../src/MemeFactory.sol";

/// @notice Deploy MemeToken implementation + MemeFactory.
/// @dev    需先部署模板，再传地址给工厂构造函数。
contract MemeFactoryScript is BaseScript {
    MemeToken public memeTokenImpl;
    MemeFactory public memeFactory;

    function run() public {
        broadcast();

        // 1. 部署模板合约（不会被直接使用，仅供 factory clone）
        memeTokenImpl = new MemeToken();
        saveDeployment("MemeTokenImpl", address(memeTokenImpl));

        // 2. 部署工厂
        memeFactory = new MemeFactory(memeTokenImpl);
        saveDeployment("MemeFactory", address(memeFactory));

        vm.stopBroadcast();
    }
}
