// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title  LeveragedDEX — vAMM-based leveraged trading
/// @notice 使用虚拟 AMM (x*y=k) 实现杠杆交易，无需真实的对手方流动性池。
///         支持 Long（做多）/ Short（做空），杠杆最高 10x。
///         抵押品为 WETH（ETH）。
///
///         vAMM 使用两个虚拟储备：
///           - vBase:  虚拟 ETH 数量
///           - vQuote: 虚拟 USD 数量
///         k = vBase × vQuote（恒定乘积）
///         当前价格 = vQuote / vBase（1e18 精度）
///
///         Long 开仓：存入 ETH 保证金 → vAMM 借出 USD → "买入" vETH
///         Short 开仓：存入 ETH 保证金 → vAMM 借出 vETH → "卖出"获得 USD
///         清算条件：权益 < 名义价值 × 6.25%（维持保证金率）
contract LeveragedDEX is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ======================================================================
    // CONSTANTS
    // ======================================================================

    uint256 public constant PRECISION = 1e18;
    uint256 public constant BPS = 10_000; // 100%
    uint256 public constant MAX_LEVERAGE = 10;
    uint256 public constant MIN_LEVERAGE = 2;
    uint256 public constant LIQUIDATION_THRESHOLD = 625; // 6.25% of notional
    uint256 public constant LIQUIDATION_BONUS_BPS = 500; // 5% of remaining collateral

    // ======================================================================
    // EVENTS
    // ======================================================================

    event PositionOpened(
        uint256 indexed id,
        address indexed trader,
        bool isLong,
        uint256 size,
        uint256 collateral,
        uint256 entryNotional,
        uint256 leverage
    );
    event PositionClosed(uint256 indexed id, address indexed trader, uint256 pnlETH, uint256 returnedETH);
    event Liquidated(uint256 indexed id, address indexed liquidator, uint256 bonusETH);
    event vAMMUpdated(uint256 vBase, uint256 vQuote, uint256 price);

    // ======================================================================
    // STORAGE: vAMM
    // ======================================================================

    uint256 public vBase; // virtual ETH reserves
    uint256 public vQuote; // virtual USD reserves

    // ======================================================================
    // STORAGE: Positions
    // ======================================================================

    uint256 public nextPositionId;

    struct Position {
        address trader;
        uint256 collateral; // ETH margin (wei)
        uint256 size; // ETH amount (wei): longs = extra ETH from swap; shorts = borrowed ETH
        uint256 notional; // USD amount (wei-equivalent): longs = USD borrowed; shorts = USD received
        uint256 leverage;
        bool isLong;
        bool isOpen;
    }

    mapping(uint256 => Position) public positions;
    mapping(address => uint256[]) public userPositions;

    // ======================================================================
    // CONSTRUCTOR
    // ======================================================================

    /// @param _initialBase 初始虚拟 ETH 数量（如 1000 ether = 1000 ETH）
    /// @param _initialQuote 初始虚拟 USD 数量（如 2000e18，即 $2000/ETH）
    constructor(uint256 _initialBase, uint256 _initialQuote) Ownable(msg.sender) {
        require(_initialBase > 0 && _initialQuote > 0, "ZERO_RESERVES");
        vBase = _initialBase;
        vQuote = _initialQuote;
    }

    // ======================================================================
    // CORE: OPEN POSITION
    // ======================================================================

    /// @notice 开仓（Long / Short）
    /// @param leverage 杠杆倍数（2–10）
    /// @param isLong   true = Long / false = Short
    /// @return positionId
    function openPosition(uint256 leverage, bool isLong) external payable nonReentrant returns (uint256 positionId) {
        require(msg.value > 0, "ZERO_MARGIN");
        require(leverage >= MIN_LEVERAGE && leverage <= MAX_LEVERAGE, "INVALID_LEVERAGE");

        uint256 margin = msg.value;
        uint256 notionalETH = margin * leverage; // approx position notional in ETH

        uint256 size;
        uint256 entryNotional;

        if (isLong) {
            (size, entryNotional) = _openLong(margin, leverage, notionalETH);
        } else {
            (size, entryNotional) = _openShort(margin, leverage, notionalETH);
        }

        positionId = nextPositionId++;
        positions[positionId] = Position({
            trader: msg.sender,
            collateral: margin,
            size: size,
            notional: entryNotional,
            leverage: leverage,
            isLong: isLong,
            isOpen: true
        });
        userPositions[msg.sender].push(positionId);

        emit PositionOpened(positionId, msg.sender, isLong, size, margin, entryNotional, leverage);
    }

    // ======================================================================
    // CORE: CLOSE POSITION
    // ======================================================================

    /// @notice 平仓
    /// @param positionId 持仓 ID
    /// @return returnedETH 退还的 ETH
    function closePosition(uint256 positionId) external nonReentrant returns (uint256 returnedETH) {
        Position storage pos = positions[positionId];
        require(pos.isOpen, "ALREADY_CLOSED");
        require(pos.trader == msg.sender, "NOT_TRADER");

        int256 pnlETH;
        if (pos.isLong) {
            pnlETH = _closeLong(pos.size, pos.notional);
        } else {
            pnlETH = _closeShort(pos.size, pos.notional);
        }

        // Collateral + PnL
        int256 total = int256(pos.collateral) + pnlETH;
        if (total <= 0) {
            returnedETH = 0; // 全部亏损
        } else {
            returnedETH = uint256(total);
        }

        pos.isOpen = false;

        if (returnedETH > 0) {
            (bool ok,) = payable(msg.sender).call{value: returnedETH}("");
            require(ok, "ETH_TRANSFER_FAILED");
        }

        emit PositionClosed(positionId, msg.sender, uint256(pnlETH > 0 ? pnlETH : int256(0)), returnedETH);
    }

    // ======================================================================
    // LIQUIDATION
    // ======================================================================

    /// @notice 清算不健康的头寸，清算者获得剩余保证金的 5% 作为奖励
    /// @param positionId 被清算的持仓 ID
    function liquidate(uint256 positionId) external nonReentrant returns (uint256 bonusETH) {
        Position storage pos = positions[positionId];
        require(pos.isOpen, "ALREADY_CLOSED");
        require(isLiquidatable(positionId), "HEALTHY");

        int256 pnlETH;
        if (pos.isLong) {
            pnlETH = _closeLong(pos.size, pos.notional);
        } else {
            pnlETH = _closeShort(pos.size, pos.notional);
        }

        int256 remaining = int256(pos.collateral) + pnlETH;
        pos.isOpen = false;

        if (remaining <= 0) {
            bonusETH = 0; // 全部亏完，没有奖励
        } else {
            uint256 total = uint256(remaining);
            bonusETH = total * LIQUIDATION_BONUS_BPS / BPS;
            uint256 toTrader = total - bonusETH;
            if (toTrader > 0) {
                (bool ok,) = payable(pos.trader).call{value: toTrader}("");
                require(ok, "ETH_TRANSFER_FAILED");
            }
            if (bonusETH > 0) {
                (bool ok2,) = payable(msg.sender).call{value: bonusETH}("");
                require(ok2, "ETH_TRANSFER_FAILED");
            }
        }

        emit Liquidated(positionId, msg.sender, bonusETH);
    }

    // ======================================================================
    // VIEW: LIQUIDATION CHECK
    // ======================================================================

    /// @notice 检查持仓是否可被清算
    function isLiquidatable(uint256 positionId) public view returns (bool) {
        Position memory pos = positions[positionId];
        if (!pos.isOpen) return false;

        int256 pnl = _unrealizedPnL(pos.isLong, pos.size, pos.notional);
        int256 equity = int256(pos.collateral) + pnl;
        if (equity <= 0) return true; // 资不抵债，立即可清算

        // 维持保证金 = 名义价值 × 6.25%
        uint256 notionalETH = pos.collateral * pos.leverage; // 近似名义价值
        uint256 maintenance = notionalETH * LIQUIDATION_THRESHOLD / BPS;

        return uint256(equity) < maintenance;
    }

    /// @notice 查询持仓的未实现盈亏（ETH）
    function getUnrealizedPnL(uint256 positionId) external view returns (int256 pnlETH) {
        Position memory pos = positions[positionId];
        if (!pos.isOpen) return 0;
        return _unrealizedPnL(pos.isLong, pos.size, pos.notional);
    }

    // ======================================================================
    // VIEW: vAMM PRICE
    // ======================================================================

    /// @notice 当前 vAMM 标记价格（USD/ETH，1e18 精度）
    function getMarkPrice() public view returns (uint256) {
        return vQuote * PRECISION / vBase;
    }

    /// @notice 获取用户所有仓位 ID
    function getUserPositions(address user) external view returns (uint256[] memory) {
        return userPositions[user];
    }

    // ======================================================================
    // INTERNAL: OPEN / CLOSE MATH
    // ======================================================================

    /// @dev Long: borrow USD from vAMM → buy ETH
    ///      vQuote += borrowedUSD  →  vBase = k / vQuote  →  size = oldVBase - newVBase
    function _openLong(
        uint256 margin,
        uint256 leverage,
        uint256 /*notionalETH*/
    )
        internal
        returns (uint256 size, uint256 entryNotional)
    {
        // borrowedUSD = margin * (leverage - 1) * price_in_USD_per_ETH
        uint256 price = getMarkPrice();
        uint256 borrowedUSD = margin * (leverage - 1) * price / PRECISION;

        uint256 oldVBase = vBase;
        uint256 oldVQuote = vQuote;
        uint256 k = oldVBase * oldVQuote;

        vQuote = oldVQuote + borrowedUSD;
        vBase = k / vQuote;
        size = oldVBase > vBase ? oldVBase - vBase : 0;
        entryNotional = borrowedUSD;

        require(size > 0, "ZERO_SIZE");
        emit vAMMUpdated(vBase, vQuote, getMarkPrice());
    }

    /// @dev Short: borrow ETH from vAMM → sell for USD
    ///      vBase += size  →  vQuote = k / vBase  →  entryNotional = oldVQuote - newVQuote
    function _openShort(
        uint256,
        /*margin*/
        uint256,
        /*leverage*/
        uint256 notionalETH
    )
        internal
        returns (uint256 size, uint256 entryNotional)
    {
        size = notionalETH; // borrow notionalETH worth of ETH

        uint256 oldVBase = vBase;
        uint256 oldVQuote = vQuote;
        uint256 k = oldVBase * oldVQuote;

        require(size < oldVBase * 9 / 10, "POSITION_TOO_LARGE"); // 不能借超过 vBase 的 90%

        vBase = oldVBase + size;
        vQuote = k / vBase;
        entryNotional = oldVQuote > vQuote ? oldVQuote - vQuote : 0;

        require(entryNotional > 0, "ZERO_NOTIONAL");
        emit vAMMUpdated(vBase, vQuote, getMarkPrice());
    }

    /// @dev Close long: give back size ETH → get USD. PnL = gotBackUSD - entryNotional (converted to ETH)
    function _closeLong(uint256 size, uint256 entryNotional) internal returns (int256 pnlETH) {
        uint256 oldVBase = vBase;
        uint256 oldVQuote = vQuote;
        uint256 k = oldVBase * oldVQuote;

        vBase = oldVBase + size;
        vQuote = k / vBase;
        uint256 gotBackUSD = oldVQuote > vQuote ? oldVQuote - vQuote : 0;

        // pnl in USD
        int256 pnlUSD = int256(gotBackUSD) - int256(entryNotional);
        // convert to ETH at close price
        uint256 closePrice = vQuote * PRECISION / vBase;
        pnlETH = (pnlUSD * int256(PRECISION)) / int256(closePrice);

        emit vAMMUpdated(vBase, vQuote, closePrice);
    }

    /// @dev Close short: buy back size ETH with entryNotional USD. PnL = size - buyBackETH
    function _closeShort(uint256 size, uint256 entryNotional) internal returns (int256 pnlETH) {
        uint256 oldVBase = vBase;
        uint256 oldVQuote = vQuote;
        uint256 k = oldVBase * oldVQuote;

        vQuote = oldVQuote + entryNotional;
        vBase = k / vQuote;
        uint256 buyBackETH = oldVBase > vBase ? oldVBase - vBase : 0;

        // Short PnL: if buyBackETH < size, didn't get enough ETH back → LOSS
        //             if buyBackETH > size, got more ETH than borrowed → PROFIT (shouldn't happen)
        pnlETH = int256(buyBackETH) - int256(size);

        emit vAMMUpdated(vBase, vQuote, vQuote * PRECISION / vBase);
    }

    /// @dev 未实现盈亏（纯 view，不修改 vAMM）
    function _unrealizedPnL(bool isLong, uint256 size, uint256 notional) internal view returns (int256 pnlETH) {
        uint256 k = vBase * vQuote;

        if (isLong) {
            // If we close now: add size to vBase, get quote back
            uint256 newVBase = vBase + size;
            uint256 newVQuote = k / newVBase;
            uint256 gotBack = vQuote > newVQuote ? vQuote - newVQuote : 0;
            int256 pnlUSD = int256(gotBack) - int256(notional);
            pnlETH = (pnlUSD * int256(PRECISION)) / int256(newVQuote * PRECISION / newVBase);
        } else {
            // If we close now: add notional to vQuote, get base back
            uint256 newVQuote = vQuote + notional;
            uint256 newVBase = k / newVQuote;
            uint256 buyBack = vBase > newVBase ? vBase - newVBase : 0;
            pnlETH = int256(buyBack) - int256(size);
        }
    }

    // ======================================================================
    // RECEIVE ETH
    // ======================================================================

    receive() external payable {}
}
