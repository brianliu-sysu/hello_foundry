// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {IFlashLoanSimpleReceiver} from "aave-v3-core/contracts/flashloan/interfaces/IFlashLoanSimpleReceiver.sol";
import {IPoolAddressesProvider} from "aave-v3-core/contracts/interfaces/IPoolAddressesProvider.sol";
import {IPool} from "aave-v3-core/contracts/interfaces/IPool.sol";
import {IERC20} from "./uniswap-v2/periphery/interfaces/IERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {AdminWithdrawable} from "./shared/AdminWithdrawable.sol";
import {UniswapV2Helper} from "./shared/UniswapV2Helper.sol";

/// @title  AaveFlashArbitrage
/// @notice 利用 Aave v3 Flash Loan 借款，在 Uniswap V2 上进行三角/多跳套利
contract AaveFlashArbitrage is IFlashLoanSimpleReceiver, AdminWithdrawable, ReentrancyGuard {
    // ======================================================================
    // EVENTS
    // ======================================================================

    event ArbitrageExecuted(
        address indexed initiator,
        address indexed asset,
        uint256 borrowAmount,
        uint256 premium,
        uint256 repayAmount,
        uint256 profit
    );

    // ======================================================================
    // IMMUTABLES
    // ======================================================================

    IPoolAddressesProvider public immutable override ADDRESSES_PROVIDER;
    IPool public immutable override POOL;
    address public immutable factory;

    // ======================================================================
    // MUTEX
    // ======================================================================
    //
    // 为什么不用 ReentrancyGuard.nonReentrant 而要自己写 lock？
    //   executeArbitrage (nonReentrant) → Aave Pool.flashLoanSimple() → executeOperation (lock)
    //   两个 guard 用不同存储槽，合法回调不会被 nonReentrant 误拦。

    uint256 private unlocked = 1;

    modifier lock() {
        require(unlocked == 1, "AaveFlashArbitrage: LOCKED");
        unlocked = 0;
        _;
        unlocked = 1;
    }

    // ======================================================================
    // CONSTRUCTOR
    // ======================================================================

    constructor(address _provider, address _factory) {
        require(_provider != address(0), "ZERO_PROVIDER");
        require(_factory != address(0), "ZERO_FACTORY");
        ADDRESSES_PROVIDER = IPoolAddressesProvider(_provider);
        POOL = IPool(ADDRESSES_PROVIDER.getPool());
        factory = _factory;
    }

    // ======================================================================
    // EXTERNAL: EXECUTE ARBITRAGE
    // ======================================================================

    function executeArbitrage(
        address asset,
        uint256 borrowAmount,
        address[] calldata tradePath,
        uint256 minProfit,
        uint256 deadline
    ) external onlyOwner nonReentrant {
        require(asset != address(0), "ZERO_ASSET");
        require(borrowAmount > 0, "ZERO_AMOUNT");
        require(tradePath.length >= 3, "PATH_TOO_SHORT");
        require(deadline >= block.timestamp, "EXPIRED");
        require(tradePath[0] == asset, "PATH_START_NOT_ASSET");
        require(tradePath[tradePath.length - 1] == asset, "PATH_END_NOT_ASSET");

        bytes memory params = abi.encode(msg.sender, tradePath, minProfit, deadline);
        POOL.flashLoanSimple(address(this), asset, borrowAmount, params, 0);
    }

    // ======================================================================
    // AAVE CALLBACK
    // ======================================================================

    function executeOperation(
        address asset,
        uint256 amount,
        uint256 premium,
        address /*initiator*/,
        bytes calldata params
    ) external override lock returns (bool) {
        require(msg.sender == address(POOL), "CALLER_NOT_POOL");

        (address caller, address[] memory tradePath, uint256 minProfit, uint256 deadline) =
            abi.decode(params, (address, address[], uint256, uint256));

        require(deadline >= block.timestamp, "EXPIRED");

        uint256 finalAmount = UniswapV2Helper.tradeAlongPath(factory, amount, tradePath);

        uint256 repayAmount = amount + premium;
        require(finalAmount >= repayAmount, "INSUFFICIENT_REPAY");

        uint256 profit = finalAmount - repayAmount;
        require(profit >= minProfit, "INSUFFICIENT_PROFIT");

        IERC20(asset).approve(address(POOL), repayAmount);

        if (profit > 0) {
            UniswapV2Helper.safeTransfer(asset, caller, profit);
        }

        emit ArbitrageExecuted(caller, asset, amount, premium, repayAmount, profit);
        return true;
    }
}
