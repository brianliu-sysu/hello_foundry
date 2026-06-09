// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC1363} from "@openzeppelin/contracts/token/ERC20/extensions/ERC1363.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @notice BrianICOToken — ERC1363 + EIP-2612 permit 代币，owner 可提回误转入的余额
contract BrianICOToken is ERC1363, ERC20Permit, Ownable {
    constructor(uint256 initialSupply)
        ERC20("BrianICOToken", "BIT")
        ERC20Permit("BrianICOToken")
        Ownable(msg.sender)
    {
        _mint(msg.sender, initialSupply);
    }

    /// @notice 通过 ERC1363 的 transferAndCall 将代币存入指定银行合约，银行合约会通过 onTransferReceived 回调记录存款
    /// @param bank TokenBank 合约地址（需实现 IERC1363Receiver）
    /// @param amount 存入的代币数量
    /// @return success 是否成功
    function depositToBank(address bank, uint256 amount) public returns (bool) {
        // transferAndCall 会在转账后回调 bank 的 onTransferReceived，传入 msg.sender 和 data
        return transferAndCall(bank, amount, "");
    }

    /// @notice Owner 提取本合约中全部 ETH 余额（例如误转入的 ETH）
    function adminWithdrawETH() external onlyOwner {
        uint256 balance = address(this).balance;
        require(balance > 0, "No ETH to withdraw");
        (bool ok,) = owner().call{value: balance}("");
        require(ok, "ETH withdraw failed");
    }

    /// @notice Owner 提取本合约中被误转入的其他 ERC20 代币
    /// @param token 要提取的 ERC20 代币地址
    function adminWithdrawToken(address token) external onlyOwner {
        uint256 balance = IERC20(token).balanceOf(address(this));
        require(balance > 0, "No tokens to withdraw");
        require(IERC20(token).transfer(owner(), balance), "Token withdraw failed");
    }

    /// @notice 接收 ETH（误转入时不会丢失）
    receive() external payable {}
}