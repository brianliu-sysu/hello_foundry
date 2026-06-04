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
];

// ────────────────────────────────────
// Auto-generated deploy addresses
// ────────────────────────────────────
import { CONTRACTS } from "./deploy-generated.js";

export const TOKENBANK_DEPLOYED   = fromDeploy("TokenBank");
export const BRIANICOTOKEN_DEPLOYED = fromDeploy("BrianICOToken");
export const NFTMARKET_DEPLOYED   = fromDeploy("NFTMarket");
export const BRIANFT_DEPLOYED    = fromDeploy("BrianNFT");

function fromDeploy(name) {
  const out = {};
  for (const chainId of Object.keys(CONTRACTS)) {
    out[chainId] = CONTRACTS[chainId][name] || "";
  }
  return out;
}

// ────────────────────────────────────
// Utilities
// ────────────────────────────────────
export function shortenHash(hash) {
  return hash.slice(0, 6) + "…" + hash.slice(-4);
}

export function explorerUrl(receipt) {
  const chainId = Number(receipt.chainId || 31337);
  if (chainId === 11155111) return `https://sepolia.etherscan.io/tx/${receipt.hash}`;
  return "#";
}
