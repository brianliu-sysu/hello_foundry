// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.26;

import {IERC1363Receiver} from "@openzeppelin/contracts/interfaces/IERC1363Receiver.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract TokenBank is IERC1363Receiver {
    // 记录每个用户在每种代币上的存款金额: user => token => amount
    mapping(address => mapping(address => uint256)) public deposits;

    event Deposited(address indexed token, address indexed from, uint256 amount);
    event Withdrawn(address indexed token, address indexed to, uint256 amount);

    /// @notice ERC1363 回调：当用户通过 transferAndCall 转入代币时被调用
    /// @param from 代币转出地址（即存款用户）
    /// @param value 转入的代币数量
    /// @return IERC1363Receiver.onTransferReceived 的 selector，表示接受该转账
    function onTransferReceived(
        address /* operator */,
        address from,
        uint256 value,
        bytes calldata /* data */
    ) external override returns (bytes4) {
        // 记录用户存入的 token 数量，msg.sender 即代币合约地址
        deposits[from][msg.sender] += value;

        emit Deposited(msg.sender, from, value);

        // 必须返回此 magic value 以确认接收
        return IERC1363Receiver.onTransferReceived.selector;
    }

    /// @notice 提取已存入的指定代币
    /// @param token 代币合约地址
    /// @param amount 提取数量
    function withdraw(address token, uint256 amount) external {
        require(deposits[msg.sender][token] >= amount, "TokenBank: insufficient deposit");
        deposits[msg.sender][token] -= amount;
        require(IERC20(token).transfer(msg.sender, amount), "TokenBank: transfer failed");
        emit Withdrawn(token, msg.sender, amount);
    }
}
