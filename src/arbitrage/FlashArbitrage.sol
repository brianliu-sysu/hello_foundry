// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {IUniswapV2Callee} from "../uniswap-v2/core/interfaces/IUniswapV2Callee.sol";
import {IUniswapV2Pair} from "../uniswap-v2/core/interfaces/IUniswapV2Pair.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {AdminWithdrawable} from "../shared/AdminWithdrawable.sol";
import {UniswapV2Helper} from "../shared/UniswapV2Helper.sol";

/// @title  FlashArbitrage
/// @notice 利用 Uniswap V2 Flash Swap 进行多跳路径套利
contract FlashArbitrage is IUniswapV2Callee, AdminWithdrawable, ReentrancyGuard {
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

    // ======================================================================
    // IMMUTABLES
    // ======================================================================

    address public immutable factory;
    address public immutable WETH;

    // ======================================================================
    // MUTEX
    // ======================================================================

    uint256 private unlocked = 1;

    modifier lock() {
        require(unlocked == 1, "FlashArbitrage: LOCKED");
        unlocked = 0;
        _;
        unlocked = 1;
    }

    // ======================================================================
    // CONSTRUCTOR
    // ======================================================================

    constructor(address _factory, address _weth) {
        require(_factory != address(0), "ZERO_FACTORY");
        require(_weth != address(0), "ZERO_WETH");
        factory = _factory;
        WETH = _weth;
    }

    // ======================================================================
    // EXTERNAL: EXECUTE ARBITRAGE
    // ======================================================================

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

        address borrowToken = borrowToken0 ? token0 : token1;
        address repayToken = borrowToken0 ? token1 : token0;
        require(tradePath[0] == borrowToken, "PATH_START_MISMATCH");
        require(tradePath[tradePath.length - 1] == repayToken, "PATH_END_MISMATCH");

        bytes memory data = abi.encode(msg.sender, tradePath, minProfit, deadline);

        if (borrowToken0) {
            IUniswapV2Pair(borrowPair).swap(borrowAmount, 0, address(this), data);
        } else {
            IUniswapV2Pair(borrowPair).swap(0, borrowAmount, address(this), data);
        }
    }

    // ======================================================================
    // FLASH SWAP CALLBACK
    // ======================================================================

    function uniswapV2Call(
        address,
        /*sender*/
        uint256 amount0,
        uint256 amount1,
        bytes calldata data
    )
        external
        override
        lock
    {
        _handleCallback(msg.sender, amount0, amount1, data);
    }

    // ======================================================================
    // INTERNAL: CALLBACK HANDLER
    // ======================================================================

    function _handleCallback(address pair, uint256 amount0, uint256 amount1, bytes calldata data) internal {
        (address caller, address[] memory tradePath, uint256 minProfit, uint256 deadline) =
            abi.decode(data, (address, address[], uint256, uint256));

        require(deadline >= block.timestamp, "EXPIRED");

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

        uint256 finalAmount = UniswapV2Helper.tradeAlongPath(factory, borrowAmount, tradePath);

        uint256 repayAmount = _calculateRepayAmount(pair, borrowToken, repayToken, borrowAmount);
        require(finalAmount >= repayAmount, "INSUFFICIENT_REPAY");

        uint256 profit = finalAmount - repayAmount;
        require(profit >= minProfit, "INSUFFICIENT_PROFIT");

        UniswapV2Helper.safeTransfer(repayToken, pair, repayAmount);
        if (profit > 0) {
            UniswapV2Helper.safeTransfer(repayToken, caller, profit);
        }

        emit ArbitrageExecuted(caller, pair, borrowToken, borrowAmount, repayToken, repayAmount, profit);
    }

    // ======================================================================
    // INTERNAL: FLASH SWAP REPAY MATH
    // ======================================================================

    function _calculateRepayAmount(address pair, address borrowToken, address repayToken, uint256 borrowAmount)
        internal
        view
        returns (uint256)
    {
        (uint256 reserveBorrow, uint256 reserveRepay) = UniswapV2Helper.getReserves(pair, borrowToken, repayToken);
        return UniswapV2Helper.getAmountIn(borrowAmount, reserveRepay, reserveBorrow);
    }
}
