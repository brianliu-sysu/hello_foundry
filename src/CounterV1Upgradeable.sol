// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

/// @notice Counter — UUPS 可升级合约 V1
///         支持 setNumber / increment，只有 owner 可以升级实现。
contract CounterV1Upgradeable is Initializable, OwnableUpgradeable, UUPSUpgradeable {
    uint256 public number;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice 初始化（替代构造函数，由 proxy 调用）
    function initialize() public initializer {
        __Ownable_init(msg.sender);
    }

    // ═══════════════════════════════════════════════════════════════
    // V1 业务逻辑
    // ═══════════════════════════════════════════════════════════════

    function setNumber(uint256 newNumber) external {
        number = newNumber;
    }

    function increment() external {
        number++;
    }

    // ═══════════════════════════════════════════════════════════════
    // UUPS 所需：只有 owner 可以升级
    // ═══════════════════════════════════════════════════════════════

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
}
