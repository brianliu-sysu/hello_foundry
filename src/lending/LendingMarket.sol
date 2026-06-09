// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title  LendingMarket — 多资产借贷市场 + 闪电贷
/// @notice 支持：
///         - 存入资产赚取利息（Compound 风格指数模型）
///         - 超额抵押借款
///         - 闪电贷（单笔交易内借还，费率极低）
///         - 清算（健康因子 < 1 时触发）
///
///         核心设计：
///         - 每个资产有一个 Reserve（准备金），追踪总流动性和总债务
///         - 利息通过 liquidityIndex / borrowIndex 累积（无需逐笔计息）
///         - 用户余额以 scaled balance 存储（除以指数的值）
///         - 利率模型：分段线性 + 跳跃利率（80% 最优利用率后飙升）
///         - 价格由 Owner 手动设置（或用 Chainlink Oracle 替换）
contract LendingMarket is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ======================================================================
    // CONSTANTS
    // ======================================================================

    uint256 public constant RAY = 1e27;                          // 精度基数（27 位小数）
    uint256 public constant BPS = 10000;                          // 基点基数
    uint256 public constant SECONDS_PER_YEAR = 365 days;

    // 闪电贷回调选择器
    bytes4 private constant FLASHLOAN_CALLBACK =
        bytes4(keccak256("onFlashLoan(address,address,uint256,uint256,bytes)"));

    // ======================================================================
    // EVENTS
    // ======================================================================

    event ReserveInitialized(address indexed asset, uint256 collateralFactor, uint256 price);
    event Supplied(address indexed user, address indexed asset, uint256 amount);
    event Withdrawn(address indexed user, address indexed asset, uint256 amount);
    event Borrowed(address indexed user, address indexed asset, uint256 amount);
    event Repaid(address indexed user, address indexed asset, uint256 amount);
    event FlashLoan(
        address indexed receiver,
        address indexed asset,
        uint256 amount,
        uint256 premium
    );
    event Liquidated(
        address indexed liquidator,
        address indexed borrower,
        address collateralAsset,
        address debtAsset,
        uint256 debtCovered,
        uint256 collateralSeized
    );
    event ReserveUpdated(address indexed asset, uint256 price, uint256 collateralFactor);
    event FlashLoanPremiumUpdated(address indexed asset, uint256 newPremium);

    // ======================================================================
    // DATA TYPES
    // ======================================================================

    /// @notice 每个资产的准备金数据
    struct ReserveData {
        // 指数（利率累积因子，单位 RAY）
        uint256 liquidityIndex;       // 存款累积因子
        uint256 borrowIndex;          // 借款累积因子
        // 总量（实际金额，非 scaled）
        uint256 totalLiquidity;
        uint256 totalDebt;
        // 时间戳
        uint256 lastUpdateTimestamp;
        // 利率模型参数（RAY）
        uint256 optimalUtilizationRate; // 最优利用率（默认 80% = 0.8e27）
        uint256 baseBorrowRate;         // 基础借款利率（默认 2% = 0.02e27）
        uint256 slope1;                 // 最优利用率内斜率
        uint256 slope2;                 // 超出最优利用率后的跳跃斜率
        // 风险参数（BPS）
        uint256 collateralFactor;       // 抵押因子（默认 75% = 7500 bps）
        uint256 liquidationThreshold;   // 清算阈值（默认 85% = 8500 bps）
        uint256 liquidationBonus;       // 清算奖励（默认 5% = 10500 bps）
        uint256 flashLoanPremium;       // 闪电贷手续费（默认 9 bps = 0.09%）
        // Oracle 价格（USD，1e8 精度，兼容 Chainlink 格式）
        uint256 price;
        // 状态
        bool isActive;
    }

    /// @notice 用户余额（scaled，除以指数即得实际值）
    struct UserBalance {
        mapping(address asset => uint256) scaledSupply;  // supply / liquidityIndex
        mapping(address asset => uint256) scaledBorrow;  // borrow / borrowIndex
    }

    // ======================================================================
    // STORAGE
    // ======================================================================

    /// @notice 已注册资产列表（用于迭代查询）
    address[] public reservesList;

    /// @notice 每个资产的准备金数据
    mapping(address asset => ReserveData) public reserves;

    /// @notice 用户是否将某资产作为抵押品
    mapping(address user => mapping(address asset => bool)) public isUsingAsCollateral;

    /// @notice 用户余额
    mapping(address user => UserBalance) internal _balances;

    // ======================================================================
    // MODIFIERS
    // ======================================================================

    modifier onlyActive(address asset) {
        require(reserves[asset].isActive, "LM: INACTIVE_RESERVE");
        _;
    }

    // ======================================================================
    // CONSTRUCTOR
    // ======================================================================

    constructor() Ownable(msg.sender) {}

    // ======================================================================
    // ADMIN: RESERVE MANAGEMENT
    // ======================================================================

    /// @notice 初始化（添加）一个新的借贷资产
    /// @param asset                        ERC20 代币地址
    /// @param collateralFactor            抵押因子（bps，如 7500 = 75%）
    /// @param liquidationThreshold        清算阈值（bps，如 8500 = 85%）
    /// @param liquidationBonus            清算奖励（bps，如 10500 = 5%）
    /// @param flashLoanPremium            闪电贷费率（bps，如 9 = 0.09%）
    /// @param price                       初始 USD 价格（1e8 精度）
    /// @param optimalUtilizationRate      最优利用率（RAY）
    /// @param baseBorrowRate              基础借款利率（RAY）
    /// @param slope1                      斜率 1（RAY）
    /// @param slope2                      斜率 2（RAY）
    function initReserve(
        address asset,
        uint256 collateralFactor,
        uint256 liquidationThreshold,
        uint256 liquidationBonus,
        uint256 flashLoanPremium,
        uint256 price,
        uint256 optimalUtilizationRate,
        uint256 baseBorrowRate,
        uint256 slope1,
        uint256 slope2
    ) external onlyOwner {
        require(!reserves[asset].isActive, "LM: ALREADY_ACTIVE");
        require(asset != address(0), "LM: ZERO_ADDRESS");
        require(collateralFactor <= BPS, "LM: INVALID_CF");
        require(liquidationThreshold <= BPS, "LM: INVALID_LT");
        require(price > 0, "LM: ZERO_PRICE");

        reserves[asset] = ReserveData({
            liquidityIndex: RAY,
            borrowIndex: RAY,
            totalLiquidity: 0,
            totalDebt: 0,
            lastUpdateTimestamp: block.timestamp,
            optimalUtilizationRate: optimalUtilizationRate,
            baseBorrowRate: baseBorrowRate,
            slope1: slope1,
            slope2: slope2,
            collateralFactor: collateralFactor,
            liquidationThreshold: liquidationThreshold,
            liquidationBonus: liquidationBonus,
            flashLoanPremium: flashLoanPremium,
            price: price,
            isActive: true
        });

        reservesList.push(asset);

        emit ReserveInitialized(asset, collateralFactor, price);
    }

    /// @notice 更新资产价格（临时 Oracle 方案，可替换为 Chainlink）
    function setAssetPrice(address asset, uint256 price) external onlyOwner onlyActive(asset) {
        // 更新价格前先累积利息
        _accrueInterest(asset);
        reserves[asset].price = price;
        emit ReserveUpdated(asset, price, reserves[asset].collateralFactor);
    }

    /// @notice 更新抵押因子
    function setCollateralFactor(address asset, uint256 cf) external onlyOwner onlyActive(asset) {
        require(cf <= BPS, "LM: INVALID_CF");
        _accrueInterest(asset);
        reserves[asset].collateralFactor = cf;
        emit ReserveUpdated(asset, reserves[asset].price, cf);
    }

    /// @notice 更新闪电贷费率
    function setFlashLoanPremium(address asset, uint256 premium) external onlyOwner onlyActive(asset) {
        require(premium <= 1000, "LM: PREMIUM_TOO_HIGH"); // 最高 10%
        reserves[asset].flashLoanPremium = premium;
        emit FlashLoanPremiumUpdated(asset, premium);
    }

    // ======================================================================
    // CORE: SUPPLY / WITHDRAW
    // ======================================================================

    /// @notice 存入资产，开始赚取利息
    /// @param asset  资产地址
    /// @param amount 存入金额（wei）
    function supply(address asset, uint256 amount) external onlyActive(asset) nonReentrant {
        require(amount > 0, "LM: ZERO_AMOUNT");
        _accrueInterest(asset);

        ReserveData storage r = reserves[asset];

        uint256 scaledAmount = (amount * RAY) / r.liquidityIndex;
        _balances[msg.sender].scaledSupply[asset] += scaledAmount;
        r.totalLiquidity += amount;

        IERC20(asset).safeTransferFrom(msg.sender, address(this), amount);

        emit Supplied(msg.sender, asset, amount);
    }

    /// @notice 提取已存入的资产（含利息）
    /// @param asset  资产地址
    /// @param amount 提取金额（wei）
    function withdraw(address asset, uint256 amount) external onlyActive(asset) nonReentrant {
        require(amount > 0, "LM: ZERO_AMOUNT");
        _accrueInterest(asset);

        ReserveData storage r = reserves[asset];
        UserBalance storage u = _balances[msg.sender];

        uint256 actualSupply = _actualSupply(msg.sender, asset);
        require(amount <= actualSupply, "LM: INSUFFICIENT_SUPPLY");

        // 提取后仍需满足抵押要求
        uint256 scaledAmount = (amount * RAY) / r.liquidityIndex;
        u.scaledSupply[asset] -= scaledAmount;
        r.totalLiquidity -= amount;

        // 如果该资产不再有余额，取消抵押标记
        if (_actualSupply(msg.sender, asset) == 0) {
            isUsingAsCollateral[msg.sender][asset] = false;
        }

        // 提现后检查健康因子
        if (_hasAnyDebt(msg.sender)) {
            (,,,,, uint256 healthFactor) = _getUserAccountData(msg.sender);
            require(healthFactor >= RAY, "LM: HEALTH_FACTOR_BELOW_1");
        }

        IERC20(asset).safeTransfer(msg.sender, amount);

        emit Withdrawn(msg.sender, asset, amount);
    }

    /// @notice 设置某资产是否作为抵押品
    function setUserUseAsCollateral(address asset, bool useAsCollateral)
        external
        onlyActive(asset)
    {
        if (useAsCollateral) {
            require(_actualSupply(msg.sender, asset) > 0, "LM: NO_SUPPLY");
        }
        isUsingAsCollateral[msg.sender][asset] = useAsCollateral;
    }

    // ======================================================================
    // CORE: BORROW / REPAY
    // ======================================================================

    /// @notice 借款（需有足够抵押品）
    /// @param asset  资产地址
    /// @param amount 借款金额（wei）
    function borrow(address asset, uint256 amount) external onlyActive(asset) nonReentrant {
        require(amount > 0, "LM: ZERO_AMOUNT");
        _accrueInterest(asset);

        ReserveData storage r = reserves[asset];

        require(amount <= _availableLiquidity(asset), "LM: INSUFFICIENT_LIQUIDITY");

        uint256 scaledAmount = (amount * RAY) / r.borrowIndex;
        _balances[msg.sender].scaledBorrow[asset] += scaledAmount;
        r.totalDebt += amount;

        // 借款后检查健康因子
        (,,,,, uint256 healthFactor) = _getUserAccountData(msg.sender);
        require(healthFactor >= RAY, "LM: HEALTH_FACTOR_BELOW_1");

        IERC20(asset).safeTransfer(msg.sender, amount);

        emit Borrowed(msg.sender, asset, amount);
    }

    /// @notice 偿还借款（含利息）
    /// @param asset  资产地址
    /// @param amount 还款金额（wei）
    function repay(address asset, uint256 amount) external onlyActive(asset) nonReentrant {
        require(amount > 0, "LM: ZERO_AMOUNT");
        _accrueInterest(asset);

        ReserveData storage r = reserves[asset];
        UserBalance storage u = _balances[msg.sender];

        uint256 actualBorrow = _actualBorrow(msg.sender, asset);
        if (amount > actualBorrow) {
            amount = actualBorrow; // 只还清所有债务
        }
        require(amount > 0, "LM: NO_DEBT");

        uint256 scaledAmount = (amount * RAY) / r.borrowIndex;
        u.scaledBorrow[asset] -= scaledAmount;
        r.totalDebt -= amount;

        IERC20(asset).safeTransferFrom(msg.sender, address(this), amount);

        emit Repaid(msg.sender, asset, amount);
    }

    // ======================================================================
    // FLASH LOAN
    // ======================================================================

    /// @notice 闪电贷 — 无抵押借出，单笔交易内归还
    /// @param receiverAddress 接收回调的合约地址（需实现 IFlashLoanReceiver）
    /// @param asset           借款资产
    /// @param amount          借款金额（wei）
    /// @param params          自定义参数（传给回调）
    function flashLoan(
        address receiverAddress,
        address asset,
        uint256 amount,
        bytes calldata params
    ) external onlyActive(asset) nonReentrant {
        require(amount > 0, "LM: ZERO_AMOUNT");
        require(amount <= _availableLiquidity(asset), "LM: INSUFFICIENT_LIQUIDITY");
        require(receiverAddress != address(this), "LM: SELF_LOAN");

        _accrueInterest(asset);

        ReserveData storage r = reserves[asset];
        uint256 premium = (amount * r.flashLoanPremium) / BPS;

        // 1. 转出借款
        IERC20(asset).safeTransfer(receiverAddress, amount);

        // 2. 回调 receiver，让它执行套利/清算等逻辑
        require(
            _callFlashLoanCallback(receiverAddress, msg.sender, asset, amount, premium, params),
            "LM: FLASHLOAN_CALLBACK_FAILED"
        );

        // 3. 拉回本金 + 手续费
        uint256 totalRepay = amount + premium;
        IERC20(asset).safeTransferFrom(receiverAddress, address(this), totalRepay);

        // 4. 手续费计入准备金（增加总流动性，归存款人所有）
        r.totalLiquidity += premium;

        emit FlashLoan(receiverAddress, asset, amount, premium);
    }

    /// @dev 通过 low-level call 调用 receiver 的 onFlashLoan 回调
    function _callFlashLoanCallback(
        address receiver,
        address initiator,
        address asset,
        uint256 amount,
        uint256 premium,
        bytes memory params
    ) internal returns (bool) {
        bytes memory data = abi.encodeWithSelector(
            FLASHLOAN_CALLBACK,
            initiator,
            asset,
            amount,
            premium,
            params
        );
        (bool callOk, bytes memory returnData) = receiver.call(data);
        if (!callOk || returnData.length == 0) return false;
        return abi.decode(returnData, (bool));
    }

    // ======================================================================
    // LIQUIDATION
    // ======================================================================

    /// @notice 清算一个不健康的头寸
    /// @param collateralAsset 抵押品资产地址
    /// @param debtAsset       债务资产地址
    /// @param borrower        被清算者
    /// @param debtToCover     清算者愿意偿还的债务金额（debtAsset 单位）
    function liquidate(
        address collateralAsset,
        address debtAsset,
        address borrower,
        uint256 debtToCover
    ) external onlyActive(collateralAsset) onlyActive(debtAsset) nonReentrant {
        require(borrower != msg.sender, "LM: SELF_LIQUIDATE");
        require(debtToCover > 0, "LM: ZERO_AMOUNT");

        // 检查被清算者健康因子
        (,,,,, uint256 healthFactor) = _getUserAccountData(borrower);
        require(healthFactor < RAY, "LM: HEALTH_FACTOR_ABOVE_1"); // < 1.0 in RAY

        _accrueInterest(collateralAsset);
        _accrueInterest(debtAsset);

        ReserveData storage cReserve = reserves[collateralAsset];
        ReserveData storage dReserve = reserves[debtAsset];

        uint256 actualBorrow = _actualBorrow(borrower, debtAsset);
        if (debtToCover > actualBorrow) {
            debtToCover = actualBorrow;
        }

        // 计算可获得的抵押品数量
        // collateralSeized = (debtToCover * dReserve.price / cReserve.price) * liquidationBonus / BPS
        uint256 collateralSeized =
            (debtToCover * dReserve.price * cReserve.liquidationBonus) / (cReserve.price * BPS);

        uint256 actualCollateral = _actualSupply(borrower, collateralAsset);
        require(collateralSeized <= actualCollateral, "LM: INSUFFICIENT_COLLATERAL");

        // 更新被清算者的余额
        UserBalance storage b = _balances[borrower];
        uint256 scaledDebtRepay = (debtToCover * RAY) / dReserve.borrowIndex;
        uint256 scaledCollSeized = (collateralSeized * RAY) / cReserve.liquidityIndex;

        b.scaledBorrow[debtAsset] -= scaledDebtRepay;
        b.scaledSupply[collateralAsset] -= scaledCollSeized;
        dReserve.totalDebt -= debtToCover;
        cReserve.totalLiquidity -= collateralSeized;

        if (_actualSupply(borrower, collateralAsset) == 0) {
            isUsingAsCollateral[borrower][collateralAsset] = false;
        }

        // 清算者偿还债务 + 接收抵押品
        IERC20(debtAsset).safeTransferFrom(msg.sender, address(this), debtToCover);
        IERC20(collateralAsset).safeTransfer(msg.sender, collateralSeized);

        emit Liquidated(msg.sender, borrower, collateralAsset, debtAsset, debtToCover, collateralSeized);
    }

    // ======================================================================
    // VIEW: USER DATA
    // ======================================================================

    /// @notice 查询用户账户数据
    /// @return totalCollateralUSD    抵押品总价值（USD，1e8 精度）
    /// @return totalDebtUSD           债务总价值（USD，1e8 精度）
    /// @return availableBorrowsUSD   可借额度（USD，1e8 精度）
    /// @return currentLiquidationThreshold  当前清算阈值
    /// @return ltv                            当前 LTV
    /// @return healthFactor                    健康因子（RAY）
    function getUserAccountData(address user)
        external
        view
        returns (
            uint256 totalCollateralUSD,
            uint256 totalDebtUSD,
            uint256 availableBorrowsUSD,
            uint256 currentLiquidationThreshold,
            uint256 ltv,
            uint256 healthFactor
        )
    {
        return _getUserAccountData(user);
    }

    function _getUserAccountData(address user)
        internal
        view
        returns (
            uint256 totalCollateralUSD,
            uint256 totalDebtUSD,
            uint256 availableBorrowsUSD,
            uint256 currentLiquidationThreshold,
            uint256 ltv,
            uint256 healthFactor
        )
    {
        totalCollateralUSD = 0;
        totalDebtUSD = 0;
        uint256 weightedAvgLtv = 0;
        uint256 weightedAvgLiqThreshold = 0;

        uint256 len = reservesList.length;
        for (uint256 i = 0; i < len; i++) {
            address asset = reservesList[i];
            if (!reserves[asset].isActive) continue;

            ReserveData memory r = reserves[asset];
            uint256 supplyValue = (_actualSupplyView(user, asset) * r.price) / 1e8;
            uint256 borrowValue = (_actualBorrowView(user, asset) * r.price) / 1e8;

            if (supplyValue > 0 && isUsingAsCollateral[user][asset]) {
                totalCollateralUSD += supplyValue;
                weightedAvgLtv += supplyValue * r.collateralFactor;
                weightedAvgLiqThreshold += supplyValue * r.liquidationThreshold;
            }
            if (borrowValue > 0) {
                totalDebtUSD += borrowValue;
            }
        }

        if (totalCollateralUSD > 0) {
            ltv = weightedAvgLtv / totalCollateralUSD;         // 加权平均 LTV
            currentLiquidationThreshold = weightedAvgLiqThreshold / totalCollateralUSD;
        }

        if (totalDebtUSD > 0 && totalCollateralUSD > 0) {
            // 最大可借 = 抵押品价值 * 加权平均 LTV / BPS
            uint256 maxBorrowUSD = (totalCollateralUSD * ltv) / BPS;
            if (maxBorrowUSD > totalDebtUSD) {
                availableBorrowsUSD = maxBorrowUSD - totalDebtUSD;
            }
            // 健康因子 = (collateral * liquidationThreshold / BPS) / debt
            // 以 RAY 表示：> 1e27 = 安全，< 1e27 = 可清算
            uint256 adjustedCollateral = (totalCollateralUSD * currentLiquidationThreshold) / BPS;
            healthFactor = (adjustedCollateral * RAY) / totalDebtUSD;
        } else if (totalDebtUSD == 0) {
            healthFactor = type(uint256).max; // 无债务 = 绝对安全
        }
    }

    // ======================================================================
    // VIEW: RESERVE DATA
    // ======================================================================

    /// @notice 获取当前借款利率（年化，RAY 精度）
    function getCurrentBorrowRate(address asset) public view onlyActive(asset) returns (uint256) {
        ReserveData memory r = reserves[asset];
        if (r.totalLiquidity == 0) return r.baseBorrowRate;

        uint256 utilization = (r.totalDebt * RAY) / r.totalLiquidity;

        if (utilization <= r.optimalUtilizationRate) {
            // 线性区：baseRate + (utilization / optimalRate) * slope1
            return r.baseBorrowRate + (utilization * r.slope1) / r.optimalUtilizationRate;
        } else {
            // 跳跃区：baseRate + slope1 + ((utilization - optimalRate) / (1 - optimalRate)) * slope2
            uint256 excessUtil = utilization - r.optimalUtilizationRate;
            uint256 normalizer = RAY - r.optimalUtilizationRate;
            return r.baseBorrowRate + r.slope1 + (excessUtil * r.slope2) / normalizer;
        }
    }

    /// @notice 获取当前存款利率（年化，RAY 精度）
    /// @dev 结算利率 = 借款利率 * 利用率 * (1 - 储备因子)
    function getCurrentSupplyRate(address asset) public view onlyActive(asset) returns (uint256) {
        ReserveData memory r = reserves[asset];
        if (r.totalLiquidity == 0) return 0;

        uint256 borrowRate = getCurrentBorrowRate(asset);
        uint256 utilization = (r.totalDebt * RAY) / r.totalLiquidity;
        return (borrowRate * utilization) / RAY;
    }

    /// @notice 获取用户在某资产的实际存款余额（含利息）
    function getUserSupply(address user, address asset) external view returns (uint256) {
        return _actualSupplyView(user, asset);
    }

    /// @notice 获取用户在某资产的实际借款余额（含利息）
    function getUserBorrow(address user, address asset) external view returns (uint256) {
        return _actualBorrowView(user, asset);
    }

    function _actualSupplyView(address user, address asset) internal view returns (uint256) {
        ReserveData memory r = reserves[asset];
        if (!r.isActive) return 0;
        return (_balances[user].scaledSupply[asset] * _latestLiquidityIndexView(asset)) / RAY;
    }

    function _actualBorrowView(address user, address asset) internal view returns (uint256) {
        ReserveData memory r = reserves[asset];
        if (!r.isActive) return 0;
        return (_balances[user].scaledBorrow[asset] * _latestBorrowIndexView(asset)) / RAY;
    }

    function _latestLiquidityIndexView(address asset) internal view returns (uint256) {
        ReserveData memory r = reserves[asset];
        if (!r.isActive) return RAY;
        if (r.totalLiquidity == 0) return RAY; // 没有存款时指数不变

        uint256 supplyRate = getCurrentSupplyRate(asset);
        uint256 timeDelta = block.timestamp - r.lastUpdateTimestamp;
        if (timeDelta == 0) return r.liquidityIndex;

        return r.liquidityIndex + ((r.liquidityIndex * supplyRate * timeDelta) / SECONDS_PER_YEAR) / RAY;
    }

    function _latestBorrowIndexView(address asset) internal view returns (uint256) {
        ReserveData memory r = reserves[asset];
        if (!r.isActive) return RAY;

        uint256 borrowRate = getCurrentBorrowRate(asset);
        uint256 timeDelta = block.timestamp - r.lastUpdateTimestamp;
        if (timeDelta == 0) return r.borrowIndex;

        return r.borrowIndex + ((r.borrowIndex * borrowRate * timeDelta) / SECONDS_PER_YEAR) / RAY;
    }

    /// @notice 可选：获取活跃的 reserves 列表（方便前端和 Bot 查询）
    function getReservesList() external view returns (address[] memory) {
        return reservesList;
    }

    // ======================================================================
    // INTERNAL: INTEREST ACCRUAL
    // ======================================================================

    /// @dev 将储备金的指数更新到当前时间
    function _accrueInterest(address asset) internal {
        ReserveData storage r = reserves[asset];
        if (!r.isActive) return;

        uint256 timeDelta = block.timestamp - r.lastUpdateTimestamp;
        if (timeDelta == 0) return;

        // 更新借款指数
        if (r.totalDebt > 0) {
            uint256 borrowRate = getCurrentBorrowRate(asset);
            uint256 accrued = (r.borrowIndex * borrowRate * timeDelta) / SECONDS_PER_YEAR / RAY;
            r.borrowIndex += accrued;
        }

        // 更新存款指数
        if (r.totalLiquidity > 0) {
            uint256 supplyRate = getCurrentSupplyRate(asset);
            uint256 accrued = (r.liquidityIndex * supplyRate * timeDelta) / SECONDS_PER_YEAR / RAY;
            r.liquidityIndex += accrued;
        }

        r.lastUpdateTimestamp = block.timestamp;
    }

    // ======================================================================
    // INTERNAL: HELPERS
    // ======================================================================

    function _availableLiquidity(address asset) internal view returns (uint256) {
        ReserveData memory r = reserves[asset];
        if (r.totalLiquidity <= r.totalDebt) return 0;
        return r.totalLiquidity - r.totalDebt;
    }

    function _actualSupply(address user, address asset) internal view returns (uint256) {
        return _actualSupplyView(user, asset);
    }

    function _actualBorrow(address user, address asset) internal view returns (uint256) {
        return _actualBorrowView(user, asset);
    }

    function _hasAnyDebt(address user) internal view returns (bool) {
        uint256 len = reservesList.length;
        for (uint256 i = 0; i < len; i++) {
            if (_balances[user].scaledBorrow[reservesList[i]] > 0) return true;
        }
        return false;
    }

    // ======================================================================
    // RECEIVE ETH (not supported — use WETH)
    // ======================================================================

    receive() external payable {
        revert("LM: ETH_NOT_SUPPORTED");
    }
}

/// @notice 闪电贷回调接口 — 要被 LendingMarket.flashLoan 回调的合约必须实现此接口
interface IFlashLoanReceiver {
    /// @param initiator  调用 flashLoan 的地址
    /// @param asset     借款资产
    /// @param amount    借款金额
    /// @param premium   手续费
    /// @param params    自定义参数
    function onFlashLoan(
        address initiator,
        address asset,
        uint256 amount,
        uint256 premium,
        bytes calldata params
    ) external returns (bool);
}
