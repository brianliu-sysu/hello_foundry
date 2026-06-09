// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.26;

import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {MemeToken} from "./MemeToken.sol";

/// @notice MemeFactory — 用最小代理（EIP-1167）一键部署 MemeToken。
/// @dev    先部署 MemeToken 模板，工厂持有其地址。
///         每次 createMeme() 只需 ~55K gas（clone + initialize）。
contract MemeFactory {
    using Clones for address;

    /// @notice MemeToken 模板地址（不可变）
    MemeToken public immutable memeTokenImpl;

    /// @notice 已创建的所有 meme token 地址列表
    address[] public memeTokens;

    // ── Events ────────────────────────────────────────────────

    event MemeCreated(
        string name,
        string symbol,
        uint256 totalSupply,
        address indexed creator,
        address indexed token
    );

    // ── Constructor ───────────────────────────────────────────

    /// @param impl_ MemeToken 模板合约地址
    constructor(MemeToken impl_) {
        require(address(impl_) != address(0), "MemeFactory: impl is zero");
        memeTokenImpl = impl_;
    }

    // ── Public ─────────────────────────────────────────────────

    /// @notice 创建一个新的 MemeToken 最小代理并初始化
    /// @param name_       代币名称
    /// @param symbol_     代币符号
    /// @param totalSupply_ 初始供应量（全部 mint 给 msg.sender）
    /// @return clone       新 meme token 地址
    function createMeme(
        string calldata name_,
        string calldata symbol_,
        uint256 totalSupply_
    ) external returns (address clone) {
        // 1. 部署最小代理（EIP-1167 clone）
        clone = address(memeTokenImpl).clone();

        // 2. 初始化（设置 name/symbol，mint，转移 owner）
        MemeToken(clone).initialize(name_, symbol_, totalSupply_, msg.sender);

        // 3. 记录
        memeTokens.push(clone);

        emit MemeCreated(name_, symbol_, totalSupply_, msg.sender, clone);
    }

    // ── View ───────────────────────────────────────────────────

    /// @notice 已创建的 meme token 数量
    function memeCount() external view returns (uint256) {
        return memeTokens.length;
    }

    /// @notice 获取全部已创建的 meme token 地址
    function getMemeTokens() external view returns (address[] memory) {
        return memeTokens;
    }

    /// @notice 分页获取 meme token 列表
    function getMemeTokensPaginated(uint256 offset, uint256 limit)
        external
        view
        returns (address[] memory page, uint256 total)
    {
        total = memeTokens.length;
        if (offset >= total) return (new address[](0), total);
        uint256 end = offset + limit;
        if (end > total) end = total;
        uint256 size = end - offset;
        page = new address[](size);
        for (uint256 i = 0; i < size; i++) {
            page[i] = memeTokens[offset + i];
        }
    }

}
