// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @title  DeflationaryToken — daily 1% deflation via rebase
/// @notice 初始发行量 100,000,000 DFL。每 24 小时总供应自动通缩 1%。
///         采用 "gons per token" 模型（类似 Ampleforth / ElasticSwap）：
///
///           - _gonsPerToken：多少个内部单位（gon）等于 1 个 DFL。
///                            初始值 = 1e18（PRECISION）。
///           - _gonBalances[user]：用户持有的 gon 数量（固定，只有 transfer 会变）。
///           - balanceOf(user) = _gonBalances[user] * PRECISION / _gonsPerToken
///           - totalSupply()     = _totalGons * PRECISION / _gonsPerToken
///
///         通缩时 _gonsPerToken ↑（每个 token 需要更多 gon）→ 每个 gon 代表更少的 token
///         → 用户余额自动减少，无需额外操作。
///
///         每日 1% 通缩公式：gonsPerToken = gonsPerToken * 100 / 99
///         即每天每个 token 需要多 1.0101…% 的 gon 来代表。
contract DeflationaryToken is ERC20, ERC20Permit, Ownable {
    uint256 internal constant PRECISION = 1e18;
    uint256 internal constant DEFLATION_PERIOD = 1 days;
    uint256 internal constant DEFLATION_RATE_BPS = 100; // 1% = 100 bps
    uint256 internal constant BPS_DENOMINATOR = 10000;

    uint256 internal _gonsPerToken; // gon ⇄ token 转换率（初始 PRECISION）
    mapping(address user => uint256) internal _gonBalances; // 用户 gon 余额
    uint256 internal _totalGons; // 总 gon 供应量（恒定，除非 mint/burn）

    uint256 public lastRebaseTime; // 上次通缩时间戳

    // ======================================================================
    // EVENTS
    // ======================================================================

    event Rebased(uint256 newGonsPerToken, uint256 oldTotalSupply, uint256 newTotalSupply, uint256 periodsElapsed);

    // ======================================================================
    // CONSTRUCTOR
    // ======================================================================

    /// @param initialSupply 初始发行量（1e18 精度，如 100_000_000 ether = 1 亿）
    constructor(uint256 initialSupply)
        ERC20("Deflationary Token", "DFL")
        ERC20Permit("Deflationary Token")
        Ownable(msg.sender)
    {
        require(initialSupply > 0, "ZERO_SUPPLY");
        _gonsPerToken = PRECISION;
        lastRebaseTime = block.timestamp;
        // Use _mint so our overridden _update handles gon accounting correctly
        _mint(msg.sender, initialSupply);
    }

    // ======================================================================
    // ERC20 OVERRIDES (rebase-aware)
    // ======================================================================

    /// @notice 用户当前余额 = gon 余额 / gonsPerToken
    function balanceOf(address account) public view override returns (uint256) {
        return (_gonBalances[account] * PRECISION) / _gonsPerToken;
    }

    /// @notice 当前总供应 = 总 gon / gonsPerToken
    function totalSupply() public view override returns (uint256) {
        return (_totalGons * PRECISION) / _gonsPerToken;
    }

    /// @dev 重写 _update 以使用 gon 记账
    function _update(address from, address to, uint256 value) internal override {
        // value is in token units — convert to gons
        uint256 gonValue = (value * _gonsPerToken) / PRECISION;

        if (from == address(0)) {
            // Mint
            _totalGons += gonValue;
        } else {
            uint256 fromGonBalance = _gonBalances[from];
            require(fromGonBalance >= gonValue, "ERC20: transfer amount exceeds balance");
            unchecked {
                _gonBalances[from] = fromGonBalance - gonValue;
            }
        }

        if (to == address(0)) {
            // Burn
            unchecked {
                _totalGons -= gonValue;
            }
        } else {
            unchecked {
                _gonBalances[to] += gonValue;
            }
        }

        emit Transfer(from, to, value);
    }

    // ======================================================================
    // REBASE
    // ======================================================================

    /// @notice 执行通缩（任何人可调用，每 24h 至多一次）
    /// @return periodsElapsed 通缩周期数
    function rebase() public returns (uint256 periodsElapsed) {
        uint256 elapsed = block.timestamp - lastRebaseTime;
        periodsElapsed = elapsed / DEFLATION_PERIOD;
        require(periodsElapsed > 0, "TOO_EARLY");

        uint256 oldTotalSupply = totalSupply();

        // 每日 _gonsPerToken = _gonsPerToken * (100 - 1)% 的逆运算
        // 即 _gonsPerToken = _gonsPerToken * BPS_DENOMINATOR / (BPS_DENOMINATOR - DEFLATION_RATE_BPS)
        //               = _gonsPerToken * 10000 / 9900 = _gonsPerToken * 100 / 99
        for (uint256 i = 0; i < periodsElapsed; i++) {
            _gonsPerToken = (_gonsPerToken * BPS_DENOMINATOR) / (BPS_DENOMINATOR - DEFLATION_RATE_BPS);
        }

        lastRebaseTime += periodsElapsed * DEFLATION_PERIOD;

        emit Rebased(_gonsPerToken, oldTotalSupply, totalSupply(), periodsElapsed);
    }

    /// @notice 查询下次可通缩时间
    function nextRebaseTime() public view returns (uint256) {
        return lastRebaseTime + DEFLATION_PERIOD;
    }

    // ======================================================================
    // VIEW: gon-level data (for UIs that need high precision)
    // ======================================================================

    /// @notice 用户持有的 gon 数量（内部分配单位）
    function gonBalanceOf(address account) public view returns (uint256) {
        return _gonBalances[account];
    }

    /// @notice 当前 gon→token 转换率
    function gonsPerToken() public view returns (uint256) {
        return _gonsPerToken;
    }

    /// @notice 总 gon 供应量（内部分配单位总量）
    function totalGons() public view returns (uint256) {
        return _totalGons;
    }
}
