// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

/// @notice 所有 Uniswap V2 相关的纯工具函数集中在此库中。
///         被 FlashArbitrage / AaveFlashArbitrage / Bot 等合约共用。
///
///         为什么不用现有的 UniswapV2Library.sol（src/uniswap-v2/periphery/libraries/）？
///         因为 UniswapV2Library 依赖 `factory.pairCodeHash()`（需 external call），
///         且缺少 _isPairDeployed / _safeTransfer / _swap 等我们常用的方法。
///         本项目已按 0.8.x 编译、使用已验证的 997/1000 手续费公式，
///         内联实现无需外部依赖。

import {IUniswapV2Pair} from "../uniswap-v2/core/interfaces/IUniswapV2Pair.sol";
import {IUniswapV2Factory} from "../uniswap-v2/core/interfaces/IUniswapV2Factory.sol";

library UniswapV2Helper {
    // ======================================================================
    // CONSTANTS
    // ======================================================================

    bytes4 internal constant TRANSFER_SELECTOR =
        bytes4(keccak256(bytes("transfer(address,uint256)")));

    // ======================================================================
    // TOKEN SORTING & PAIR ADDRESS
    // ======================================================================

    function sortTokens(address tokenA, address tokenB)
        internal
        pure
        returns (address token0, address token1)
    {
        require(tokenA != tokenB, "IDENTICAL_ADDRESSES");
        (token0, token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        require(token0 != address(0), "ZERO_ADDRESS");
    }

    function pairFor(address factory, address tokenA, address tokenB)
        internal
        view
        returns (address)
    {
        (address token0, address token1) = sortTokens(tokenA, tokenB);
        bytes32 pairCodeHash = IUniswapV2Factory(factory).pairCodeHash();
        return address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(
                            hex"ff", factory, keccak256(abi.encodePacked(token0, token1)), pairCodeHash
                        )
                    )
                )
            )
        );
    }

    function isPairDeployed(address pair) internal view returns (bool) {
        uint256 size;
        assembly {
            size := extcodesize(pair)
        }
        return size > 0;
    }

    // ======================================================================
    // RESERVE QUERIES
    // ======================================================================

    function getReserves(address pair, address tokenA, address tokenB)
        internal
        view
        returns (uint256 reserveA, uint256 reserveB)
    {
        (address token0,) = sortTokens(tokenA, tokenB);
        (uint256 reserve0, uint256 reserve1,) = IUniswapV2Pair(pair).getReserves();
        (reserveA, reserveB) = tokenA == token0 ? (reserve0, reserve1) : (reserve1, reserve0);
    }

    // ======================================================================
    // PRICING (0.3% fee — 997 / 1000)
    // ======================================================================

    function getAmountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut)
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

    function getAmountIn(uint256 amountOut, uint256 reserveIn, uint256 reserveOut)
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

    // ======================================================================
    // SWAP EXECUTION
    // ======================================================================

    /// @notice 在指定 Pair 上将 tokenIn 换为 tokenOut（直接调用 pair.swap，不走 Router）
    /// @param factory Uniswap V2 Factory 地址
    /// @param tokenIn   输入代币
    /// @param tokenOut  输出代币
    /// @param amountIn  输入数量
    /// @return amountOut 输出数量
    function swap(address factory, address tokenIn, address tokenOut, uint256 amountIn)
        internal
        returns (uint256 amountOut)
    {
        address pair = pairFor(factory, tokenIn, tokenOut);
        require(pair != address(0), "PAIR_NOT_FOUND");
        require(isPairDeployed(pair), "PAIR_NOT_DEPLOYED");

        (uint256 reserveIn, uint256 reserveOut) = getReserves(pair, tokenIn, tokenOut);
        amountOut = getAmountOut(amountIn, reserveIn, reserveOut);
        require(amountOut > 0, "ZERO_OUTPUT");

        // 将 tokenIn 转入 pair
        safeTransfer(tokenIn, pair, amountIn);

        // 调用 pair.swap() 换出 tokenOut
        (address token0,) = sortTokens(tokenIn, tokenOut);
        if (tokenIn == token0) {
            IUniswapV2Pair(pair).swap(0, amountOut, address(this), "");
        } else {
            IUniswapV2Pair(pair).swap(amountOut, 0, address(this), "");
        }
    }

    /// @notice 沿 tradePath 逐跳交易
    /// @param factory    Uniswap V2 Factory 地址
    /// @param startAmount 起始金额
    /// @param tradePath   交易路径数组
    /// @return amountIn 最终金额
    function tradeAlongPath(address factory, uint256 startAmount, address[] memory tradePath)
        internal
        returns (uint256 amountIn)
    {
        amountIn = startAmount;
        for (uint256 i = 0; i < tradePath.length - 1; i++) {
            amountIn = swap(factory, tradePath[i], tradePath[i + 1], amountIn);
        }
    }

    // ======================================================================
    // SAFE TRANSFER
    // ======================================================================

    /// @notice 低层级 ERC20 transfer，兼容不返回 bool 的代币
    function safeTransfer(address token, address to, uint256 value) internal {
        (bool success, bytes memory data) =
            token.call(abi.encodeWithSelector(TRANSFER_SELECTOR, to, value));
        require(
            success && (data.length == 0 || abi.decode(data, (bool))), "TRANSFER_FAILED"
        );
    }
}
