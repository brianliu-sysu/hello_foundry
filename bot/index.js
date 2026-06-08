/**
 * Flash Arbitrage Bot — Uniswap V2 Triangular Arbitrage Monitor
 *
 * Monitors configured token pairs on Uniswap V2 for triangular arbitrage
 * opportunities. When a profitable path is found, calls the FlashArbitrage
 * contract to execute a flash swap arbitrage atomically.
 *
 * Algorithm:
 *   1. Fetch live reserves from all monitored pairs
 *   2. For every triangular path (borrowPair, path[3]):
 *      - Calculate: borrow A from pair(A,B)
 *      - Trade A → C via pair(A,C)
 *      - Trade C → B via pair(B,C)
 *      - Repay B to pair(A,B)
 *      - If final B > repayment + minProfit, execute
 *   3. Also check reverse direction for each borrow pair
 *
 * Usage:
 *   cp .env.example .env
 *   # Edit .env with your RPC, addresses, mnemonic, tokens
 *   npm install
 *   npm start          # continuous monitoring
 *   npm run once       # single scan, print results
 */

import { ethers } from "ethers";
import CONFIG from "./config.js";

// ============================================================================
// MINIMAL ABIs (only the functions we need)
// ============================================================================

const FACTORY_ABI = [
  "function getPair(address,address) external view returns (address)",
];

const PAIR_ABI = [
  "function getReserves() external view returns (uint112,uint112,uint32)",
  "function token0() external view returns (address)",
  "function token1() external view returns (address)",
  "function swap(uint256,uint256,address,bytes) external",
];

const ERC20_ABI = [
  "function decimals() external view returns (uint8)",
  "function symbol() external view returns (string)",
  "function balanceOf(address) external view returns (uint256)",
];

const FLASH_ARBITRAGE_ABI = [
  "function executeArbitrage(address borrowPair, bool borrowToken0, uint256 borrowAmount, address[] calldata tradePath, uint256 minProfit, uint256 deadline) external",
  "function factory() external view returns (address)",
  "function WETH() external view returns (address)",
  "function owner() external view returns (address)",
  "event ArbitrageExecuted(address indexed caller, address indexed borrowPair, address borrowToken, uint256 borrowAmount, address repayToken, uint256 repayAmount, uint256 profit)",
];

// ============================================================================
// LOGGER
// ============================================================================

const LEVELS = { debug: 0, info: 1, warn: 2, error: 3 };
const LEVEL = LEVELS[CONFIG.logLevel] ?? LEVELS.info;

const logger = {
  debug: (...args) => LEVEL <= 0 && console.log("[DEBUG]", ...args),
  info: (...args) => LEVEL <= 1 && console.log("[INFO]", ...args),
  warn: (...args) => LEVEL <= 2 && console.warn("[WARN]", ...args),
  error: (...args) => LEVEL <= 3 && console.error("[ERROR]", ...args),
};

// ============================================================================
// UNISWAP V2 MATH (mirrors Solidity UniswapV2Library)
// ============================================================================

const BASIS_POINTS = 1000n;
const FEE_NUMERATOR = 997n;
const FEE_DENOMINATOR = 1000n;

/**
 * Given input amount and reserves, calculate output amount with 0.3% fee.
 * amountOut = (amountIn * 997 * reserveOut) / (reserveIn * 1000 + amountIn * 997)
 */
function getAmountOut(amountIn, reserveIn, reserveOut) {
  if (amountIn <= 0n) return 0n;
  if (reserveIn <= 0n || reserveOut <= 0n) return 0n;
  const amountInWithFee = amountIn * FEE_NUMERATOR;
  const numerator = amountInWithFee * reserveOut;
  const denominator = reserveIn * FEE_DENOMINATOR + amountInWithFee;
  return numerator / denominator;
}

/**
 * Given desired output amount and reserves, calculate required input amount.
 * amountIn = (reserveIn * amountOut * 1000) / ((reserveOut - amountOut) * 997) + 1
 */
function getAmountIn(amountOut, reserveIn, reserveOut) {
  if (amountOut <= 0n) return 0n;
  if (reserveIn <= 0n || reserveOut <= amountOut) return 0n;
  const numerator = reserveIn * amountOut * BASIS_POINTS;
  const denominator = (reserveOut - amountOut) * FEE_NUMERATOR;
  return numerator / denominator + 1n;
}

/**
 * Sort two token addresses (mimics Solidity sortTokens).
 */
function sortTokens(tokenA, tokenB) {
  const a = tokenA.toLowerCase();
  const b = tokenB.toLowerCase();
  if (a === b) throw new Error("IDENTICAL_ADDRESSES");
  return a < b ? [tokenA, tokenB] : [tokenB, tokenA];
}

// ============================================================================
// PAIR CACHE
// ============================================================================

/**
 * PairInfo holds token ordering and reserves for one Uniswap V2 pair.
 */
class PairInfo {
  constructor(address, token0, token1) {
    this.address = address; // checksummed
    this.token0 = token0; // checksummed, token0 < token1
    this.token1 = token1; // checksummed
    this.reserve0 = 0n;
    this.reserve1 = 0n;
    this.blockTimestampLast = 0;
  }

  /**
   * Get reserves for a given token direction.
   * Returns [reserveIn, reserveOut] where reserveIn is for `tokenIn` and
   * reserveOut is for the OTHER token.
   */
  getReservesFor(tokenIn) {
    const tIn = tokenIn.toLowerCase();
    const t0 = this.token0.toLowerCase();
    if (tIn === t0) {
      return [this.reserve0, this.reserve1];
    }
    return [this.reserve1, this.reserve0];
  }

  /**
   * Get the other token in the pair.
   */
  getOtherToken(token) {
    const t = token.toLowerCase();
    const t0 = this.token0.toLowerCase();
    return t === t0 ? this.token1 : this.token0;
  }

  updateReserves(r0, r1, ts) {
    this.reserve0 = r0;
    this.reserve1 = r1;
    this.blockTimestampLast = ts;
  }
}

// ============================================================================
// ARBITRAGE SCANNER
// ============================================================================

class ArbitrageScanner {
  /**
   * @param {ethers.Contract} factory - UniswapV2Factory contract
   * @param {string} wethAddress - WETH address (checksummed)
   * @param {string[]} monitoredTokens - Token addresses to monitor
   * @param {Map<string, PairInfo>} pairCache - Map of pairAddress -> PairInfo
   */
  constructor(factory, wethAddress, monitoredTokens, pairCache) {
    this.factory = factory;
    this.weth = ethers.getAddress(wethAddress);
    this.tokens = monitoredTokens.map((t) => ethers.getAddress(t));
    this.pairCache = pairCache;
  }

  /**
   * Fetch fresh reserves for all pairs involving monitored tokens.
   */
  async refreshReserves() {
    const pairsToFetch = new Set();
    for (const t of this.pairCache.values()) {
      pairsToFetch.add(t.address);
    }

    // Fetch all reserves in parallel
    const results = await Promise.allSettled(
      [...pairsToFetch].map(async (pairAddr) => {
        const pairContract = new ethers.Contract(pairAddr, PAIR_ABI, this.factory.runner);
        const [reserves, token0, token1] = await Promise.all([
          pairContract.getReserves(),
          pairContract.token0(),
          pairContract.token1(),
        ]);
        return { pairAddr, reserves, token0, token1 };
      })
    );

    // Update cache
    for (const result of results) {
      if (result.status === "fulfilled") {
        const { pairAddr, reserves, token0, token1 } = result.value;
        const r0 = BigInt(reserves[0].toString());
        const r1 = BigInt(reserves[1].toString());
        const ts = Number(reserves[2]);

        let info = this.pairCache.get(pairAddr.toLowerCase());
        if (!info) {
          info = new PairInfo(pairAddr, token0, token1);
          this.pairCache.set(pairAddr.toLowerCase(), info);
        }
        info.updateReserves(r0, r1, ts);
      }
    }
  }

  /**
   * Ensure all pairs exist (create PairInfo entries) for every combination
   * of monitored tokens. Skips non-existent pairs.
   */
  async discoverPairs() {
    const n = this.tokens.length;

    for (let i = 0; i < n; i++) {
      for (let j = i + 1; j < n; j++) {
        const [t0, t1] = sortTokens(this.tokens[i], this.tokens[j]);
        const key = `${t0.toLowerCase()}_${t1.toLowerCase()}`;

        // Skip if already cached
        const existing = [...this.pairCache.values()].find(
          (p) =>
            p.token0.toLowerCase() === t0.toLowerCase() &&
            p.token1.toLowerCase() === t1.toLowerCase()
        );
        if (existing) continue;

        try {
          const pairAddr = await this.factory.getPair(t0, t1);
          if (pairAddr && pairAddr !== ethers.ZeroAddress) {
            const checksummed = ethers.getAddress(pairAddr);
            this.pairCache.set(checksummed.toLowerCase(), new PairInfo(checksummed, t0, t1));
            logger.info(`Discovered pair: ${t0.slice(0, 8)}... / ${t1.slice(0, 8)}... → ${checksummed.slice(0, 10)}...`);
          } else {
            logger.warn(`No pair for ${t0.slice(0, 8)}... / ${t1.slice(0, 8)}... — skipping`);
          }
        } catch (err) {
          logger.warn(`Error fetching pair for ${t0.slice(0, 8)}.../${t1.slice(0, 8)}...: ${err.message}`);
        }
      }
    }

    logger.info(`Total pairs monitored: ${this.pairCache.size}`);
  }

  /**
   * Generate all possible triangular arbitrage paths.
   *
   * A triangular path looks like:
   *   borrowPair: (A, B) — borrow A, repay B
   *   trade path: [A, C, B] — trade A→C on pair(A,C), C→B on pair(B,C)
   *
   * We evaluate both directions for each borrow pair.
   *
   * @returns {Array<{borrowPair: string, borrowToken0: boolean, path: string[]}>}
   */
  generatePaths() {
    const paths = [];
    const pairList = [...this.pairCache.values()];

    // Build adjacency: token -> [other tokens it's paired with]
    const adjacency = new Map(); // tokenLower -> Set<otherTokenLower>
    for (const pair of pairList) {
      const t0 = pair.token0.toLowerCase();
      const t1 = pair.token1.toLowerCase();
      if (!adjacency.has(t0)) adjacency.set(t0, new Set());
      if (!adjacency.has(t1)) adjacency.set(t1, new Set());
      adjacency.get(t0).add(t1);
      adjacency.get(t1).add(t0);
    }

    // For each pair as borrow pair, try to find an intermediate token
    for (const borrowPair of pairList) {
      const a = borrowPair.token0.toLowerCase(); // token0
      const b = borrowPair.token1.toLowerCase(); // token1

      const aNeighbors = adjacency.get(a) || new Set();
      const bNeighbors = adjacency.get(b) || new Set();

      // Find tokens that are paired with BOTH a and b
      for (const c of aNeighbors) {
        if (c === b) continue; // skip same token
        if (bNeighbors.has(c)) {
          // We have a triangle: a, b, c all paired with each other

          // Direction 1: borrow A (token0 of borrowPair), repay B (token1)
          // Path: A → C → B
          paths.push({
            borrowPair: borrowPair.address,
            borrowToken0: true, // borrow token0 = A
            path: [
              borrowPair.token0, // A
              ethers.getAddress(c), // C (intermediate)
              borrowPair.token1, // B (repay)
            ],
            label: `${borrowPair.token0.slice(0, 8)}→${ethers.getAddress(c).slice(0, 8)}→${borrowPair.token1.slice(0, 8)}`,
          });

          // Direction 2: borrow B (token1 of borrowPair), repay A (token0)
          // Path: B → C → A
          paths.push({
            borrowPair: borrowPair.address,
            borrowToken0: false, // borrow token1 = B
            path: [
              borrowPair.token1, // B
              ethers.getAddress(c), // C (intermediate)
              borrowPair.token0, // A (repay)
            ],
            label: `${borrowPair.token1.slice(0, 8)}→${ethers.getAddress(c).slice(0, 8)}→${borrowPair.token0.slice(0, 8)}`,
          });
        }
      }
    }

    return paths;
  }

  /**
   * Simulate a single arbitrage path and return the expected profit.
   *
   * @param {string} borrowPair - Pair address to borrow from
   * @param {string[]} path - [borrowToken, midToken, repayToken]
   * @param {bigint} borrowAmount - Amount to borrow
   * @returns {{profitable: boolean, profit: bigint, repayAmount: bigint, finalAmount: bigint, details: string}}
   */
  simulatePath(borrowPair, path, borrowAmount) {
    const bpKey = borrowPair.toLowerCase();
    const borrowPairInfo = this.pairCache.get(bpKey);
    if (!borrowPairInfo) {
      return { profitable: false, profit: 0n, repayAmount: 0n, finalAmount: 0n, details: "borrow pair not in cache" };
    }

    const borrowToken = path[0].toLowerCase();
    const repayToken = path[path.length - 1].toLowerCase();

    // Step 1: Calculate trade along the path
    let currentAmount = borrowAmount;
    let currentToken = borrowToken;
    const steps = [];

    for (let i = 0; i < path.length - 1; i++) {
      const fromToken = path[i].toLowerCase();
      const toToken = path[i + 1].toLowerCase();

      // Find the pair for (fromToken, toToken)
      const [t0, t1] = sortTokens(fromToken, toToken);
      const pairInfo = [...this.pairCache.values()].find(
        (p) =>
          p.token0.toLowerCase() === t0.toLowerCase() &&
          p.token1.toLowerCase() === t1.toLowerCase()
      );

      if (!pairInfo) {
        return { profitable: false, profit: 0n, repayAmount: 0n, finalAmount: 0n, details: `no pair for ${fromToken.slice(0, 8)}→${toToken.slice(0, 8)}` };
      }

      const [reserveIn, reserveOut] = pairInfo.getReservesFor(fromToken);
      const amountOut = getAmountOut(currentAmount, reserveIn, reserveOut);
      if (amountOut <= 0n) {
        return { profitable: false, profit: 0n, repayAmount: 0n, finalAmount: 0n, details: `zero output at ${fromToken.slice(0, 8)}→${toToken.slice(0, 8)}` };
      }

      steps.push({ from: fromToken, to: toToken, amountIn: currentAmount, amountOut });
      currentAmount = amountOut;
      currentToken = toToken;
    }

    const finalAmount = currentAmount;

    // Step 2: Calculate repayment amount
    const [reserveBorrow, reserveRepay] = borrowPairInfo.getReservesFor(borrowToken);
    const repayAmount = getAmountIn(borrowAmount, reserveRepay, reserveBorrow);

    if (repayAmount <= 0n) {
      return { profitable: false, profit: 0n, repayAmount: 0n, finalAmount, details: "cannot calculate repayment" };
    }

    // Step 3: Profit = final amount in repay token - repay amount
    if (finalAmount <= repayAmount) {
      const loss = repayAmount - finalAmount;
      return { profitable: false, profit: 0n, repayAmount, finalAmount, details: `loss of ${loss}` };
    }

    const profit = finalAmount - repayAmount;
    return { profitable: true, profit, repayAmount, finalAmount, details: "profitable", steps };
  }

  /**
   * Scan all triangular paths for profitable opportunities.
   *
   * @param {bigint} borrowAmount - Amount to borrow in each simulation
   * @param {bigint} minProfit - Minimum profit threshold
   * @returns {Array<{path: object, profit: bigint, finalAmount: bigint, repayAmount: bigint}>}
   */
  scan(borrowAmount, minProfit) {
    const allPaths = this.generatePaths();
    logger.debug(`Generated ${allPaths.length} triangular paths to evaluate`);

    const opportunities = [];

    for (const candidate of allPaths) {
      const result = this.simulatePath(candidate.borrowPair, candidate.path, borrowAmount);

      if (result.profitable && result.profit >= minProfit) {
        opportunities.push({
          borrowPair: candidate.borrowPair,
          borrowToken0: candidate.borrowToken0,
          path: candidate.path,
          label: candidate.label,
          profit: result.profit,
          finalAmount: result.finalAmount,
          repayAmount: result.repayAmount,
          steps: result.steps,
        });
      }
    }

    // Sort by profit descending
    opportunities.sort((a, b) => (b.profit > a.profit ? 1 : b.profit < a.profit ? -1 : 0));
    return opportunities;
  }
}

// ============================================================================
// EXECUTOR
// ============================================================================

class ArbitrageExecutor {
  /**
   * @param {ethers.Wallet} wallet - Signer (must be owner of FlashArbitrage)
   * @param {string} flashArbitrageAddress - FlashArbitrage contract address
   */
  constructor(wallet, flashArbitrageAddress) {
    this.wallet = wallet;
    this.contract = new ethers.Contract(
      flashArbitrageAddress,
      FLASH_ARBITRAGE_ABI,
      wallet
    );
  }

  /**
   * Execute arbitrage on-chain.
   *
   * @param {object} opportunity - From ArbitrageScanner.scan()
   * @param {bigint} borrowAmount - Amount to borrow
   * @param {bigint} gasPriceBuffer - Gas price multiplier
   * @param {number} gasLimit - Gas limit
   * @returns {Promise<ethers.TransactionReceipt|null>}
   */
  async execute(opportunity, borrowAmount, gasPriceBuffer, gasLimit) {
    const deadline = Math.floor(Date.now() / 1000) + 120; // 2 minutes

    logger.info(`EXECUTING: ${opportunity.label} — profit: ${ethers.formatEther(opportunity.profit)} ETH-equivalent`);

    try {
      const feeData = await this.wallet.provider.getFeeData();
      let txOpts = { gasLimit };

      if (feeData.maxPriorityFeePerGas && feeData.maxFeePerGas) {
        txOpts.maxPriorityFeePerGas =
          (feeData.maxPriorityFeePerGas * BigInt(Math.floor(gasPriceBuffer * 100))) / 100n;
        txOpts.maxFeePerGas =
          (feeData.maxFeePerGas * BigInt(Math.floor(gasPriceBuffer * 100))) / 100n;
      } else if (feeData.gasPrice) {
        txOpts.gasPrice =
          (feeData.gasPrice * BigInt(Math.floor(gasPriceBuffer * 100))) / 100n;
      }

      logger.debug("Tx options:", JSON.stringify(txOpts, (_, v) => (typeof v === "bigint" ? v.toString() : v), 2));

      const tx = await this.contract.executeArbitrage(
        opportunity.borrowPair,
        opportunity.borrowToken0,
        borrowAmount,
        opportunity.path,
        opportunity.profit, // minProfit = calculated profit (conservative)
        deadline,
        txOpts
      );

      logger.info(`TX sent: ${tx.hash}`);
      logger.info(`Explorer: https://sepolia.etherscan.io/tx/${tx.hash}`);

      const receipt = await tx.wait(1);
      logger.info(`TX confirmed in block ${receipt.blockNumber}, gas used: ${receipt.gasUsed.toString()}`);

      // Parse events
      for (const log of receipt.logs) {
        try {
          const parsed = this.contract.interface.parseLog({
            topics: [...log.topics],
            data: log.data,
          });
          if (parsed && parsed.name === "ArbitrageExecuted") {
            logger.info(`  Profit: ${ethers.formatEther(parsed.args.profit)}`);
          }
        } catch {
          // log is from another contract, ignore
        }
      }

      return receipt;
    } catch (err) {
      logger.error(`Execution failed: ${err.message}`);
      // Check for common revert reasons
      if (err.message.includes("INSUFFICIENT_PROFIT")) {
        logger.warn("  → Profit slipped below threshold (sandwich/front-run?)");
      } else if (err.message.includes("EXPIRED")) {
        logger.warn("  → Transaction expired");
      } else if (err.message.includes("LOCKED")) {
        logger.warn("  → Contract is locked (reentrancy guard)");
      } else if (err.message.includes("INSUFFICIENT_LIQUIDITY")) {
        logger.warn("  → Not enough liquidity in one of the pairs");
      }
      return null;
    }
  }
}

// ============================================================================
// MAIN ENTRY
// ============================================================================

async function main() {
  logger.info("╔══════════════════════════════════════════╗");
  logger.info("║   Flash Arbitrage Bot — Uniswap V2      ║");
  logger.info("╚══════════════════════════════════════════╝");
  logger.info(`RPC:        ${CONFIG.rpcUrl}`);
  logger.info(`Factory:    ${CONFIG.factoryAddress}`);
  logger.info(`WETH:       ${CONFIG.wethAddress}`);
  logger.info(`Arbitrage:  ${CONFIG.flashArbitrageAddress}`);
  logger.info(`Poll:       ${CONFIG.pollIntervalMs}ms`);
  logger.info(`Min profit: ${ethers.formatEther(CONFIG.minProfitWei)} ETH`);
  logger.info(`Borrow:     ${ethers.formatEther(CONFIG.borrowAmount)} ETH`);

  // ---- Connect ----
  const provider = new ethers.JsonRpcProvider(CONFIG.rpcUrl);
  const wallet = ethers.Wallet.fromPhrase(CONFIG.mnemonic).connect(provider);
  logger.info(`Bot wallet: ${wallet.address}`);

  // Verify ownership
  const flashContract = new ethers.Contract(
    CONFIG.flashArbitrageAddress,
    FLASH_ARBITRAGE_ABI,
    provider
  );
  const owner = await flashContract.owner();
  if (owner.toLowerCase() !== wallet.address.toLowerCase()) {
    throw new Error(
      `Bot wallet ${wallet.address} is NOT the owner of FlashArbitrage (owner: ${owner}). ` +
      `Only the owner can call executeArbitrage.`
    );
  }
  logger.info("Ownership verified ✓");

  // ---- Parse monitored tokens ----
  let monitoredTokens = [];
  if (CONFIG.monitoredTokensRaw.trim()) {
    monitoredTokens = CONFIG.monitoredTokensRaw.split(",").map((t) => ethers.getAddress(t.trim()));
  }

  if (monitoredTokens.length < 3) {
    throw new Error(
      `At least 3 monitored tokens required for triangular arbitrage. ` +
      `Set MONITORED_TOKENS in bot/.env. Got: ${monitoredTokens.length}`
    );
  }

  // Load token symbols for display
  const tokenSymbols = new Map();
  for (const t of monitoredTokens) {
    try {
      const tokenContract = new ethers.Contract(t, ERC20_ABI, provider);
      const symbol = await tokenContract.symbol();
      tokenSymbols.set(t.toLowerCase(), symbol);
    } catch {
      tokenSymbols.set(t.toLowerCase(), t.slice(0, 8) + "...");
    }
  }
  logger.info(
    `Monitoring: ${monitoredTokens.map((t) => tokenSymbols.get(t.toLowerCase())).join(", ")}`
  );

  // ---- Initialize scanner ----
  const factory = new ethers.Contract(CONFIG.factoryAddress, FACTORY_ABI, provider);
  const pairCache = new Map(); // pairAddressLower -> PairInfo
  const scanner = new ArbitrageScanner(factory, CONFIG.wethAddress, monitoredTokens, pairCache);
  const executor = new ArbitrageExecutor(wallet, CONFIG.flashArbitrageAddress);

  // ---- Discover pairs ----
  logger.info("Discovering pairs...");
  await scanner.discoverPairs();

  if (pairCache.size < 3) {
    throw new Error(
      `Only ${pairCache.size} pairs found — need at least 3 for triangular arbitrage. ` +
      `Make sure the monitored tokens have liquidity pools with each other on Uniswap V2.`
    );
  }

  // ---- Check for --once flag ----
  const runOnce = process.argv.includes("--once");

  // ---- Main loop ----
  let running = true;
  let scanCount = 0;

  async function scanAndExecute() {
    scanCount++;
    const startTime = performance.now();

    try {
      // Refresh reserves
      await scanner.refreshReserves();

      // Scan for opportunities
      const opportunities = scanner.scan(CONFIG.borrowAmount, CONFIG.minProfitWei);

      const elapsed = (performance.now() - startTime).toFixed(1);

      if (opportunities.length === 0) {
        logger.debug(`[#${scanCount}] No profitable paths found (${elapsed}ms)`);
      } else {
        logger.info(
          `[#${scanCount}] Found ${opportunities.length} profitable path(s) (${elapsed}ms):`
        );
        for (const opp of opportunities) {
          logger.info(
            `  • ${opp.label} — profit: ${ethers.formatEther(opp.profit)} (${opp.profit.toString()} wei)`
          );
          logger.debug(`    borrowPair: ${opp.borrowPair}`);
          logger.debug(`    path: ${opp.path.join(" → ")}`);
          logger.debug(`    finalAmount: ${opp.finalAmount}, repayAmount: ${opp.repayAmount}`);
        }

        // Execute the most profitable one (unless --once dry run)
        if (!runOnce) {
          const best = opportunities[0];
          logger.info(`Executing best: ${best.label} (profit: ${ethers.formatEther(best.profit)})`);
          await executor.execute(best, CONFIG.borrowAmount, CONFIG.gasPriceBuffer, CONFIG.gasLimit);
        }
      }
    } catch (err) {
      logger.error(`Scan error: ${err.message}`);
    }
  }

  // Run first scan immediately
  await scanAndExecute();

  if (runOnce) {
    logger.info("--once mode: exiting after single scan");
    return;
  }

  // Schedule recurring scans
  logger.info(`Polling every ${CONFIG.pollIntervalMs}ms (Ctrl+C to stop)`);

  const interval = setInterval(async () => {
    if (!running) return;
    await scanAndExecute();
  }, CONFIG.pollIntervalMs);

  // Graceful shutdown
  const shutdown = () => {
    logger.info("Shutting down...");
    running = false;
    clearInterval(interval);
    process.exit(0);
  };

  process.on("SIGINT", shutdown);
  process.on("SIGTERM", shutdown);
}

// ============================================================================
// START
// ============================================================================

main().catch((err) => {
  logger.error(`Fatal: ${err.message}`);
  process.exit(1);
});
