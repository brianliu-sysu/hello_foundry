// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.26;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract NaiveFaucet {
    IERC20 public immutable token;
    address public immutable owner;

    constructor(IERC20 _token, address _owner) {
        token = _token;
        owner = _owner;
        token.approve(address(this), type(uint256).max);
    }

    event Withdrawal(address indexed to, uint amount);

    function withdraw(uint256 amount) public {
        require(amount <= 100000e18, "Amount is too large");
        require(token.balanceOf(owner) >= amount, "Insufficient balance");
        token.transferFrom(owner, msg.sender, amount);
        emit Withdrawal(msg.sender, amount);
    }
}