import { useState, useEffect, useCallback } from "react";
import { Contract, isAddress } from "ethers";
import { NFTMARKET_ABI, ERC721_ABI, ERC20_ABI, shortenHash, explorerUrl } from "../utils/contract";

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

  const getListingInfo = useCallback(async (nftAddr, tokenId, userAddr) => {
    if (!isAddress(nftAddr)) throw new Error("Invalid NFT address");
    if (!signer) throw new Error("Wallet not connected");
    if (!marketContract) throw new Error("Market contract not ready");
    const nft = new Contract(nftAddr, ERC721_ABI, signer.provider);
    const mkt = new Contract(marketContract.target, NFTMARKET_ABI, signer.provider);
    const [listing, nftOwner, nftName, nftSymbol, nftBalance, paymentTokenAddr] = await Promise.all([
      mkt.getListing(nftAddr, tokenId),
      nft.ownerOf(tokenId).catch(() => null),
      nft.name().catch(() => "???"),
      nft.symbol().catch(() => "???"),
      nft.balanceOf(userAddr).catch(() => 0n),
      mkt.paymentToken(),
    ]);
    return { seller: listing.seller, price: listing.price, active: listing.active, nftOwner, nftName, nftSymbol, nftBalance: Number(nftBalance), paymentToken: paymentTokenAddr };
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
    list, buy, cancel,
    getListingInfo, getBITInfo,
  };
}
