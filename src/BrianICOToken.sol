// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC1363} from "@openzeppelin/contracts/token/ERC20/extensions/ERC1363.sol";

contract BrianICOToken is ERC1363 {
    constructor(uint256 initialSupply) ERC20("BrianICOToken", "BIT") {
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
}