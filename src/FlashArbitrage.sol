// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {IUniswapV2Callee} from "./uniswap-v2/core/interfaces/IUniswapV2Callee.sol";
import {IUniswapV2Pair} from "./uniswap-v2/core/interfaces/IUniswapV2Pair.sol";
import {IUniswapV2Factory} from "./uniswap-v2/core/interfaces/IUniswapV2Factory.sol";
import {IERC20} from "./uniswap-v2/periphery/interfaces/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title  FlashArbitrage
/// @notice 利用 Uniswap V2 Flash Swap 进行多跳路径套利
///         流程：
///           1. 从 borrowPair 借出 borrowAmount 个 borrowToken（Flash Swap）
///           2. 沿 tradePath 逐跳交易（borrowToken → ... → repayToken）
///           3. 按 0.3% 费率归还 repayToken 至 borrowPair
///           4. 剩余 repayToken 作为利润转给调用者
///
///         调用者（或 Bot）需链下计算套利路径和金额，本合约仅负责执行。
contract FlashArbitrage is IUniswapV2Callee, Ownable, ReentrancyGuard {
    // ======================================================================
    // EVENTS
    // ======================================================================

    event ArbitrageExecuted(
        address indexed caller,
        address indexed borrowPair,
        address borrowToken,
        uint256 borrowAmount,
        address repayToken,
        uint256 repayAmount,
        uint256 profit
    );

    event ETHWithdrawn(address indexed to, uint256 amount);
    event TokenWithdrawn(address indexed token, address indexed to, uint256 amount);

    // ======================================================================
    // IMMUTABLES
    // ======================================================================

    /// @notice Uniswap V2 Factory 地址
    address public immutable factory;

    /// @notice WETH 地址（用于套利利润结算）
    address public immutable WETH;

    // ======================================================================
    // STORAGE
    // ======================================================================

    /// @notice 套利执行中的互斥锁（防止重入 + 防止在回调外被调用）
    uint256 private unlocked = 1;

    /// @notice 当前套利的参数（仅在 uniswapV2Call 回调期间有效）
    struct ArbitrageContext {
        address caller; // 原始调用者，利润将转给此地址
        address[] tradePath; // 交易路径 [borrowToken, midToken..., repayToken]
        uint256 minProfit; // 最小利润要求（在 repayToken 中）
        uint256 deadline; // 截止时间
    }

    modifier lock() {
        require(unlocked == 1, "FlashArbitrage: LOCKED");
        unlocked = 0;
        _;
        unlocked = 1;
    }

    // ======================================================================
    // CONSTRUCTOR
    // ======================================================================

    /// @param _factory Uniswap V2 Factory 地址
    /// @param _weth    WETH 地址
    constructor(address _factory, address _weth) Ownable(msg.sender) {
        require(_factory != address(0), "ZERO_FACTORY");
        require(_weth != address(0), "ZERO_WETH");
        factory = _factory;
        WETH = _weth;
    }

    // ======================================================================
    // EXTERNAL: EXECUTE ARBITRAGE
    // ======================================================================

    /// @notice 发起闪电借贷套利
    /// @dev 仅 Owner（Bot）可调用。调用前需链下确认存在正利润。
    ///
    /// @param borrowPair   要借出代币的 Uniswap V2 Pair 地址
    /// @param borrowToken0 若为 true，借 token0；若为 false，借 token1
    /// @param borrowAmount 借出数量（wei）
    /// @param tradePath    交易路径数组：首元素 = 借出的代币，末元素 = 归还代币（该 pair 的另一种代币）
    ///                     例如 pair(WETH/TOKEN_A)，借 WETH 还 TOKEN_A：
    ///                     [WETH, TOKEN_B, TOKEN_A]
    /// @param minProfit    最小利润要求（在归还代币中），不足则回滚
    /// @param deadline     交易截止 Unix 时间戳
    function executeArbitrage(
        address borrowPair,
        bool borrowToken0,
        uint256 borrowAmount,
        address[] calldata tradePath,
        uint256 minProfit,
        uint256 deadline
    ) external onlyOwner nonReentrant {
        require(borrowPair != address(0), "ZERO_PAIR");
        require(borrowAmount > 0, "ZERO_AMOUNT");
        require(tradePath.length >= 2, "PATH_TOO_SHORT");
        require(deadline >= block.timestamp, "EXPIRED");

        address token0 = IUniswapV2Pair(borrowPair).token0();
        address token1 = IUniswapV2Pair(borrowPair).token1();

        // 验证 tradePath 首元素 = 借出代币，末元素 = 归还代币
        address borrowToken = borrowToken0 ? token0 : token1;
        address repayToken = borrowToken0 ? token1 : token0;
        require(tradePath[0] == borrowToken, "PATH_START_MISMATCH");
        require(tradePath[tradePath.length - 1] == repayToken, "PATH_END_MISMATCH");

        // 编码回调参数
        bytes memory data = abi.encode(msg.sender, tradePath, minProfit, deadline);

        // 发起 Flash Swap
        if (borrowToken0) {
            IUniswapV2Pair(borrowPair).swap(borrowAmount, 0, address(this), data);
        } else {
            IUniswapV2Pair(borrowPair).swap(0, borrowAmount, address(this), data);
        }
    }

    // ======================================================================
    // FLASH SWAP CALLBACK (IUniswapV2Callee)
    // ======================================================================

    /// @notice Uniswap V2 Pair 在转出代币后回调此函数
    /// @param /*sender*/ msg.sender of pair.swap() — the FlashArbitrage contract itself
    /// @param amount0 借出的 token0 数量（若为 0 则借的是 token1）
    /// @param amount1 借出的 token1 数量（若为 0 则借的是 token0）
    /// @param data    编码的套利参数
    /// @dev `sender` is `msg.sender` from pair.swap() — i.e., this contract itself.
    ///      The actual pair address is `msg.sender` in this callback.
    function uniswapV2Call(address /*sender*/, uint256 amount0, uint256 amount1, bytes calldata data)
        external
        override
        lock
    {
        // msg.sender is the Uniswap V2 Pair that invoked this callback
        _handleCallback(msg.sender, amount0, amount1, data);
    }

    // ======================================================================
    // INTERNAL: CALLBACK HANDLER (reduces stack depth in uniswapV2Call)
    // ======================================================================

    /// @dev Extracted from uniswapV2Call to avoid "Stack too deep" compiler error.
    /// @param pair The Uniswap V2 pair that called us back (msg.sender of uniswapV2Call)
    function _handleCallback(address pair, uint256 amount0, uint256 amount1, bytes calldata data) internal {
        (address caller, address[] memory tradePath, uint256 minProfit, uint256 deadline) =
            abi.decode(data, (address, address[], uint256, uint256));

        require(deadline >= block.timestamp, "EXPIRED");

        // Determine which token was borrowed
        address borrowToken;
        uint256 borrowAmount;
        address repayToken;

        if (amount0 > 0) {
            borrowToken = IUniswapV2Pair(pair).token0();
            repayToken = IUniswapV2Pair(pair).token1();
            borrowAmount = amount0;
        } else {
            borrowToken = IUniswapV2Pair(pair).token1();
            repayToken = IUniswapV2Pair(pair).token0();
            borrowAmount = amount1;
        }

        // Trade along the path
        uint256 finalAmount = _tradeAlongPath(borrowAmount, tradePath);

        // Calculate and handle repayment + profit
        uint256 repayAmount = _calculateRepayAmount(pair, borrowToken, repayToken, borrowAmount);
        require(finalAmount >= repayAmount, "INSUFFICIENT_REPAY");

        uint256 profit = finalAmount - repayAmount;
        require(profit >= minProfit, "INSUFFICIENT_PROFIT");

        // Repay flash swap
        _safeTransfer(repayToken, pair, repayAmount);

        // Send profit to caller
        if (profit > 0) {
            _safeTransfer(repayToken, caller, profit);
        }

        emit ArbitrageExecuted(caller, pair, borrowToken, borrowAmount, repayToken, repayAmount, profit);
    }

    /// @dev Execute swaps along the trade path, returning final output amount.
    function _tradeAlongPath(uint256 startAmount, address[] memory tradePath)
        internal
        returns (uint256 amountIn)
    {
        amountIn = startAmount;
        for (uint256 i = 0; i < tradePath.length - 1; i++) {
            amountIn = _swap(tradePath[i], tradePath[i + 1], amountIn);
        }
    }

    // ======================================================================
    // INTERNAL: SWAP LOGIC
    // ======================================================================

    /// @notice 在指定 Pair 上将 tokenIn 换为 tokenOut
    /// @dev 直接调用 pair.swap()，不走 Router（节省 gas）
    /// @param tokenIn   输入代币
    /// @param tokenOut  输出代币
    /// @param amountIn  输入数量
    /// @return amountOut 输出数量
    function _swap(address tokenIn, address tokenOut, uint256 amountIn) internal returns (uint256 amountOut) {
        address pair = _pairFor(tokenIn, tokenOut);
        require(pair != address(0), "PAIR_NOT_FOUND");
        require(_isPairDeployed(pair), "PAIR_NOT_DEPLOYED");

        (uint256 reserveIn, uint256 reserveOut) = _getReserves(pair, tokenIn, tokenOut);
        amountOut = _getAmountOut(amountIn, reserveIn, reserveOut);
        require(amountOut > 0, "ZERO_OUTPUT");

        // 将 tokenIn 转入 pair
        _safeTransfer(tokenIn, pair, amountIn);

        // 调用 pair.swap() 换出 tokenOut
        // 注意：输出的 token 放在 token0/token1 位置取决于排序
        (address token0,) = _sortTokens(tokenIn, tokenOut);
        if (tokenIn == token0) {
            // tokenIn = token0, 输入 token0，输出 token1
            IUniswapV2Pair(pair).swap(0, amountOut, address(this), "");
        } else {
            // tokenIn = token1, 输入 token1，输出 token0
            IUniswapV2Pair(pair).swap(amountOut, 0, address(this), "");
        }
    }

    // ======================================================================
    // INTERNAL: UNISWAP V2 MATH (内联，避免外部依赖)
    // ======================================================================

    function _sortTokens(address tokenA, address tokenB) internal pure returns (address token0, address token1) {
        require(tokenA != tokenB, "IDENTICAL_ADDRESSES");
        (token0, token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        require(token0 != address(0), "ZERO_ADDRESS");
    }

    function _pairFor(address tokenA, address tokenB) internal view returns (address) {
        (address token0, address token1) = _sortTokens(tokenA, tokenB);
        bytes32 pairCodeHash = IUniswapV2Factory(factory).pairCodeHash();
        return address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(hex"ff", factory, keccak256(abi.encodePacked(token0, token1)), pairCodeHash)
                    )
                )
            )
        );
    }

    function _isPairDeployed(address pair) internal view returns (bool) {
        // 检查 pair 地址是否有代码（CREATE2 部署后 code.length > 0）
        uint256 size;
        assembly {
            size := extcodesize(pair)
        }
        return size > 0;
    }

    function _getReserves(address pair, address tokenA, address tokenB)
        internal
        view
        returns (uint256 reserveA, uint256 reserveB)
    {
        (address token0,) = _sortTokens(tokenA, tokenB);
        (uint256 reserve0, uint256 reserve1,) = IUniswapV2Pair(pair).getReserves();
        (reserveA, reserveB) = tokenA == token0 ? (reserve0, reserve1) : (reserve1, reserve0);
    }

    /// @notice 给定输入量和储备量，计算输出量（含 0.3% 手续费）
    function _getAmountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut)
        internal
        pure
        returns (uint256 amountOut)
    {
        require(amountIn > 0, "INSUFFICIENT_AMOUNT_IN");
        require(reserveIn > 0 && reserveOut > 0, "INSUFFICIENT_LIQUIDITY");
        uint256 amountInWithFee = amountIn * 997;
        uint256 numerator = amountInWithFee * reserveOut;
        uint256 denominator = (reserveIn * 1000) + amountInWithFee;
        amountOut = numerator / denominator;
    }

    /// @notice 给定期望输出量和储备量，计算所需输入量（含 0.3% 手续费）
    function _getAmountIn(uint256 amountOut, uint256 reserveIn, uint256 reserveOut)
        internal
        pure
        returns (uint256 amountIn)
    {
        require(amountOut > 0, "INSUFFICIENT_AMOUNT_OUT");
        require(reserveIn > 0 && reserveOut > 0, "INSUFFICIENT_LIQUIDITY");
        uint256 numerator = reserveIn * amountOut * 1000;
        uint256 denominator = (reserveOut - amountOut) * 997;
        amountIn = (numerator / denominator) + 1;
    }

    /// @notice 计算 Flash Swap 的归还数量（在 repayToken 中）
    /// @dev 使用 getAmountIn：借出 borrowAmount 个 borrowToken，
    ///      需要归还多少 repayToken 才能满足 K 值。
    function _calculateRepayAmount(address pair, address borrowToken, address repayToken, uint256 borrowAmount)
        internal
        view
        returns (uint256)
    {
        (uint256 reserveBorrow, uint256 reserveRepay) = _getReserves(pair, borrowToken, repayToken);
        return _getAmountIn(borrowAmount, reserveRepay, reserveBorrow);
    }

    // ======================================================================
    // INTERNAL: SAFE TRANSFER
    // ======================================================================

    bytes4 private constant TRANSFER_SELECTOR = bytes4(keccak256(bytes("transfer(address,uint256)")));

    function _safeTransfer(address token, address to, uint256 value) internal {
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(TRANSFER_SELECTOR, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))), "TRANSFER_FAILED");
    }

    // ======================================================================
    // ADMIN: WITHDRAW (紧急提取)
    // ======================================================================

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
        _safeTransfer(token, owner(), balance);
        emit TokenWithdrawn(token, owner(), balance);
    }

    // ======================================================================
    // RECEIVE ETH
    // ======================================================================

    receive() external payable {}
}
