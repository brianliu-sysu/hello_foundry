pragma solidity ^0.8.26;
// SPDX-License-Identifier: GPL-3.0
import "./Faucet.sol";

contract Token is Faucet {
    Faucet public faucet;

    constructor(address payable _f) payable {
        faucet = Faucet(_f);
        faucet.withdraw(0.01 ether, payable(address(this)));
    }

    function changeFaucetOwner(address _owner) public onlyOwner {
        faucet.changeOwner(_owner);
    }
}
