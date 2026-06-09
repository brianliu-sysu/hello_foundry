pragma solidity ^0.8.26;
// SPDX-License-Identifier: GPL-3.0

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

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
    event Withdrawal(address indexed to, uint256 amount);
    event Deposit(address indexed from, uint256 amount);
    event TokenWithdrawal(address indexed to, uint256 amount);
    event TokenDeposit(address indexed from, uint256 amount);

    /// @notice 水龙头支持的 ERC20 代币地址
    IERC20 public token;

    /// @notice 每个地址的上次 ETH 提款时间（Unix timestamp）
    mapping(address => uint256) public lastWithdrawTime;

    /// @notice 每个地址的上次代币提款时间（Unix timestamp）
    mapping(address => uint256) public lastTokenWithdrawTime;

    /// @notice 单次代币提款上限：10 枚代币（假设 18 位小数）
    uint256 public constant MAX_TOKEN_WITHDRAW = 10 ether;

    constructor() payable {
        owner = msg.sender;
    }

    // ═══════════════════════════════════════════════════════════════
    // ETH 水龙头
    // ═══════════════════════════════════════════════════════════════

    // 向任何提出要求的人提供 ether
    function withdraw(uint256 _withdrawAmount, address payable _to) public whenNotPaused {
        // 限制每个地址一天只能提款一次（首次提款不受限）
        require(
            lastWithdrawTime[msg.sender] == 0 || block.timestamp >= lastWithdrawTime[msg.sender] + 1 days,
            "Withdraw limited to once per day"
        );

        // 限制提款金额
        require(_withdrawAmount <= 0.01 ether);

        // 记录本次提款时间
        lastWithdrawTime[msg.sender] = block.timestamp;

        // 将金额发送到请求它的地址
        (bool success,) = _to.call{value: _withdrawAmount}("");
        require(success, "Transfer failed");
        emit Withdrawal(_to, _withdrawAmount);
    }

    // ═══════════════════════════════════════════════════════════════
    // Token 水龙头
    // ═══════════════════════════════════════════════════════════════

    /// @notice Owner 设置支持的代币合约地址
    /// @param _token ERC20 代币地址
    function setToken(address _token) external onlyOwner {
        token = IERC20(_token);
    }

    /// @notice 提取代币（每人每天最多 10 枚）
    /// @param amount 提取的代币数量（以最小单位计，通常 18 位小数）
    function withdrawToken(uint256 amount) public whenNotPaused {
        require(address(token) != address(0), "Token not set");

        // 限制每个地址一天只能提款一次（首次提款不受限）
        require(
            lastTokenWithdrawTime[msg.sender] == 0 || block.timestamp >= lastTokenWithdrawTime[msg.sender] + 1 days,
            "Token withdraw limited to once per day"
        );

        // 限制提款金额
        require(amount <= MAX_TOKEN_WITHDRAW, "Token withdraw amount exceeds limit");

        // 记录本次提款时间
        lastTokenWithdrawTime[msg.sender] = block.timestamp;

        // 转账代币给调用者
        require(token.transfer(msg.sender, amount), "Token transfer failed");
        emit TokenWithdrawal(msg.sender, amount);
    }

    /// @notice Owner 一键提回合约中全部代币余额
    function adminWithdrawToken() external onlyOwner {
        require(address(token) != address(0), "Token not set");
        uint256 balance = token.balanceOf(address(this));
        require(balance > 0, "No tokens to withdraw");
        require(token.transfer(owner, balance), "Admin token withdraw failed");
    }

    // ═══════════════════════════════════════════════════════════════
    // 管理 & 接收
    // ═══════════════════════════════════════════════════════════════

    function unpause() public view override onlyOwner {
        revert("Faucet is not paused");
    }

    // 接收 Ether 的函数。msg.data 必须为空
    receive() external payable {
        emit Deposit(msg.sender, msg.value);
    }

    // 当 msg.data 不为空时调用 Fallback 函数
    fallback() external payable {}
}
