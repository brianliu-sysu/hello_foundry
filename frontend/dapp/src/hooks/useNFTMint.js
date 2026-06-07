import { useState, useEffect, useCallback } from "react";
import { Contract, isAddress } from "ethers";
import { ERC721_ABI, BRIANFT_EXTRA_ABI, ipfsToHttp, shortenHash, explorerUrl } from "../utils/contract";

// 从 IPFS URI 拉取 NFT 元数据 JSON
async function fetchMetadata(uri) {
  if (!uri) return null;
  try {
    const url = ipfsToHttp(uri, 0);
    const res = await fetch(url);
    if (!res.ok) return null;
    const meta = await res.json();
    return {
      name: meta.name || "",
      description: meta.description || "",
      image: meta.image || "",
      attributes: meta.attributes || [],
    };
  } catch {
    return null;
  }
}

export function useNFTMint(signer, nftAddress) {
  const [nftContract, setNftContract] = useState(null);
  const [nftAddressOk, setNftAddressOk] = useState(false);
  const [txStatus, setTxStatus] = useState(null);
  const [txPending, setTxPending] = useState(false);

  // ── Supply stats ──
  const [maxSupply, setMaxSupply] = useState(null);       // 0 = unlimited
  const [totalMinted, setTotalMinted] = useState(null);
  const [nextTokenId, setNextTokenId] = useState(null);
  const [nftOwner, setNftOwner] = useState(null);
  const [nftName, setNftName] = useState("");
  const [nftSymbol, setNftSymbol] = useState("");
  const [statsLoading, setStatsLoading] = useState(false);

  // ── 用户持有的 NFT ──
  const [myNFTs, setMyNFTs] = useState(null);           // null = 未加载
  const [myNFTsLoading, setMyNFTsLoading] = useState(false);

  useEffect(() => {
    if (signer && nftAddress && isAddress(nftAddress)) {
      const c = new Contract(nftAddress, [...ERC721_ABI, ...BRIANFT_EXTRA_ABI], signer);
      setNftContract(c);
      setNftAddressOk(true);
    } else {
      setNftContract(null);
      setNftAddressOk(false);
    }
  }, [signer, nftAddress]);

  // ── 发送交易 ──
  const sendTx = useCallback(async (txFn) => {
    setTxPending(true);
    setTxStatus({ type: "pending", message: "Waiting for wallet confirmation…" });
    try {
      const tx = await txFn();
      setTxStatus({ type: "pending", message: `Submitted: ${shortenHash(tx.hash)} — waiting…`, hash: tx.hash });
      const receipt = await tx.wait();
      setTxStatus({ type: "success", message: `Confirmed in block ${receipt.blockNumber}.`, hash: receipt.hash, block: receipt.blockNumber, explorerUrl: explorerUrl(receipt) });
    } catch (err) {
      const msg = err.reason || err.message || String(err);
      setTxStatus({ type: "error", message: msg });
      throw err;
    } finally {
      setTxPending(false);
    }
  }, []);

  const clearTxStatus = useCallback(() => setTxStatus(null), []);

  // ── 加载合约数据 ──
  const refreshStats = useCallback(async () => {
    if (!nftContract) return;
    setStatsLoading(true);
    try {
      const [max, minted, next, owner, name, symbol] = await Promise.all([
        nftContract.maxSupply().catch(() => 0n),
        nftContract.totalMinted().catch(() => 0n),
        nftContract.nextTokenId().catch(() => 1n),
        nftContract.owner().catch(() => null),
        nftContract.name().catch(() => "???"),
        nftContract.symbol().catch(() => "???"),
      ]);
      setMaxSupply(max);
      setTotalMinted(minted);
      setNextTokenId(next);
      setNftOwner(owner);
      setNftName(name);
      setNftSymbol(symbol);
    } catch (err) {
      console.error("Failed to load NFT stats:", err);
    } finally {
      setStatsLoading(false);
    }
  }, [nftContract]);

  // 自动加载
  useEffect(() => {
    if (nftContract) refreshStats();
  }, [nftContract, refreshStats]);

  // ── 加载当前用户持有的 NFT（枚举 + IPFS 元数据） ──
  const loadMyNFTs = useCallback(async (userAddr) => {
    if (!nftContract || !userAddr) return;
    setMyNFTsLoading(true);
    try {
      const balance = Number(await nftContract.balanceOf(userAddr).catch(() => 0n));
      const nfts = [];
      for (let i = 0; i < balance; i++) {
        try {
          const tokenId = await nftContract.tokenOfOwnerByIndex(userAddr, i);
          const uri = await nftContract.tokenURI(tokenId).catch(() => "");
          const meta = await fetchMetadata(uri);
          nfts.push({
            tokenId: Number(tokenId),
            uri,
            image: meta?.image || "",
            name: meta?.name || "",
            description: meta?.description || "",
            attributes: meta?.attributes || [],
          });
        } catch { /* skip failed reads */ }
      }
      setMyNFTs(nfts);
    } catch (err) {
      console.error("Failed to load my NFTs:", err);
      setMyNFTs([]);
    } finally {
      setMyNFTsLoading(false);
    }
  }, [nftContract]);

  // ── 单个铸造 ──
  const safeMint = useCallback(async (to, uri) => {
    if (!nftContract) { setTxStatus({ type: "error", message: "Invalid NFT address." }); return; }
    await sendTx(() => nftContract.safeMint(to, uri));
    await refreshStats();
  }, [nftContract, sendTx, refreshStats]);

  // ── 批量铸造 ──
  const safeMintBatch = useCallback(async (recipients, uris) => {
    if (!nftContract) { setTxStatus({ type: "error", message: "Invalid NFT address." }); return; }
    await sendTx(() => nftContract.safeMintBatch(recipients, uris));
    await refreshStats();
  }, [nftContract, sendTx, refreshStats]);

  return {
    nftAddressOk,
    txStatus, txPending, clearTxStatus,
    // 统计数据
    maxSupply, totalMinted, nextTokenId,
    nftOwner, nftName, nftSymbol,
    statsLoading, refreshStats,
    // 铸造
    safeMint, safeMintBatch,
    // 用户 NFT
    myNFTs, myNFTsLoading, loadMyNFTs,
  };
}
