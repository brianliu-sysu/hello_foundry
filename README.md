# Hello Foundry — Solidity 学习仓库

这是一个通过实战项目学习 **Solidity 智能合约开发** 的个人练习仓库，基于 Foundry 工具链构建。

## 涵盖的知识点

| 领域 | 涉及的内容 |
|------|-----------|
| **ERC20 代币** | 标准 ERC20、ERC1363（接收回调）、EIP-2612 Permit |
| **ERC721 NFT** | NFT 铸造、元数据 URI、批量 mint、页面展示 |
| **权限控制** | Ownable、owner/admin 分离设计 |
| **资金托管** | TokenBank 存款/取款、Faucet 代币水龙头 |
| **代币分发** | 线性释放（Vesting）、MemeFactory 一键发币 |
| **合约委托** | GasSponsorDelegation（代付 Gas）、BatchTransferDelegation |
| **代币兑换** | NFT 市场、MemeToken Swap |
| **代理模式** | UUPS Upgradeable（Counter V1 → V2 升级） |
| **签名验证** | Permit2 签名转账 |
| **低级调用** | 批量 Call、raw call |

## 合约清单

| 合约 | 说明 |
|------|------|
| `Token.sol` | 基础 ERC20 代币 |
| `BrianICOToken.sol` | ERC1363 + EIP-2612 Permit + owner 可提回误转代币 |
| `BrianNFT.sol` | ERC721 NFT，支持批量铸造 |
| `TokenBank.sol` | ERC1363 代币银行，支持存款/取款 |
| `NaiveFaucet.sol` | 简单代币水龙头 |
| `Faucet.sol` | 完整代币水龙头 + admin 提取 |
| `Vesting.sol` | 代币解锁合约：cliff + 24 月线性释放 + 多期补领 + 管理员提取盈余 |
| `MemeFactory.sol` | MemeToken 工厂合约，一键创建代币并可交易 |
| `MemeToken.sol` | Meme 代币 + 内置 Swap |
| `NFTMarket.sol` | NFT 交易市场 |
| `Permit2.sol` | Permit2 签名转账 |
| `Counter.sol` | 简单计数器 |
| `CounterV1Upgradeable.sol` | UUPS 可升级计数器 V1 |
| `CounterV2Upgradeable.sol` | UUPS 可升级计数器 V2（增加递减功能） |
| `proxy.sol` | 手动实现代理合约 |
| `Call.sol` | 低级 call 调用示例 |
| `GasSponsorDelegation.sol` | 代付 Gas 委托 |
| `BatchTransferDelegation.sol` | 批量转账委托 |

## 技术栈

- **Foundry** — 编译、测试、部署、格式化
- **Solidity ^0.8.26** — 编译器
- **OpenZeppelin Contracts v5** — 标准库（ERC20 / ERC721 / Ownable / UUPS / SafeERC20）
- **OpenZeppelin Foundry Upgrades** — UUPS 升级脚本

## 快速开始

### 构建

```shell
forge build
```

### 测试

```shell
forge test
```

### 格式化

```shell
forge fmt
```

### Gas 快照

```shell
forge snapshot
```

### 本地网络

```shell
anvil
```

### 部署脚本

```shell
# 部署 BrianICOToken
forge script script/BrianICOToken.s.sol --rpc-url <RPC> --broadcast

# 部署 Vesting（含代币转入）
forge script script/Vesting.s.sol --rpc-url <RPC> --broadcast

# 指定受益人
BENEFICIARY=0x... forge script script/Vesting.s.sol --rpc-url <RPC> --broadcast
```

### Cast

```shell
cast <subcommand>
```

### 帮助

```shell
forge --help
anvil --help
cast --help
```

## 参考资料

- [Foundry Book](https://book.getfoundry.sh/)
- [OpenZeppelin Contracts](https://docs.openzeppelin.com/contracts/5.x/)
- [Solidity Documentation](https://docs.soliditylang.org/)
- [EIP-2612 Permit](https://eips.ethereum.org/EIPS/eip-2612)
- [EIP-1363 ERC20 回调](https://eips.ethereum.org/EIPS/eip-1363)
