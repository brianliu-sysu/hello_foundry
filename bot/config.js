import { config } from "dotenv";
import { resolve } from "path";
import { fileURLToPath } from "url";

// Load .env from bot/ directory
const __dirname = fileURLToPath(new URL(".", import.meta.url));
config({ path: resolve(__dirname, ".env") });

const CONFIG = {
  // RPC
  rpcUrl: process.env.RPC_URL || "http://127.0.0.1:8545",

  // Contract addresses
  flashArbitrageAddress: process.env.FLASH_ARBITRAGE_ADDRESS || "",
  factoryAddress: process.env.FACTORY_ADDRESS || "",
  wethAddress: process.env.WETH_ADDRESS || "",

  // Bot wallet — mnemonic phrase, derives first account at m/44'/60'/0'/0/0
  mnemonic: process.env.MNEMONIC || "",

  // Polling
  pollIntervalMs: parseInt(process.env.POLL_INTERVAL_MS || "2000", 10),

  // Profit threshold (in wei of profit token — typically WETH or stable)
  minProfitWei: BigInt(process.env.MIN_PROFIT_USD || "1000000000000000"), // 0.001 ETH

  // Gas settings
  gasPriceBuffer: parseFloat(process.env.GAS_PRICE_BUFFER || "1.2"),
  gasLimit: parseInt(process.env.GAS_LIMIT || "500000", 10),

  // Monitored tokens (parsed at startup)
  monitoredTokensRaw: process.env.MONITORED_TOKENS || "",

  // Borrow amount per attempt
  borrowAmount: BigInt(process.env.BORROW_AMOUNT || "100000000000000000"), // 0.1 ETH

  // Log level
  logLevel: process.env.LOG_LEVEL || "info",
};

// Validate required config
const REQUIRED = [
  "flashArbitrageAddress",
  "factoryAddress",
  "wethAddress",
  "mnemonic",
];
for (const key of REQUIRED) {
  if (!CONFIG[key]) {
    throw new Error(`Missing required config: ${key}. Set it in bot/.env`);
  }
}

export default CONFIG;
