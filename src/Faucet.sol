pragma solidity ^0.8.26;
// SPDX-License-Identifier: GPL-3.0

contract Owner {
    address public owner;

    constructor() {
        owner = msg.sender;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner can call this function");
        _;
    }

    function changeOwner(address newOwner) public virtual onlyOwner {
        owner = newOwner;
    }
}

contract Pausable is Owner {
    bool public paused;

    constructor() {
        paused = false;
    }

    modifier whenNotPaused() {
        require(!paused, "Contract is paused");
        _;
    }
    
    function pause() public virtual onlyOwner {
        paused = true;
    }

    function unpause() public virtual onlyOwner {
        paused = false;
    }
    
}

// 我们的第一个合约是一个水龙头！
contract Faucet is Pausable {
    event Withdrawal(address indexed to, uint amount);
    event Deposit(address indexed from, uint amount);

    constructor() payable {
        owner = msg.sender;
    }

    // 向任何提出要求的人提供 ether
    function withdraw(uint256 _withdrawAmount, address payable _to) public whenNotPaused {

        // 限制提款金额
        require(_withdrawAmount <= 1000000000000);

        // 将金额发送到请求它的地址
        (bool success, ) = _to.call{value: _withdrawAmount}("");
        require(success, "Transfer failed");
        emit Withdrawal(_to, _withdrawAmount);
    }

    function unpause() public override view onlyOwner {
        revert("Faucet is not paused");
    }

    // 接收 Ether 的函数。msg.data 必须为空
    receive() external payable {
        emit Deposit(msg.sender, msg.value);
    }

    // 当 msg.data 不为空时调用 Fallback 函数
    fallback() external payable {}
}
