// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {KKToken} from "./KKToken.sol";

/// @notice WETH9 minimal interface (deposit / withdraw)
interface IWETH9 {
    function deposit() external payable;
    function withdraw(uint256 wad) external;
    function balanceOf(address) external view returns (uint256);
}

/// @notice LendingMarket 最小接口（supply / withdraw view）
interface ILendingMarket {
    function supply(address asset, uint256 amount) external;
    function withdraw(address asset, uint256 amount) external;
    function getUserSupply(address user, address asset) external view returns (uint256);
}

/// @title  StakingPool
/// @notice 用户质押 ETH，赚取 KK 奖励代币（每区块 10 KK，按质押量+时间均分）。
///         质押的 ETH 会自动存入 LendingMarket 赚取额外借贷利息。
///         KK 随时可领取。
contract StakingPool is Ownable, ReentrancyGuard {
    // ======================================================================
    // CONSTANTS
    // ======================================================================

    uint256 public constant REWARD_PER_BLOCK = 10 * 1e18; // 每区块 10 KK（18 decimals）
    uint256 internal constant PRECISION = 1e18;

    // ======================================================================
    // EVENTS
    // ======================================================================

    event Staked(address indexed user, uint256 ethAmount);
    event Withdrawn(address indexed user, uint256 ethAmount, uint256 stakeShare);
    event RewardClaimed(address indexed user, uint256 amount);
    event RewardsAccrued(uint256 blocks, uint256 amount);
    event LendingMarketUpdated(address indexed oldMarket, address indexed newMarket);

    // ======================================================================
    // IMMUTABLES
    // ======================================================================

    IWETH9 public immutable WETH;
    KKToken public immutable KK;
    ILendingMarket public lendingMarket;

    // ======================================================================
    // STORAGE
    // ======================================================================

    uint256 public totalStaked;                          // 总质押 ETH 量（wei）
    uint256 public rewardPerTokenStored;                 // 每质押 1 ETH 的累计奖励（PRECISION 精度）
    uint256 public lastUpdateBlock;                      // 上次更新时 block.number
    uint256 public totalRewardsMinted;                   // 累计已铸造的 KK

    mapping(address user => uint256) public stakedBalance;           // 用户质押 ETH 量
    mapping(address user => uint256) public userRewardPerTokenPaid;  // 用户已结算的 rewardPerToken
    mapping(address user => uint256) public rewards;                 // 用户待领取的 KK

    // ======================================================================
    // CONSTRUCTOR
    // ======================================================================

    /// @param _weth           WETH9 地址
    /// @param _kk             KKToken 地址（Pool 必须是其 Owner）
    /// @param _lendingMarket  LendingMarket 地址
    constructor(address _weth, address _kk, address _lendingMarket) Ownable(msg.sender) {
        require(_weth != address(0), "ZERO_WETH");
        require(_kk != address(0), "ZERO_KK");
        require(_lendingMarket != address(0), "ZERO_MARKET");
        WETH = IWETH9(_weth);
        KK = KKToken(_kk);
        lendingMarket = ILendingMarket(_lendingMarket);
        lastUpdateBlock = block.number;

        // 无限授权 WETH 给 LendingMarket
        IERC20(_weth).approve(_lendingMarket, type(uint256).max);
    }

    // ======================================================================
    // CORE: STAKE
    // ======================================================================

    /// @notice 质押 ETH，开始赚取 KK 奖励 + LendingMarket 利息
    function stake() external payable nonReentrant {
        require(msg.value > 0, "ZERO_STAKE");
        _accrueRewards();

        // 先结算用户已有的奖励
        _updateReward(msg.sender);

        uint256 amount = msg.value;

        // 1. ETH → WETH
        WETH.deposit{value: amount}();

        // 2. WETH → LendingMarket（开始赚取借贷利息）
        lendingMarket.supply(address(WETH), amount);

        // 3. 记录质押
        stakedBalance[msg.sender] += amount;
        totalStaked += amount;

        emit Staked(msg.sender, amount);
    }

    // ======================================================================
    // CORE: WITHDRAW
    // ======================================================================

    /// @notice 赎回质押的 ETH（含 LendingMarket 利息分成）
    /// @param stakeAmount 要赎回的质押 ETH 量（wei）
    function withdraw(uint256 stakeAmount) external nonReentrant {
        require(stakeAmount > 0, "ZERO_WITHDRAW");
        require(stakedBalance[msg.sender] >= stakeAmount, "INSUFFICIENT_STAKE");

        _accrueRewards();
        _updateReward(msg.sender);

        // 按比例计算可提取的 WETH（含 LendingMarket 利息）
        uint256 poolWETH = getUserWETH(address(this));
        uint256 wethShare = (stakeAmount * poolWETH) / totalStaked;

        // 1. 从 LendingMarket 提回 WETH
        lendingMarket.withdraw(address(WETH), wethShare);

        // 2. WETH → ETH
        WETH.withdraw(wethShare);

        // 3. 更新状态
        stakedBalance[msg.sender] -= stakeAmount;
        totalStaked -= stakeAmount;

        // 4. 发送 ETH 给用户
        (bool ok,) = payable(msg.sender).call{value: wethShare}("");
        require(ok, "ETH_TRANSFER_FAILED");

        emit Withdrawn(msg.sender, wethShare, stakeAmount);
    }

    // ======================================================================
    // CORE: CLAIM KK REWARDS
    // ======================================================================

    /// @notice 领取已累积的 KK 奖励
    function claimReward() public nonReentrant returns (uint256) {
        _accrueRewards();
        _updateReward(msg.sender);

        uint256 reward = rewards[msg.sender];
        if (reward > 0) {
            rewards[msg.sender] = 0;
            IERC20(KK).transfer(msg.sender, reward);
            emit RewardClaimed(msg.sender, reward);
        }
        return reward;
    }

    // ======================================================================
    // VIEW
    // ======================================================================

    /// @notice 查询用户当前待领取的 KK 奖励
    function earned(address user) public view returns (uint256) {
        // 预测本次 _accrueRewards 后的 rewardPerToken
        uint256 predictedRPT = rewardPerTokenStored;
        if (totalStaked > 0) {
            uint256 blocksElapsed = block.number - lastUpdateBlock;
            uint256 newRewards = blocksElapsed * REWARD_PER_BLOCK;
            predictedRPT += (newRewards * PRECISION) / totalStaked;
        }
        return rewards[user]
            + (stakedBalance[user] * (predictedRPT - userRewardPerTokenPaid[user])) / PRECISION;
    }

    /// @notice 查询合约在 LendingMarket 中的 WETH 余额
    function getUserWETH(address user) public view returns (uint256) {
        return lendingMarket.getUserSupply(user, address(WETH));
    }

    /// @notice 查询 Pool 在 LendingMarket 中已赚取的总利息
    function getTotalInterestEarned() public view returns (uint256) {
        uint256 supplied = getUserWETH(address(this));
        // 利息 = 当前余额 - 用户本金（近似，因为可能有提现导致的复杂度）
        return supplied > totalStaked ? supplied - totalStaked : 0;
    }

    // ======================================================================
    // ADMIN
    // ======================================================================

    /// @notice Owner 更新 LendingMarket 地址（迁移时用）
    function setLendingMarket(address _newMarket) external onlyOwner {
        require(_newMarket != address(0), "ZERO_MARKET");
        address old = address(lendingMarket);
        lendingMarket = ILendingMarket(_newMarket);
        // 授权新的 LendingMarket
        IERC20(address(WETH)).approve(_newMarket, type(uint256).max);
        emit LendingMarketUpdated(old, _newMarket);
    }

    // ======================================================================
    // INTERNAL: REWARD ACCRUAL
    // ======================================================================

    /// @dev 将 KK 奖励累积到 rewardPerTokenStored
    function _accrueRewards() internal {
        uint256 blocksElapsed = block.number - lastUpdateBlock;
        if (blocksElapsed == 0) return;

        // 1. 铸造新 KK（StakingPool 必须是 KKToken 的 owner）
        uint256 minted = KK.mintPoolReward(blocksElapsed);
        totalRewardsMinted += minted;

        // 2. 更新全局 rewardPerToken
        if (totalStaked > 0) {
            rewardPerTokenStored += (minted * PRECISION) / totalStaked;
        }
        // 如果还没人质押（totalStaked == 0），铸造的 KK 就留在池子里，不给任何人

        lastUpdateBlock = block.number;

        emit RewardsAccrued(blocksElapsed, minted);
    }

    /// @dev 更新用户的待领取奖励（在 stake/withdraw/claim 之前调用）
    function _updateReward(address user) internal {
        uint256 newReward = stakedBalance[user]
            * (rewardPerTokenStored - userRewardPerTokenPaid[user]) / PRECISION;
        if (newReward > 0) {
            rewards[user] += newReward;
        }
        userRewardPerTokenPaid[user] = rewardPerTokenStored;
    }

    // ======================================================================
    // RECEIVE
    // ======================================================================

    receive() external payable {
        // 仅 WETH 在 withdraw 时会转入 ETH，不接受直接转账
        require(msg.sender == address(WETH), "ONLY_WETH");
    }
}
