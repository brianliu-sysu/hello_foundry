import { useState, useCallback } from "react";
import { isAddress, parseUnits, formatUnits } from "ethers";
import { useNFTMarket } from "../hooks/useNFTMarket";
import { NFTMARKET_DEPLOYED, BRIANFT_DEPLOYED } from "../utils/contract";
import TxStatus from "../components/TxStatus";

const DEFAULT_NETWORK = "31337";

export default function NFTMarketView({ signer, account }) {
  const [marketAddr,   setMarketAddr]   = useState(NFTMARKET_DEPLOYED[DEFAULT_NETWORK] || "");
  const [nftAddr,      setNftAddr]      = useState(BRIANFT_DEPLOYED[DEFAULT_NETWORK] || "");
  const [tokenId,      setTokenId]      = useState("");
  const [network,      setNetwork]      = useState(DEFAULT_NETWORK);
  const [listingInfo,  setListingInfo]  = useState(null);
  const [bitInfo,      setBITInfo]      = useState(null);
  const [infoError,    setInfoError]    = useState(null);
  const [loading,      setLoading]      = useState(false);

  const { txStatus, txPending, clearTxStatus, list, buy, cancel, getListingInfo, getBITInfo } = useNFTMarket(signer, marketAddr);

  const onNetwork = useCallback((key) => {
    setNetwork(key);
    setMarketAddr(NFTMARKET_DEPLOYED[key] || "");
    setNftAddr(BRIANFT_DEPLOYED[key] || "");
    clearTxStatus();
  }, [clearTxStatus]);

  const refresh = useCallback(async () => {
    if (!nftAddr || !isAddress(nftAddr)) { setInfoError("Invalid NFT address"); return; }
    if (tokenId === "" || isNaN(Number(tokenId)) || Number(tokenId) < 0) { setInfoError("Invalid Token ID"); return; }
    if (!account) { setInfoError("Please connect MetaMask first."); return; }
    setInfoError(null); setLoading(true);
    try {
      const info = await getListingInfo(nftAddr, Number(tokenId), account);
      setListingInfo(info);
      try { setBITInfo(await getBITInfo(info.paymentToken, account)); } catch { setBITInfo(null); }
    } catch (e) {
      setInfoError(e.message || "Failed to read listing.");
      setListingInfo(null); setBITInfo(null);
    } finally { setLoading(false); }
  }, [nftAddr, tokenId, account, getListingInfo, getBITInfo]);

  const mkAction = (fn) => async (...args) => { try { await fn(...args); await refresh(); } catch { /* in txStatus */ } };

  const validNFT = isAddress(nftAddr);
  const validToken = tokenId !== "" && !isNaN(Number(tokenId)) && Number(tokenId) >= 0 && Number.isInteger(Number(tokenId));
  const canLoad = validNFT && validToken && account && !loading;

  const { active, seller, nftOwner, price, nftName, nftSymbol, nftBalance, paymentToken } = listingInfo || {};
  const isSeller = account && seller && account.toLowerCase() === seller.toLowerCase();

  const [listPrice, setListPrice] = useState("");

  return (
    <>
      {/* ── Market Config ── */}
      <div className="card">
        <div className="card-header">📄 NFTMarket Contract</div>
        <div className="network-select">
          {["31337","11155111"].map(k => (
            <span key={k} className={`chip ${network === k ? "active" : ""}`} onClick={() => onNetwork(k)}>{k === "31337" ? "Anvil Local" : "Sepolia"}</span>
          ))}
        </div>
        <div className="form-group">
          <label className="form-label">NFTMarket Address</label>
          <input className="input" value={marketAddr} onChange={e => { setMarketAddr(e.target.value); clearTxStatus(); }} placeholder="0x…" spellCheck={false} />
        </div>
      </div>

      {/* ── Listing Info ── */}
      <div className="card">
        <div className="card-header">🖼️ NFT Listing</div>
        <div className="form-group">
          <label className="form-label">NFT Contract Address</label>
          <input className="input" value={nftAddr} onChange={e => { setNftAddr(e.target.value); setListingInfo(null); setBITInfo(null); setInfoError(null); }} placeholder="0x… ERC721" spellCheck={false} />
        </div>
        <div className="form-group">
          <label className="form-label">Token ID</label>
          <div className="input-row">
            <input className="input" value={tokenId} onChange={e => { setTokenId(e.target.value); setListingInfo(null); setBITInfo(null); setInfoError(null); }} placeholder="0" spellCheck={false} />
            <button className="btn btn-primary btn-sm" disabled={!canLoad} onClick={refresh}>{loading ? "…" : "🔍 Load"}</button>
          </div>
        </div>
        {infoError && <div style={{ color: "#fca5a5", fontSize: "0.8rem", marginBottom: "0.5rem" }}>❌ {infoError}</div>}
        {listingInfo && (
          <div style={{ marginTop: "0.75rem" }}>
            <InfoRow label="NFT" value={`${nftName||"???"} (${nftSymbol||"???"})`} />
            <InfoRow label="Token ID" value={String(tokenId)} />
            <InfoRow label="Owner" value={nftOwner||"???"} mono />
            <InfoRow label="Your NFT Count" value={String(nftBalance??"…")} />
            <hr className="divider" />
            <InfoRow label="Status" value={active ? "🟢 Listed" : "🔴 Not Listed"} highlight={active} />
            {active && <>
              <InfoRow label="Seller" value={seller} mono />
              <InfoRow label="Price" value={bitInfo ? `${formatUnits(price, bitInfo.decimals)} ${bitInfo.symbol}` : String(price)} mono highlight />
              {isSeller && <div style={{ color: "#fcd34d", fontSize: "0.8rem", marginTop: "0.5rem" }}>👤 You are the seller</div>}
            </>}
            {!active && nftOwner && nftOwner.toLowerCase() === account?.toLowerCase() && <div style={{ color: "#6ee7b7", fontSize: "0.8rem", marginTop: "0.5rem" }}>✅ You own this NFT — ready to list</div>}
            <hr className="divider" />
            <InfoRow label="Payment Token" value={paymentToken||"…"} mono />
            <InfoRow label="Your BIT Balance" value={bitInfo ? `${formatUnits(bitInfo.balance, bitInfo.decimals)} ${bitInfo.symbol}` : "…"} highlight />
            <InfoRow label="BIT Allowance" value={bitInfo ? `${formatUnits(bitInfo.allowance, bitInfo.decimals)} ${bitInfo.symbol}` : "…"} />
          </div>
        )}
      </div>

      {/* ── List ── */}
      <div className="card">
        <div className="card-header">📋 List NFT for Sale</div>
        <p style={{ color: "#94a3b8", fontSize: "0.8rem", marginBottom: "0.75rem" }}>Approve market to transfer your NFT, then list it.</p>
        <div className="form-group">
          <label className="form-label">Price ({bitInfo?.symbol || "BIT"})</label>
          <input className="input" value={listPrice} onChange={e => setListPrice(e.target.value)} placeholder="0.0" spellCheck={false} />
        </div>
        {active && <div style={{ color: "#fbbf24", fontSize: "0.75rem", marginBottom: "0.5rem" }}>⚠ Already listed. Cancel first to re-list.</div>}
        <button className="btn btn-primary" disabled={!nftAddr||!isAddress(nftAddr)||!validToken||!listPrice||isNaN(listPrice)||Number(listPrice)<=0||!bitInfo?.decimals||txPending||active} onClick={() => { if (bitInfo?.decimals) { mkAction(list)(nftAddr, Number(tokenId), parseUnits(listPrice, bitInfo.decimals)); setListPrice(""); } }}>{txPending ? "⏳ Processing…" : "📋 Approve & List"}</button>
        <TxStatus status={txStatus} />
      </div>

      {/* ── Buy ── */}
      <div className="card">
        <div className="card-header">🛒 Buy NFT</div>
        <p style={{ color: "#94a3b8", fontSize: "0.8rem", marginBottom: "0.75rem" }}>Approve BIT spending to market, then buy.</p>
        {!active && listingInfo && <div style={{ color: "#94a3b8", fontSize: "0.75rem", marginBottom: "0.5rem" }}>⚠ Not listed.</div>}
        {active && isSeller && <div style={{ color: "#fbbf24", fontSize: "0.75rem", marginBottom: "0.5rem" }}>⚠ You are the seller.</div>}
        {active && !isSeller && bitInfo && bitInfo.balance < price && <div style={{ color: "#fca5a5", fontSize: "0.75rem", marginBottom: "0.5rem" }}>❌ Insufficient BIT balance.</div>}
        <button className="btn btn-primary" disabled={!active||isSeller||txPending} onClick={() => { mkAction(buy)(nftAddr, Number(tokenId), price, paymentToken); }}>{txPending ? "⏳ Processing…" : "🛒 Approve & Buy"}</button>
        <TxStatus status={txStatus} />
      </div>

      {/* ── Cancel ── */}
      <div className="card">
        <div className="card-header">❌ Cancel Listing</div>
        <p style={{ color: "#94a3b8", fontSize: "0.8rem", marginBottom: "0.75rem" }}>Cancel your listing and get your NFT back.</p>
        {!active && listingInfo && <div style={{ color: "#94a3b8", fontSize: "0.75rem", marginBottom: "0.5rem" }}>⚠ Not listed.</div>}
        {active && !isSeller && <div style={{ color: "#fbbf24", fontSize: "0.75rem", marginBottom: "0.5rem" }}>⚠ Only the seller can cancel.</div>}
        <button className="btn btn-danger" disabled={!active||!isSeller||txPending} onClick={() => { mkAction(cancel)(nftAddr, Number(tokenId)); }}>{txPending ? "⏳ Processing…" : "❌ Cancel Listing"}</button>
        <TxStatus status={txStatus} />
      </div>
    </>
  );
}

function InfoRow({ label, value, mono, highlight }) {
  return (
    <div className="info-row">
      <span className="info-label">{label}</span>
      <span className="info-value" style={{ fontFamily: mono||highlight ? "'SF Mono','Fira Code',monospace" : undefined, color: highlight ? "#fcd34d" : undefined, fontWeight: highlight ? 600 : undefined }}>{value}</span>
    </div>
  );
}
