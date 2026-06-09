// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @title  KKToken — StakingPool 的奖励代币
/// @notice 每以太坊区块产生 10 KK，由 StakingPool 调用 mintPoolReward 铸造。
///         仅 Owner（StakingPool）可铸造，Owner 可转移。
contract KKToken is ERC20, ERC20Permit, Ownable {
    /// @notice 每区块产生的 KK 数量（18 decimals）
    uint256 public constant REWARD_PER_BLOCK = 10 * 1e18;

    event Minted(address indexed pool, uint256 amount);
    event PoolTransferred(address indexed oldPool, address indexed newPool);

    constructor() ERC20("KK Token", "KK") ERC20Permit("KK Token") Ownable(msg.sender) {}

    /// @notice 由 StakingPool 调用，按区块数铸造奖励
    /// @param blocks Elapsed blocks since last mint
    /// @return minted Amount actually minted
    function mintPoolReward(uint256 blocks) external onlyOwner returns (uint256 minted) {
        minted = blocks * REWARD_PER_BLOCK;
        _mint(msg.sender, minted);
        emit Minted(msg.sender, minted);
    }
}
