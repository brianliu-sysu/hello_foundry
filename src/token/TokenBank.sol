// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.26;

import {IERC1363Receiver} from "@openzeppelin/contracts/interfaces/IERC1363Receiver.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import {ISignatureTransfer} from "../utils/ISignatureTransfer.sol";

contract TokenBank is IERC1363Receiver {
    address private constant PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;
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

    /// @notice 直接存入代币（需先 approve 本合约）
    /// @dev 与 transferAndCall / ERC1363 方式互为补充
    /// @param token 代币合约地址
    /// @param amount 存入数量
    function deposit(address token, uint256 amount) external {
        require(amount > 0, "TokenBank: amount must be > 0");
        require(
            IERC20(token).transferFrom(msg.sender, address(this), amount),
            "TokenBank: transferFrom failed"
        );
        deposits[msg.sender][token] += amount;
        emit Deposited(token, msg.sender, amount);
    }

    /// @notice 离线签名授权后存入代币（EIP-2612 permit + deposit 一步完成）
    /// @dev 用户链下签名 permit，任意中继者（relayer）即可代付 gas 上链
    /// @param owner   代币持有者（签名方）
    /// @param token   代币合约地址（需支持 IERC20Permit）
    /// @param amount  存入数量
    /// @param deadline 签名截止时间（unix timestamp）
    /// @param v        permit 签名的 v
    /// @param r        permit 签名的 r
    /// @param s        permit 签名的 s
    function permitDeposit(
        address owner,
        address token,
        uint256 amount,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {
        require(amount > 0, "TokenBank: amount must be > 0");

        // 1. 执行 permit，使本合约获得 owner → address(this) 的 allowance
        IERC20Permit(token).permit(owner, address(this), amount, deadline, v, r, s);

        // 2. 从 owner 转账到本合约
        require(
            IERC20(token).transferFrom(owner, address(this), amount),
            "TokenBank: transferFrom failed"
        );

        // 3. 记录存款
        deposits[owner][token] += amount;
        emit Deposited(token, owner, amount);
    }

    /// @notice Deposit tokens via Permit2 SignatureTransfer (gasless for users who have pre-approved Permit2)
    /// @dev  User signs a PermitTransferFrom message off-chain. Anyone (relayer) submits it.
    ///       Requires a one-time ERC20 approve of the Permit2 contract (type(uint256).max recommended).
    /// @param owner     Token holder who signed the permit
    /// @param token     ERC20 token address (must match the signed TokenPermissions.token)
    /// @param amount    Amount to deposit (must be <= signed TokenPermissions.amount)
    /// @param nonce     Permit2 nonce (unique value; unused bit in Permit2's bitmap)
    /// @param deadline  Signature expiration (unix timestamp)
    /// @param signature EIP-712 signature bytes
    function depositPermit2(
        address owner,
        address token,
        uint256 amount,
        uint256 nonce,
        uint256 deadline,
        bytes calldata signature
    ) external {
        require(amount > 0, "TokenBank: amount must be > 0");

        ISignatureTransfer.PermitTransferFrom memory permit = ISignatureTransfer.PermitTransferFrom({
            permitted: ISignatureTransfer.TokenPermissions({token: token, amount: amount}),
            nonce: nonce,
            deadline: deadline
        });

        ISignatureTransfer.SignatureTransferDetails memory transferDetails = ISignatureTransfer
            .SignatureTransferDetails({to: address(this), requestedAmount: amount});

        ISignatureTransfer(PERMIT2).permitTransferFrom(permit, transferDetails, owner, signature);

        deposits[owner][token] += amount;
        emit Deposited(token, owner, amount);
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
