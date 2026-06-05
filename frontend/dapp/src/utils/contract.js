// ============================================================
// DApp unified — all contract ABIs + auto-generated addresses
// ============================================================

// ────────────────────────────────────
// TokenBank ABI
// ────────────────────────────────────
export const TOKENBANK_ABI = [
  { type: "function", name: "deposit", inputs: [
    { name: "token", type: "address" }, { name: "amount", type: "uint256" },
  ], outputs: [], stateMutability: "nonpayable" },
  { type: "function", name: "deposits", inputs: [
    { name: "", type: "address" }, { name: "", type: "address" },
  ], outputs: [{ name: "", type: "uint256" }], stateMutability: "view" },
  { type: "function", name: "onTransferReceived", inputs: [
    { name: "", type: "address" }, { name: "from", type: "address" },
    { name: "value", type: "uint256" }, { name: "", type: "bytes" },
  ], outputs: [{ name: "", type: "bytes4" }], stateMutability: "nonpayable" },
  { type: "function", name: "permitDeposit", inputs: [
    { name: "owner", type: "address" }, { name: "token", type: "address" },
    { name: "amount", type: "uint256" }, { name: "deadline", type: "uint256" },
    { name: "v", type: "uint8" }, { name: "r", type: "bytes32" }, { name: "s", type: "bytes32" },
  ], outputs: [], stateMutability: "nonpayable" },
  { type: "function", name: "depositPermit2", inputs: [
    { name: "owner", type: "address" }, { name: "token", type: "address" },
    { name: "amount", type: "uint256" }, { name: "nonce", type: "uint256" },
    { name: "deadline", type: "uint256" }, { name: "signature", type: "bytes" },
  ], outputs: [], stateMutability: "nonpayable" },
  { type: "function", name: "withdraw", inputs: [
    { name: "token", type: "address" }, { name: "amount", type: "uint256" },
  ], outputs: [], stateMutability: "nonpayable" },
  { type: "event", name: "Deposited", inputs: [
    { name: "token", type: "address", indexed: true },
    { name: "from", type: "address", indexed: true },
    { name: "amount", type: "uint256", indexed: false },
  ], anonymous: false },
  { type: "event", name: "Withdrawn", inputs: [
    { name: "token", type: "address", indexed: true },
    { name: "to", type: "address", indexed: true },
    { name: "amount", type: "uint256", indexed: false },
  ], anonymous: false },
];

// ────────────────────────────────────
// NFTMarket ABI
// ────────────────────────────────────
export const NFTMARKET_ABI = [
  { type: "function", name: "list", inputs: [
    { name: "nft", type: "address" }, { name: "tokenId", type: "uint256" }, { name: "price", type: "uint256" },
  ], outputs: [], stateMutability: "nonpayable" },
  { type: "function", name: "buy", inputs: [
    { name: "nft", type: "address" }, { name: "tokenId", type: "uint256" },
  ], outputs: [], stateMutability: "nonpayable" },
  { type: "function", name: "cancel", inputs: [
    { name: "nft", type: "address" }, { name: "tokenId", type: "uint256" },
  ], outputs: [], stateMutability: "nonpayable" },
  { type: "function", name: "getListing", inputs: [
    { name: "nft", type: "address" }, { name: "tokenId", type: "uint256" },
  ], outputs: [
    { name: "seller", type: "address" }, { name: "price", type: "uint256" }, { name: "active", type: "bool" },
  ], stateMutability: "view" },
  { type: "function", name: "paymentToken", inputs: [], outputs: [{ name: "", type: "address" }], stateMutability: "view" },
  { type: "function", name: "feeBps", inputs: [], outputs: [{ name: "", type: "uint256" }], stateMutability: "view" },
  { type: "function", name: "feeRecipient", inputs: [], outputs: [{ name: "", type: "address" }], stateMutability: "view" },
  { type: "function", name: "owner", inputs: [], outputs: [{ name: "", type: "address" }], stateMutability: "view" },
  { type: "event", name: "Listed", inputs: [
    { name: "seller", type: "address", indexed: true }, { name: "nft", type: "address", indexed: true },
    { name: "tokenId", type: "uint256", indexed: true }, { name: "price", type: "uint256", indexed: false },
  ], anonymous: false },
  { type: "event", name: "Sold", inputs: [
    { name: "seller", type: "address", indexed: true }, { name: "buyer", type: "address", indexed: true },
    { name: "nft", type: "address", indexed: true }, { name: "tokenId", type: "uint256", indexed: false },
    { name: "price", type: "uint256", indexed: false }, { name: "fee", type: "uint256", indexed: false },
  ], anonymous: false },
  { type: "event", name: "Cancelled", inputs: [
    { name: "seller", type: "address", indexed: true }, { name: "nft", type: "address", indexed: true },
    { name: "tokenId", type: "uint256", indexed: true },
  ], anonymous: false },
];

// ────────────────────────────────────
// ERC20 ABI (unified: TokenBank + NFTMarket needs)
// ────────────────────────────────────
export const ERC20_ABI = [
  { type: "function", name: "approve", inputs: [
    { name: "spender", type: "address" }, { name: "value", type: "uint256" },
  ], outputs: [{ name: "", type: "bool" }], stateMutability: "nonpayable" },
  { type: "function", name: "allowance", inputs: [
    { name: "owner", type: "address" }, { name: "spender", type: "address" },
  ], outputs: [{ name: "", type: "uint256" }], stateMutability: "view" },
  { type: "function", name: "balanceOf", inputs: [
    { name: "account", type: "address" },
  ], outputs: [{ name: "", type: "uint256" }], stateMutability: "view" },
  { type: "function", name: "decimals", inputs: [], outputs: [{ name: "", type: "uint8" }], stateMutability: "view" },
  { type: "function", name: "symbol", inputs: [], outputs: [{ name: "", type: "string" }], stateMutability: "view" },
  // EIP-2612 permit
  { type: "function", name: "nonces", inputs: [
    { name: "owner", type: "address" },
  ], outputs: [{ name: "", type: "uint256" }], stateMutability: "view" },
  { type: "function", name: "permit", inputs: [
    { name: "owner", type: "address" }, { name: "spender", type: "address" },
    { name: "value", type: "uint256" }, { name: "deadline", type: "uint256" },
    { name: "v", type: "uint8" }, { name: "r", type: "bytes32" }, { name: "s", type: "bytes32" },
  ], outputs: [], stateMutability: "nonpayable" },
];

// ────────────────────────────────────
// ERC721 ABI
// ────────────────────────────────────
export const ERC721_ABI = [
  { type: "function", name: "approve", inputs: [
    { name: "to", type: "address" }, { name: "tokenId", type: "uint256" },
  ], outputs: [], stateMutability: "nonpayable" },
  { type: "function", name: "ownerOf", inputs: [
    { name: "tokenId", type: "uint256" },
  ], outputs: [{ name: "", type: "address" }], stateMutability: "view" },
  { type: "function", name: "balanceOf", inputs: [
    { name: "owner", type: "address" },
  ], outputs: [{ name: "", type: "uint256" }], stateMutability: "view" },
  { type: "function", name: "tokenURI", inputs: [
    { name: "tokenId", type: "uint256" },
  ], outputs: [{ name: "", type: "string" }], stateMutability: "view" },
  { type: "function", name: "name", inputs: [], outputs: [{ name: "", type: "string" }], stateMutability: "view" },
  { type: "function", name: "symbol", inputs: [], outputs: [{ name: "", type: "string" }], stateMutability: "view" },
  { type: "function", name: "getApproved", inputs: [
    { name: "tokenId", type: "uint256" },
  ], outputs: [{ name: "", type: "address" }], stateMutability: "view" },
  { type: "function", name: "tokenOfOwnerByIndex", inputs: [
    { name: "owner", type: "address" }, { name: "index", type: "uint256" },
  ], outputs: [{ name: "", type: "uint256" }], stateMutability: "view" },
];

// ────────────────────────────────────
// BrianNFT ABI（铸造 + Owner）
// ────────────────────────────────────
export const BRIANFT_EXTRA_ABI = [
  { type: "function", name: "safeMint", inputs: [
    { name: "to", type: "address" }, { name: "uri", type: "string" },
  ], outputs: [], stateMutability: "nonpayable" },
];

// ────────────────────────────────────
// MemeFactory ABI
// ────────────────────────────────────
export const MEMEFACTORY_ABI = [
  { type: "function", name: "createMeme", inputs: [
    { name: "name", type: "string" }, { name: "symbol", type: "string" }, { name: "totalSupply", type: "uint256" },
  ], outputs: [{ name: "", type: "address" }], stateMutability: "nonpayable" },
  { type: "function", name: "memeCount", inputs: [], outputs: [{ name: "", type: "uint256" }], stateMutability: "view" },
  { type: "function", name: "memeTokens", inputs: [{ name: "", type: "uint256" }], outputs: [{ name: "", type: "address" }], stateMutability: "view" },
  { type: "function", name: "getMemeTokens", inputs: [], outputs: [{ name: "", type: "address[]" }], stateMutability: "view" },
  { type: "function", name: "getMemeTokensPaginated", inputs: [
    { name: "offset", type: "uint256" }, { name: "limit", type: "uint256" },
  ], outputs: [{ name: "page", type: "address[]" }, { name: "total", type: "uint256" }], stateMutability: "view" },
  { type: "event", name: "MemeCreated", inputs: [
    { name: "name", type: "string", indexed: false }, { name: "symbol", type: "string", indexed: false },
    { name: "totalSupply", type: "uint256", indexed: false }, { name: "creator", type: "address", indexed: true },
    { name: "token", type: "address", indexed: true },
  ], anonymous: false },
];

// MemeToken 额外 ABI（Ownable + ERC20 读取函数）
export const MEMETOKEN_EXTRA_ABI = [
  { type: "function", name: "owner", inputs: [], outputs: [{ name: "", type: "address" }], stateMutability: "view" },
  { type: "function", name: "name", inputs: [], outputs: [{ name: "", type: "string" }], stateMutability: "view" },
  { type: "function", name: "totalSupply", inputs: [], outputs: [{ name: "", type: "uint256" }], stateMutability: "view" },
];

// ────────────────────────────────────
// Auto-generated deploy addresses (fallback)
// ────────────────────────────────────
import { CONTRACTS } from "./deploy-generated.js";
import {
  CONTRACT_ADDRESSES,
  PERMIT2_ADDRESS as _PERMIT2_ADDRESS,
  EXPLORER_URLS,
} from "../config.js";

export const PERMIT2_ADDRESS = _PERMIT2_ADDRESS;

/// 合并手动配置与自动生成：手动值优先，空字符串则 fallback 到自动生成
function mergeAddress(name) {
  const manual = (CONTRACT_ADDRESSES[name] || {});
  const out = {};
  // 收集所有 chainId
  const chainIds = new Set([
    ...Object.keys(CONTRACTS),
    ...Object.keys(manual),
  ]);
  for (const chainId of chainIds) {
    if (manual[chainId] && manual[chainId] !== "") {
      out[chainId] = manual[chainId];           // 手动地址优先
    } else {
      out[chainId] = (CONTRACTS[chainId]?.[name]) || "";
    }
  }
  return out;
}

export const TOKENBANK_DEPLOYED      = mergeAddress("TokenBank");
export const BRIANICOTOKEN_DEPLOYED   = mergeAddress("BrianICOToken");
export const NFTMARKET_DEPLOYED        = mergeAddress("NFTMarket");
export const BRIANFT_DEPLOYED          = mergeAddress("BrianNFT");
export const MEMEFACTORY_DEPLOYED      = mergeAddress("MemeFactory");

// ────────────────────────────────────
// Utilities
// ────────────────────────────────────
export function shortenHash(hash) {
  return hash.slice(0, 6) + "…" + hash.slice(-4);
}

export function explorerUrl(receipt) {
  const chainId = Number(receipt.chainId || 31337);
  const base = EXPLORER_URLS[String(chainId)];
  if (base) return `${base}/tx/${receipt.hash}`;
  return "#";
}

// 将 ipfs:// 转换为 HTTP 网关可访问的 URL
const IPFS_GATEWAYS = [
  "https://ipfs.io/ipfs/",
  "https://cloudflare-ipfs.com/ipfs/",
];
export function ipfsToHttp(uri, gatewayIndex = 0) {
  if (!uri) return "";
  if (uri.startsWith("ipfs://")) return IPFS_GATEWAYS[gatewayIndex || 0] + uri.slice(7);
  if (uri.startsWith("https://") || uri.startsWith("http://")) return uri;
  // CID-only 字符串
  if (uri.match(/^[a-zA-Z0-9]{46,}$/)) return IPFS_GATEWAYS[gatewayIndex || 0] + uri;
  return uri;
}
