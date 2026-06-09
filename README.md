# Hello Foundry — Solidity 学习仓库

这是一个通过实战项目学习 **Solidity 智能合约开发** 的个人练习仓库，基于 Foundry 工具链构建，附带 React 前端。

## 涵盖的知识点

| 领域 | 涉及的内容 |
|------|-----------|
| **ERC20 代币** | 标准 ERC20、ERC1363（接收回调）、EIP-2612 Permit、通缩 Rebase Token |
| **ERC721 NFT** | NFT 铸造、元数据 URI、批量 mint、市场交易 |
| **权限控制** | Ownable、owner/admin 分离设计、AdminWithdrawable 共享基类 |
| **资金托管** | TokenBank 存款/取款、Faucet 水龙头 |
| **代币分发** | 线性释放（Vesting）、MemeFactory 一键发币、StakingPool 质押挖矿 |
| **DeFi 借贷** | LendingMarket（多资产 Compound 风格）、超额抵押借款、清算、闪电贷 |
| **闪电贷套利** | Uniswap V2 Flash Swap 套利、Aave v3 Flash Loan 套利、三角路径 Bot |
| **杠杆交易** | 基于 vAMM (x*y=k) 的链上永续合约 — Long/Short/清算 |
| **DEX 基础设施** | 自实现 Uniswap V2（Factory/Pair/Router/WETH + 全套接口） |
| **合约委托** | GasSponsorDelegation（代付 Gas）、BatchTransferDelegation（EIP-7702） |
| **代理模式** | UUPS Upgradeable（Counter V1 → V2 升级）、手动 Proxy |
| **签名验证** | Permit2 签名转账、EIP-2612 Permit |
| **低级调用** | 批量 Call、raw call |

## 合约清单

### DeFi 核心

| 合约 | 说明 |
|------|------|
| `LendingMarket.sol` | 多资产借贷市场 — 存款计息（指数模型）、超额抵押借款、闪电贷（0.09%）、清算（5% 奖励）、分段跳跃利率 |
| `StakingPool.sol` | ETH 质押池 — 每区块 10 KK 奖励、质押 ETH 自动存入 LendingMarket 赚利息 |
| `KKToken.sol` | StakingPool 奖励代币（10 KK/block） |

### 闪电贷套利

| 合约 | 说明 |
|------|------|
| `FlashArbitrage.sol` | Uniswap V2 Flash Swap 三角套利（借 A 还 B，多跳路径） |
| `AaveFlashArbitrage.sol` | Aave v3 Flash Loan → Uniswap V2 套利（借 A 还 A 闭环，0.09% 费率） |

### 杠杆交易（vAMM）

| 合约 | 说明 |
|------|------|
| `LeveragedDEX.sol` | vAMM 杠杆 DEX — 开仓（Long/Short 2–10x）、平仓、清算（维持保证金 6.25%）、ETH 抵押 |

### Uniswap V2（自实现，pragma ^0.8.0）

| 合约 | 说明 |
|------|------|
| `UniswapV2Factory.sol` | Pair 工厂（CREATE2 确定性部署） |
| `UniswapV2Pair.sol` | AMM Pair（mint/burn/swap/flash swap 回调） |
| `UniswapV2ERC20.sol` | LP Token（含 EIP-2612 Permit） |
| `UniswapV2Router02.sol` | 路由（add/remove liquidity、swap、ETH↔WETH） |
| `WETH9.sol` | Wrapped ETH |
| `UniswapV2Library.sol` | 定价公式（getAmountOut/In、pairFor CREATE2 计算） |

### ERC20 代币

| 合约 | 说明 |
|------|------|
| `BrianICOToken.sol` | ERC1363 + EIP-2612 Permit + Owner 可提回误转代币 |
| `DeflationaryToken.sol` | 每日 1% 通缩 Rebase Token（初始 1 亿 DFL，gons/token 模型） |
| `Token.sol` | 基础 ERC20（基于 Faucet） |
| `MemeToken.sol` | Meme 代币（EIP-1167 Minimal Proxy） |

### 代币工具

| 合约 | 说明 |
|------|------|
| `TokenBank.sol` | ERC1363 代币银行（deposit/withdraw/ERC1363/Permit2 存款） |
| `Faucet.sol` | ETH + Token 水龙头（每日限额 + Owner 提回） |
| `NaiveFaucet.sol` | 简化版水龙头 |
| `Vesting.sol` | 代币解锁 — cliff + 24 月线性释放 + 多期补领 + Owner 提取盈余 |

### NFT

| 合约 | 说明 |
|------|------|
| `BrianNFT.sol` | ERC721 NFT + 限量铸造 + IPFS 元数据 |
| `NFTMarket.sol` | NFT 交易市场（list/buy/cancel/fee） |

### MemeFactory

| 合约 | 说明 |
|------|------|
| `MemeFactory.sol` | EIP-1167 Minimal Proxy 工厂 → 一键发 MemeToken |
| `MemeToken.sol` | Meme 代币（Ownable + 内置 Swap） |

### Counter & Proxy

| 合约 | 说明 |
|------|------|
| `Counter.sol` | 简单计数器 |
| `CounterV1Upgradeable.sol` | UUPS 可升级 Counter V1 |
| `CounterV2Upgradeable.sol` | UUPS 可升级 Counter V2（增加递减功能） |
| `proxy.sol` | 手动实现代理合约 |

### 委托 & 签名

| 合约 | 说明 |
|------|------|
| `GasSponsorDelegation.sol` | 代付 Gas 委托 |
| `BatchTransferDelegation.sol` | EIP-7702 批量转账委托 |
| `Permit2.sol` | Permit2 签名转账集成 |
| `ISignatureTransfer.sol` | Permit2 Transfer 接口 |
| `Call.sol` | 低级 call 调用示例 |

### 共享库

| 合约 | 说明 |
|------|------|
| `AdminWithdrawable.sol` | 抽象基类：withdrawETH / withdrawToken / receive（Ownable） |
| `UniswapV2Helper.sol` | library：V2 定价公式 / swap / safeTransfer / tradeAlongPath |

## 目录结构

```
src/
├── dex/            LeveragedDEX （vAMM 杠杆交易）
├── arbitrage/     FlashArbitrage, AaveFlashArbitrage
├── lending/       LendingMarket
├── staking/       StakingPool, KKToken
├── token/         BrianICOToken, DeflationaryToken, Token, TokenBank, Faucet, NaiveFaucet, Vesting
├── nft/           BrianNFT, NFTMarket
├── meme/          MemeFactory, MemeToken
├── counter/       Counter, CounterV1Upgradeable, CounterV2Upgradeable, proxy
├── delegation/    BatchTransferDelegation, GasSponsorDelegation
├── utils/         Call, Permit2, ISignatureTransfer
├── shared/        AdminWithdrawable, UniswapV2Helper
└── uniswap-v2/    core/ (Factory, Pair, ERC20), periphery/ (Router, WETH9, Library)
```

## 技术栈

- **Foundry** — 编译、测试、部署
- **Solidity ^0.8.26** — 编译器（via_ir = true）
- **OpenZeppelin Contracts v5.6** — 标准库（ERC20 / ERC721 / Ownable / UUPS / SafeERC20 / ReentrancyGuard）
- **Aave v3 Core** — 闪电贷接口
- **React + ethers v6** — 前端 DApp

## 🌐 Frontend Architecture

```
frontend/dapp/src/
├── hooks/
│   ├── useWallet.js         # MetaMask connection
│   ├── useLendingMarket.js  # LendingMarket contract hook
│   ├── useStakingPool.js    # StakingPool contract hook
│   ├── useLeveragedDEX.js   # LeveragedDEX contract hook
│   └── useUniswapV2.js      # Uniswap V2 hook
├── views/
│   ├── LeveragedDEXView.jsx  # vAMM Pool / Open / Close / Liquidate
│   ├── LendingMarketView.jsx  # Supply/Borrow/FlashLoan/Dashboard/Admin
│   ├── StakingPoolView.jsx    # Stake/Withdraw/Claim KK
│   └── UniswapV2View.jsx      # AddLiquidity/RemoveLiquidity/Swap
├── utils/
│   └── contract.js          # ABIs + mergeAddress (deploy fallback)
├── config.js                # Manual contract address overrides
└── App.jsx                  # Tab navigation
```

## 快速开始

### 构建

```shell
forge build
```

### 测试

```shell
forge test          # 448 个测试
forge test -vvv     # 详细输出
```

### 部署

```shell
# Uniswap V2 基础设施
forge script script/DeployUniswapV2.s.sol --rpc-url <RPC> --broadcast

# LendingMarket（依赖 WETH9）
forge script script/DeployLendingMarket.s.sol --rpc-url <RPC> --broadcast

# StakingPool + KKToken
forge script script/DeployStakingPool.s.sol --rpc-url <RPC> --broadcast

# FlashArbitrage
forge script script/DeployFlashArbitrage.s.sol --rpc-url <RPC> --broadcast

# AaveFlashArbitrage（需 Aave v3 PoolAddressesProvider）
AAVE_POOL_ADDRESSES_PROVIDER=0x... \
  forge script script/DeployAaveFlashArbitrage.s.sol --rpc-url <RPC> --broadcast

# LeveragedDEX
forge script script/DeployLeveragedDEX.s.sol --rpc-url <RPC> --broadcast

# DeflationaryToken
forge script script/DeployDeflationaryToken.s.sol --rpc-url <RPC> --broadcast
```

### 前端

```shell
cd frontend/dapp
npm install
npm run dev         # 开发模式
npm run build       # 生产构建
```

### 套利监控 Bot

```shell
cd bot
cp .env.example .env
# 编辑 .env 填入 RPC、助记词、合约地址、监控的 Token 列表
npm install
npm start           # 持续监控三角套利
npm run once        # 单次扫描
```

## 参考资料

- [Foundry Book](https://book.getfoundry.sh/)
- [OpenZeppelin Contracts](https://docs.openzeppelin.com/contracts/5.x/)
- [Solidity Documentation](https://docs.soliditylang.org/)
- [Uniswap V2 Whitepaper](https://uniswap.org/whitepaper.pdf)
- [Aave v3 Documentation](https://docs.aave.com/developers/)
- [EIP-2612 Permit](https://eips.ethereum.org/EIPS/eip-2612)
- [EIP-1363 ERC20 回调](https://eips.ethereum.org/EIPS/eip-1363)
- [EIP-7702 Delegation](https://eips.ethereum.org/EIPS/eip-7702)
