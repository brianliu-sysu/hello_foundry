// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {BaseScript} from "./BaseScript.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {CounterV1Upgradeable} from "../src/CounterV1Upgradeable.sol";
import {CounterV2Upgradeable} from "../src/CounterV2Upgradeable.sol";

/// @notice 部署+升级 UUPS Counter 的脚本
///         首次部署: forge script script/CounterUUPS.s.sol --sig "run()"
///         升级到V2: forge script script/CounterUUPS.s.sol --sig "upgrade()"
contract CounterUUPSScript is BaseScript {
    ERC1967Proxy public proxy;
    CounterV1Upgradeable public counterV1;
    CounterV2Upgradeable public counterV2;

    function run() public {
        broadcast();

        // 1. 部署 V1 实现
        counterV1 = new CounterV1Upgradeable();
        // 2. 部署代理，指向 V1，calldata = initialize()
        proxy = new ERC1967Proxy(
            address(counterV1),
            abi.encodeCall(CounterV1Upgradeable.initialize, ())
        );
        saveDeployment("CounterUUPS_Proxy", address(proxy));
        saveDeployment("CounterUUPS_V1", address(counterV1));

        vm.stopBroadcast();
    }

    function upgrade() public {
        broadcast();

        // 3. 部署 V2 实现
        counterV2 = new CounterV2Upgradeable();
        // 4. 通过 proxy 调用 upgradeToAndCall（UUPS 自带的升级方法）
        CounterV1Upgradeable(address(proxy)).upgradeToAndCall(
            address(counterV2),
            "" // 不需要再次 initialize
        );
        saveDeployment("CounterUUPS_V2", address(counterV2));

        vm.stopBroadcast();
    }
}
