import { useState, useCallback, useEffect, useRef } from "react";
import { isAddress, parseUnits, formatUnits } from "ethers";
import { useNFTMarket } from "../hooks/useNFTMarket";
import { NFTMARKET_DEPLOYED, BRIANFT_DEPLOYED, ipfsToHttp } from "../utils/contract";
import { DEFAULT_NETWORK, NETWORK_LABELS } from "../config";
import TxStatus from "../components/TxStatus";
import AddressLabel from "../components/AddressLabel";

export default function NFTMarketView({ signer, account, chainId }) {
  const networkKey = chainId != null ? String(chainId) : DEFAULT_NETWORK;
  const networkLabel = NETWORK_LABELS[networkKey] || `Chain ${networkKey}`;

  const [marketAddr, setMarketAddr] = useState(NFTMARKET_DEPLOYED[networkKey] || "");
  const [nftAddr,    setNftAddr]    = useState(BRIANFT_DEPLOYED[networkKey] || "");

  const prevNetwork = useRef(networkKey);
  useEffect(() => {
    if (prevNetwork.current !== networkKey) {
      prevNetwork.current = networkKey;
      setMarketAddr(NFTMARKET_DEPLOYED[networkKey] || "");
      setNftAddr(BRIANFT_DEPLOYED[networkKey] || "");
      clearTxStatus();
    }
  }, [networkKey]); // eslint-disable-line react-hooks/exhaustive-deps

  const [tokenId,      setTokenId]      = useState("");
  const [listingInfo,  setListingInfo]  = useState(null);
  const [bitInfo,      setBITInfo]      = useState(null);
  const [loading,      setLoading]      = useState(false);

  const { txStatus, txPending, clearTxStatus, list, buy, cancel, getListingInfo, getBITInfo, loadMyNFTs } = useNFTMarket(signer, marketAddr);

  // 加载单个 NFT 信息（供 List/Buy/Cancel 使用）
  const refreshNft = useCallback(async (tid) => {
    const id = tid ?? tokenId;
    if (!nftAddr || !isAddress(nftAddr) || id === "" || isNaN(Number(id)) || Number(id) < 0 || !account) return;
    setLoading(true);
    try {
      const info = await getListingInfo(nftAddr, Number(id), account);
      setListingInfo(info);
      try { setBITInfo(await getBITInfo(info.paymentToken, account)); } catch { setBITInfo(null); }
    } catch {
      setListingInfo(null); setBITInfo(null);
    } finally { setLoading(false); }
  }, [nftAddr, tokenId, account, getListingInfo, getBITInfo]);

  // ── My NFTs state ──
  const [myNFTs, setMyNFTs] = useState(null);
  const [myNFTsLoading, setMyNFTsLoading] = useState(false);
  const hasAutoLoaded = useRef(false);

  const loadOwnedNFTs = useCallback(async () => {
    if (!account || !nftAddr || !isAddress(nftAddr)) return;
    setMyNFTsLoading(true);
    try { setMyNFTs(await loadMyNFTs(nftAddr, account)); }
    catch { setMyNFTs([]); }
    finally { setMyNFTsLoading(false); }
  }, [nftAddr, account, loadMyNFTs]);

  // 首次自动加载（有账号 + 合约地址后触发）
  useEffect(() => {
    if (account && nftAddr && isAddress(nftAddr) && !hasAutoLoaded.current) {
      hasAutoLoaded.current = true;
      loadOwnedNFTs();
    }
  }, [account, nftAddr]); // eslint-disable-line react-hooks/exhaustive-deps

  // nftAddr 变化时重置 auto-load 标记并重新加载
  useEffect(() => {
    hasAutoLoaded.current = false;
    if (account && nftAddr && isAddress(nftAddr)) {
      hasAutoLoaded.current = true;
      loadOwnedNFTs();
    }
  }, [nftAddr]); // eslint-disable-line react-hooks/exhaustive-deps

  const mkAction = (fn) => async (...args) => { try { await fn(...args); await refreshNft(tokenId); await loadOwnedNFTs(); } catch { /* in txStatus */ } };

  const { active, seller, price, paymentToken } = listingInfo || {};
  const isSeller = account && seller && account.toLowerCase() === seller.toLowerCase();
  const validToken = tokenId !== "" && !isNaN(Number(tokenId)) && Number(tokenId) >= 0 && Number.isInteger(Number(tokenId));

  const [listPrice, setListPrice] = useState("");

  // 点击 My NFTs 中的 NFT 时自动加载其 listing 信息
  const selectNFT = useCallback((tid) => {
    setTokenId(String(tid));
    refreshNft(tid);
  }, [refreshNft]);

  return (
    <>
      {/* ── Market Config ── */}
      <div className="card">
        <div className="card-header" style={{ display: "flex", justifyContent: "space-between", alignItems: "center" }}>
          <span>📄 NFTMarket Contract</span>
          <span className="chip active" style={{ fontSize: "0.7rem" }}>🟢 {networkLabel}</span>
        </div>
        <div className="form-group">
          <label className="form-label">NFTMarket Address</label>
          <input className="input" value={marketAddr} onChange={e => { setMarketAddr(e.target.value); clearTxStatus(); }} placeholder="0x…" spellCheck={false} />
        </div>
      </div>

      {/* ── My NFTs ── */}
      <div className="card">
        <div className="card-header" style={{ display: "flex", justifyContent: "space-between", alignItems: "center" }}>
          <span>🎴 My NFTs</span>
          <button className="btn btn-secondary btn-sm" disabled={!account || myNFTsLoading} onClick={loadOwnedNFTs}>
            {myNFTsLoading ? "…" : "🔄 Refresh"}
          </button>
        </div>
        <div className="form-group">
          <label className="form-label">NFT Contract Address</label>
          <input className="input" value={nftAddr} onChange={e => { setNftAddr(e.target.value); setListingInfo(null); setBITInfo(null); }} placeholder="0x… ERC721" spellCheck={false} />
        </div>
        {myNFTs === null && !myNFTsLoading && (
          <p style={{ color: "#94a3b8", fontSize: "0.8rem", marginTop: "0.5rem" }}>Connect wallet to see your NFTs.</p>
        )}
        {myNFTs !== null && myNFTs.length === 0 && !myNFTsLoading && (
          <p style={{ color: "#94a3b8", fontSize: "0.8rem", marginTop: "0.5rem" }}>You don't own any NFTs from this collection yet.</p>
        )}
        {myNFTs && myNFTs.length > 0 && (
          <div style={{ marginTop: "0.5rem", display: "grid", gridTemplateColumns: "repeat(auto-fill, minmax(160px, 1fr))", gap: "0.75rem" }}>
            {myNFTs.map((nft) => (
              <div key={nft.tokenId} onClick={() => selectNFT(nft.tokenId)}
                style={{ cursor: "pointer", borderRadius: "10px", overflow: "hidden", border: tokenId === String(nft.tokenId) ? "2px solid #fcd34d" : "2px solid #1e293b",
                  transition: "border-color 0.2s, transform 0.15s", backgroundColor: "#0f172a"
                }}
                onMouseEnter={(e) => { e.currentTarget.style.borderColor = "#fcd34d"; e.currentTarget.style.transform = "scale(1.02)"; }}
                onMouseLeave={(e) => { e.currentTarget.style.borderColor = tokenId === String(nft.tokenId) ? "#fcd34d" : "#1e293b"; e.currentTarget.style.transform = "scale(1)"; }}>
                {nft.image ? (
                  <img src={ipfsToHttp(nft.image)} alt={nft.name || `#${nft.tokenId}`}
                    style={{ width: "100%", aspectRatio: "1", objectFit: "cover", display: "block" }}
                    onError={(e) => { e.target.src = "data:image/svg+xml," + encodeURIComponent('<svg xmlns="http://www.w3.org/2000/svg" width="200" height="200"><rect fill="#1e293b" width="200" height="200"/><text fill="#94a3b8" font-size="14" x="50%" y="50%" dominant-baseline="middle" text-anchor="middle">No Image</text></svg>'); }} />
                ) : (
                  <div style={{ width: "100%", aspectRatio: "1", backgroundColor: "#1e293b", display: "flex", alignItems: "center", justifyContent: "center" }}>
                    <span style={{ color: "#94a3b8", fontSize: "2rem" }}>🖼️</span>
                  </div>
                )}
                <div style={{ padding: "0.5rem" }}>
                  <div style={{ fontFamily: "'SF Mono','Fira Code',monospace", fontSize: "0.75rem", color: "#fcd34d", fontWeight: 600 }}>
                    #{nft.tokenId}
                  </div>
                  {nft.name && (
                    <div style={{ fontSize: "0.78rem", color: "#e2e8f0", marginTop: "0.15rem", whiteSpace: "nowrap", overflow: "hidden", textOverflow: "ellipsis" }}>
                      {nft.name}
                    </div>
                  )}
                </div>
              </div>
            ))}
          </div>
        )}
      </div>

      {/* ── Token ID selector + selected NFT quick info ── */}
      <div className="card">
        <div className="card-header">🔍 Selected NFT</div>
        <div className="form-group">
          <label className="form-label">Token ID</label>
          <div className="input-row">
            <input className="input" value={tokenId} onChange={e => { setTokenId(e.target.value); setListingInfo(null); setBITInfo(null); }} placeholder="0" spellCheck={false} />
            <button className="btn btn-primary btn-sm" disabled={!validToken || !account || loading} onClick={() => refreshNft()}>{loading ? "…" : "🔍 Load"}</button>
          </div>
        </div>
        {listingInfo && (
          <div style={{ marginTop: "0.25rem", fontSize: "0.78rem", color: "#94a3b8" }}>
            <span style={{ color: active ? "#6ee7b7" : "#fca5a5" }}>{active ? "🟢 Listed" : "🔴 Not Listed"}</span>
            {active && seller && (
              <> · Seller: <AddressLabel address={seller} mono /></>
            )}
            {active && price != null && bitInfo && (
              <> · Price: {formatUnits(price, bitInfo.decimals)} {bitInfo.symbol}</>
            )}
            {isSeller && <span style={{ color: "#fcd34d", marginLeft: "0.5rem" }}>👤 You</span>}
          </div>
        )}
      </div>

      {/* ── List ── */}
      <div className="card">
        <div className="card-header">📋 List NFT for Sale</div>
        <p style={{ color: "#94a3b8", fontSize: "0.8rem", marginBottom: "0.75rem" }}>Select an NFT above, then set a price and list it.</p>
        <div className="form-group">
          <label className="form-label">Token ID to List</label>
          <input className="input" value={tokenId} onChange={e => { setTokenId(e.target.value); }} placeholder="0" spellCheck={false} />
        </div>
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
        <div className="form-group">
          <label className="form-label">Token ID to Buy</label>
          <input className="input" value={tokenId} onChange={e => { setTokenId(e.target.value); }} placeholder="0" spellCheck={false} />
        </div>
        {!active && listingInfo && validToken && <div style={{ color: "#94a3b8", fontSize: "0.75rem", marginBottom: "0.5rem" }}>⚠ Not listed.</div>}
        {active && isSeller && <div style={{ color: "#fbbf24", fontSize: "0.75rem", marginBottom: "0.5rem" }}>⚠ You are the seller.</div>}
        {active && !isSeller && bitInfo && bitInfo.balance < price && <div style={{ color: "#fca5a5", fontSize: "0.75rem", marginBottom: "0.5rem" }}>❌ Insufficient BIT balance.</div>}
        <button className="btn btn-primary" disabled={!active||isSeller||txPending} onClick={() => { mkAction(buy)(nftAddr, Number(tokenId), price, paymentToken); }}>{txPending ? "⏳ Processing…" : "🛒 Approve & Buy"}</button>
        <TxStatus status={txStatus} />
      </div>

      {/* ── Cancel ── */}
      <div className="card">
        <div className="card-header">❌ Cancel Listing</div>
        <p style={{ color: "#94a3b8", fontSize: "0.8rem", marginBottom: "0.75rem" }}>Cancel your listing and get your NFT back.</p>
        <div className="form-group">
          <label className="form-label">Token ID to Cancel</label>
          <input className="input" value={tokenId} onChange={e => { setTokenId(e.target.value); }} placeholder="0" spellCheck={false} />
        </div>
        {!active && listingInfo && validToken && <div style={{ color: "#94a3b8", fontSize: "0.75rem", marginBottom: "0.5rem" }}>⚠ Not listed.</div>}
        {active && !isSeller && <div style={{ color: "#fbbf24", fontSize: "0.75rem", marginBottom: "0.5rem" }}>⚠ Only the seller can cancel.</div>}
        <button className="btn btn-danger" disabled={!active||!isSeller||txPending} onClick={() => { mkAction(cancel)(nftAddr, Number(tokenId)); }}>{txPending ? "⏳ Processing…" : "❌ Cancel Listing"}</button>
        <TxStatus status={txStatus} />
      </div>

    </>
  );
}
