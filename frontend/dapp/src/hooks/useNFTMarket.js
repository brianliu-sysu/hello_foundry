import { useState, useEffect, useCallback } from "react";
import { Contract, isAddress } from "ethers";
import { NFTMARKET_ABI, ERC721_ABI, ERC20_ABI, BRIANFT_EXTRA_ABI, ipfsToHttp, shortenHash, explorerUrl } from "../utils/contract";

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

export function useNFTMarket(signer, marketAddress) {
  const [marketContract,  setMarketContract]  = useState(null);
  const [marketAddressOk, setMarketAddressOk] = useState(false);
  const [txStatus,  setTxStatus]  = useState(null);
  const [txPending, setTxPending] = useState(false);

  useEffect(() => {
    if (signer && marketAddress && isAddress(marketAddress)) {
      setMarketContract(new Contract(marketAddress, NFTMARKET_ABI, signer));
      setMarketAddressOk(true);
    } else { setMarketContract(null); setMarketAddressOk(false); }
  }, [signer, marketAddress]);

  const sendTx = useCallback(async (txFn, onConfirmed) => {
    setTxPending(true);
    setTxStatus({ type: "pending", message: "Waiting for wallet confirmation…" });
    try {
      const tx = await txFn();
      setTxStatus({ type: "pending", message: `Submitted: ${shortenHash(tx.hash)} — waiting…`, hash: tx.hash });
      const receipt = await tx.wait();
      setTxStatus({ type: "success", message: `Confirmed in block ${receipt.blockNumber}.`, hash: receipt.hash, block: receipt.blockNumber, explorerUrl: explorerUrl(receipt) });
      if (onConfirmed) await onConfirmed();
    } catch (err) {
      const msg = err.reason || err.message || String(err);
      setTxStatus({ type: "error", message: msg });
      throw err;
    } finally { setTxPending(false); }
  }, []);

  const clearTxStatus = useCallback(() => setTxStatus(null), []);

  const list = useCallback(async (nftAddr, tokenId, price) => {
    if (!marketContract) { setTxStatus({ type: "error", message: "Invalid NFTMarket address." }); return; }
    try {
      const nft = new Contract(nftAddr, ERC721_ABI, signer);
      await sendTx(() => nft.approve(marketContract.target, tokenId));
      await sendTx(() => marketContract.list(nftAddr, tokenId, price));
    } catch { /* surfaced */ }
  }, [marketContract, signer, sendTx]);

  const buy = useCallback(async (nftAddr, tokenId, price, bitAddr) => {
    if (!marketContract) { setTxStatus({ type: "error", message: "Invalid NFTMarket address." }); return; }
    try {
      const bit = new Contract(bitAddr, ERC20_ABI, signer);
      await sendTx(() => bit.approve(marketContract.target, price));
      await sendTx(() => marketContract.buy(nftAddr, tokenId));
    } catch { /* surfaced */ }
  }, [marketContract, signer, sendTx]);

  const cancel = useCallback(async (nftAddr, tokenId) => {
    if (!marketContract) { setTxStatus({ type: "error", message: "Invalid NFTMarket address." }); return; }
    try { await sendTx(() => marketContract.cancel(nftAddr, tokenId)); } catch { /* surfaced */ }
  }, [marketContract, sendTx]);

  // ── safeMint（BrianNFT） ──
  const safeMint = useCallback(async (nftAddr, to, uri) => {
    if (!isAddress(nftAddr)) { setTxStatus({ type: "error", message: "Invalid NFT address." }); return; }
    try {
      const nft = new Contract(nftAddr, [...ERC721_ABI, ...BRIANFT_EXTRA_ABI], signer);
      await sendTx(() => nft.safeMint(to, uri));
    } catch { /* surfaced */ }
  }, [signer, sendTx]);

  // ── loadMyNFTs（枚举当前用户持有的 NFT + IPFS 元数据） ──
  const loadMyNFTs = useCallback(async (nftAddr, userAddr) => {
    if (!isAddress(nftAddr)) throw new Error("Invalid NFT address");
    if (!signer) throw new Error("Wallet not connected");
    const nft = new Contract(nftAddr, ERC721_ABI, signer.provider);
    const balance = Number(await nft.balanceOf(userAddr).catch(() => 0n));
    const nfts = [];
    for (let i = 0; i < balance; i++) {
      try {
        const tokenId = await nft.tokenOfOwnerByIndex(userAddr, i);
        const uri = await nft.tokenURI(tokenId).catch(() => "");
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
    return nfts;
  }, [signer]);

  const getListingInfo = useCallback(async (nftAddr, tokenId, userAddr) => {
    if (!isAddress(nftAddr)) throw new Error("Invalid NFT address");
    if (!signer) throw new Error("Wallet not connected");
    if (!marketContract) throw new Error("Market contract not ready");
    const nft = new Contract(nftAddr, ERC721_ABI, signer.provider);
    const mkt = new Contract(marketContract.target, NFTMARKET_ABI, signer.provider);
    const [listing, nftOwner, nftName, nftSymbol, nftBalance, paymentTokenAddr, nftTokenURI] = await Promise.all([
      mkt.getListing(nftAddr, tokenId),
      nft.ownerOf(tokenId).catch(() => null),
      nft.name().catch(() => "???"),
      nft.symbol().catch(() => "???"),
      nft.balanceOf(userAddr).catch(() => 0n),
      mkt.paymentToken(),
      nft.tokenURI(tokenId).catch(() => ""),
    ]);
    const nftMeta = await fetchMetadata(nftTokenURI);
    return {
      seller: listing.seller, price: listing.price, active: listing.active,
      nftOwner, nftName, nftSymbol, nftBalance: Number(nftBalance),
      paymentToken: paymentTokenAddr, nftTokenURI,
      nftImage: nftMeta?.image || "",
      nftDesc: nftMeta?.description || "",
      nftAttrs: nftMeta?.attributes || [],
    };
  }, [marketContract, signer]);

  const getBITInfo = useCallback(async (bitAddr, userAddr) => {
    if (!isAddress(bitAddr)) throw new Error("Invalid BIT address");
    if (!signer) throw new Error("Wallet not connected");
    const bit = new Contract(bitAddr, ERC20_ABI, signer.provider);
    const [symbol, decimals, balance, allowanceRaw] = await Promise.all([
      bit.symbol().catch(() => "???"), bit.decimals().catch(() => 18),
      bit.balanceOf(userAddr).catch(() => 0n),
      marketContract ? bit.allowance(userAddr, marketContract.target).catch(() => 0n) : Promise.resolve(0n),
    ]);
    return { symbol, decimals: Number(decimals), balance, allowance: allowanceRaw };
  }, [marketContract, signer]);

  return {
    marketContract, marketAddressOk,
    txStatus, txPending, clearTxStatus,
    list, buy, cancel, safeMint,
    getListingInfo, getBITInfo, loadMyNFTs,
  };
}
