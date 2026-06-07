// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

/// @notice Counter — UUPS 可升级合约 V2
///         在 V1 基础上新增 decrement 和 add 功能。
contract CounterV2Upgradeable is Initializable, OwnableUpgradeable, UUPSUpgradeable {
    uint256 public number;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice 初始化（仅在首次部署时调用一次）
    function initialize() public initializer {
        __Ownable_init(msg.sender);
    }

    // ═══════════════════════════════════════════════════════════════
    // V1 原有方法
    // ═══════════════════════════════════════════════════════════════

    function setNumber(uint256 newNumber) external {
        number = newNumber;
    }

    function increment() external {
        number++;
    }

    // ═══════════════════════════════════════════════════════════════
    // V2 新增方法
    // ═══════════════════════════════════════════════════════════════

    /// @notice V2 新增：减值
    function decrement() external {
        require(number > 0, "Counter: underflow");
        number--;
    }

    /// @notice V2 新增：加任意值
    function add(uint256 i) external {
        number = number + i;
    }

    // ═══════════════════════════════════════════════════════════════
    // UUPS upgrade guard
    // ═══════════════════════════════════════════════════════════════

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
}
