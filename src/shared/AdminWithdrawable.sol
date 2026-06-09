// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "../uniswap-v2/periphery/interfaces/IERC20.sol";
import {UniswapV2Helper} from "./UniswapV2Helper.sol";

/// @notice 可继承的基类，提供：
///         - withdrawETH: 提取合约中误转入的 ETH
///         - withdrawToken: 提取合约中误转入的 ERC20
///         - receive(): 适配接收 ETH
///         - 所有子类共享的 TokenWithdrawn / ETHWithdrawn 事件
abstract contract AdminWithdrawable is Ownable {
    event ETHWithdrawn(address indexed to, uint256 amount);
    event TokenWithdrawn(address indexed token, address indexed to, uint256 amount);

    constructor() Ownable(msg.sender) {}

    /// @notice 提取合约中的 ETH 余额（误转入的 ETH 或 WETH 解包后）
    function withdrawETH() external onlyOwner {
        uint256 balance = address(this).balance;
        require(balance > 0, "NO_ETH");
        (bool ok,) = owner().call{value: balance}("");
        require(ok, "ETH_TRANSFER_FAILED");
        emit ETHWithdrawn(owner(), balance);
    }

    /// @notice 提取合约中被误转入的其他 ERC20 代币
    /// @param token ERC20 代币地址
    function withdrawToken(address token) external onlyOwner {
        uint256 balance = IERC20(token).balanceOf(address(this));
        require(balance > 0, "NO_TOKENS");
        UniswapV2Helper.safeTransfer(token, owner(), balance);
        emit TokenWithdrawn(token, owner(), balance);
    }

    /// @notice 接收 ETH（误转入时不会丢失）
    receive() external payable {}
}
