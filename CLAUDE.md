# Hello Foundry — Project Guidelines

## ⚠️ Frontend JS: BigInt / Float Precision (CRITICAL)

The frontend (`frontend/dapp/`) uses **ethers v6** which returns **BigInt** for all on-chain values. JS `Number()` has a safe integer limit of `2^53 ≈ 9e15`. Any ETH/ERC20 amount larger than ~0.009 ETH exceeds this — `Number(bigint)` will silently truncate low bits.

### NEVER do this:
```js
// BROKEN — Number() loses precision when wei > 2^53
const human = Number(bigintWei) / 10 ** decimals;  // precision loss
const raw = BigInt(Math.floor(parseFloat(human) * 10 ** decimals)); // precision loss
```

### ALWAYS do this:
```js
// Correct — BigInt division + string formatting, zero precision loss
const toWei = (humanStr, decimals = 18) => {
  const [whole, frac = ""] = humanStr.split(".");
  const padded = (frac + "0".repeat(decimals)).slice(0, decimals);
  return BigInt(whole) * (10n ** BigInt(decimals)) + BigInt(padded || "0");
};

const fmtToken = (wei, decimals = 18) => {
  const dec = 10n ** BigInt(decimals);
  const whole = wei / dec;
  const frac = (wei % dec).toString().padStart(decimals, "0").slice(0, 6);
  return whole.toString() + "." + frac;
};
```

### Hook `getTokenInfo` must convert `decimals` to Number:
```js
// ethers v6 returns decimals as BigInt (e.g. 18n)
// JS expressions like 10 ** decimals fail with: Cannot mix BigInt and other types
return { symbol, decimals: Number(decimals), balanceOf: balance };
```

### `useContractEvent` / `Promise.all` on ethers v6 Result objects:
- ethers v6 `Result` objects (from contract calls with multiple returns) use **numeric indices** `r[0]`, `r[1]`, etc.
- `{ ...r }` spread does NOT correctly unpack named keys
- Always unpack by index, not by spread:
```js
// Correct
const [reserves] = await Promise.all([pair.getReserves()]);
const reserve0 = reserves[0]; // not reserves.reserve0
```

### MAX button in forms:
- BigInt `0n` is **falsy** in JS (`!0n === true`). Never use `if (!bal)` to check for zero balance — use `if (bal == null || bal <= 0n)` instead.
- Always gate MAX button visibility on actual balance > 0n

### `const` temporal dead zone:
- Derived values that depend on `useState` variables must be declared **after** all state hooks, never before, or the entire component crashes with `ReferenceError`.

## 🛠️ Foundry: `via_ir` Compiler

`foundry.toml` has `via_ir = true` enabled to fix "Stack too deep" errors in complex contracts (FlashArbitrage, AaveFlashArbitrage). This changes Solidity's compilation pipeline — always run `forge clean && forge build` after modifying contracts, and rerun the full suite to catch stale cache issues.

## 📁 Source Architecture

```
src/
├── FlashArbitrage.sol       # Uniswap V2 Flash Swap arbitrage
├── AaveFlashArbitrage.sol   # Aave v3 Flash Loan arbitrage
├── LendingMarket.sol        # Multi-asset lending + flash loans
├── StakingPool.sol          # ETH staking → KK rewards + LendingMarket
├── KKToken.sol              # StakingPool reward token
├── shared/
│   ├── AdminWithdrawable.sol  # withdrawETH / withdrawToken base contract
│   └── UniswapV2Helper.sol    # Uniswap V2 math / swap / safeTransfer library
├── uniswap-v2/              # Forked Uniswap V2 (pragma ^0.8.0)
├── BrianICOToken.sol        # ERC1363 + ERC20Permit test token
└── ...other contracts...
```

## 🧪 Testing Patterns

```solidity
contract XxxTest is Test {
    address public owner = makeAddr("owner");
    address public alice = makeAddr("alice");

    function setUp() public {
        vm.label(alice, "alice");
        vm.prank(owner);
        vm.deal(alice, 100 ether);
        vm.warp(...);   // time manipulation
        vm.roll(...);   // block number manipulation
    }
}
```

## 🌐 Frontend Architecture

```
frontend/dapp/src/
├── hooks/
│   ├── useWallet.js         # MetaMask connection
│   ├── useLendingMarket.js  # LendingMarket contract hook
│   ├── useStakingPool.js    # StakingPool contract hook
│   └── useUniswapV2.js      # Uniswap V2 hook
├── views/
│   ├── LendingMarketView.jsx  # Supply/Borrow/FlashLoan/Dashboard/Admin
│   ├── StakingPoolView.jsx    # Stake/Withdraw/Claim KK
│   └── UniswapV2View.jsx      # AddLiquidity/RemoveLiquidity/Swap
├── utils/
│   └── contract.js          # ABIs + mergeAddress (deploy fallback)
├── config.js                # Manual contract address overrides
└── App.jsx                  # Tab navigation
```
