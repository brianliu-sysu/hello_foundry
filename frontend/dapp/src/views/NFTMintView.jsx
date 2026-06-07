import { useState, useEffect, useRef, useCallback } from "react";
import { isAddress } from "ethers";
import { useNFTMint } from "../hooks/useNFTMint";
import { BRIANFT_DEPLOYED, ipfsToHttp } from "../utils/contract";
import { DEFAULT_NETWORK, NETWORK_LABELS } from "../config";
import TxStatus from "../components/TxStatus";
import AddressLabel from "../components/AddressLabel";

export default function NFTMintView({ signer, account, chainId }) {
  const networkKey = chainId != null ? String(chainId) : DEFAULT_NETWORK;
  const networkLabel = NETWORK_LABELS[networkKey] || `Chain ${networkKey}`;

  const [nftAddr, setNftAddr] = useState(BRIANFT_DEPLOYED[networkKey] || "");

  const prevNetwork = useRef(networkKey);
  useEffect(() => {
    if (prevNetwork.current !== networkKey) {
      prevNetwork.current = networkKey;
      setNftAddr(BRIANFT_DEPLOYED[networkKey] || "");
      clearTxStatus();
    }
  }, [networkKey]); // eslint-disable-line react-hooks/exhaustive-deps

  const {
    nftAddressOk,
    txStatus, txPending, clearTxStatus,
    maxSupply, totalMinted, nextTokenId,
    nftOwner, nftName, nftSymbol,
    statsLoading, refreshStats,
    safeMint, safeMintBatch,
    myNFTs, myNFTsLoading, loadMyNFTs,
  } = useNFTMint(signer, nftAddr);

  // ── 自动加载当前用户的 NFT ──
  const hasAutoLoadedNFTs = useRef(false);

  useEffect(() => {
    if (account && nftAddressOk && !hasAutoLoadedNFTs.current) {
      hasAutoLoadedNFTs.current = true;
      loadMyNFTs(account);
    }
  }, [account, nftAddressOk, loadMyNFTs]);

  // nftAddr 变化时重置标记并重新加载
  useEffect(() => {
    hasAutoLoadedNFTs.current = false;
    if (account && nftAddressOk) {
      hasAutoLoadedNFTs.current = true;
      loadMyNFTs(account);
    }
  }, [nftAddr]); // eslint-disable-line react-hooks/exhaustive-deps

  // ── 单个 Mint 状态 ──
  const DEFAULT_MINT_URI = "bafkreia5hk7ykthyjrqqyr4l5iahel3ifevvyhktwlcfaejx5uhr6zeydu";
  const [mintTo, setMintTo] = useState(account || "");
  const [mintUri, setMintUri] = useState("");
  useEffect(() => { if (account && !mintTo) setMintTo(account); }, [account]); // eslint-disable-line react-hooks/exhaustive-deps

  const isRecipientValid = mintTo && isAddress(mintTo);

  // ── 批量 Mint 状态 ──
  const [batchRows, setBatchRows] = useState([
    { to: account || "", uri: "" },
    { to: "", uri: "" },
  ]);

  const updateBatchRow = (i, field, value) => {
    const next = batchRows.map((r, idx) => (idx === i ? { ...r, [field]: value } : r));
    setBatchRows(next);
  };
  const addBatchRow = () => setBatchRows([...batchRows, { to: "", uri: "" }]);
  const removeBatchRow = (i) => {
    if (batchRows.length <= 1) return;
    setBatchRows(batchRows.filter((_, idx) => idx !== i));
  };

  const batchValid = batchRows.every(r => r.to && isAddress(r.to)) && batchRows.length > 0;

  // ── 计算可铸造数量 ──
  const remaining = (() => {
    if (maxSupply === null || totalMinted === null) return null;
    if (maxSupply === 0n) return "∞"; // 无上限
    const rem = maxSupply - totalMinted;
    if (rem < 0n) return "0";
    return String(rem);
  })();

  const isOwner = account && nftOwner && account.toLowerCase() === nftOwner.toLowerCase();
  const isSupplyExhausted = maxSupply !== null && maxSupply !== 0n && totalMinted !== null && totalMinted >= maxSupply;

  return (
    <>
      {/* ── NFT Contract Config ── */}
      <div className="card">
        <div className="card-header" style={{ display: "flex", justifyContent: "space-between", alignItems: "center" }}>
          <span>🖼️ BrianNFT Contract</span>
          <span className="chip active" style={{ fontSize: "0.7rem" }}>🟢 {networkLabel}</span>
        </div>
        <div className="form-group">
          <label className="form-label">NFT Contract Address</label>
          <input className="input" value={nftAddr} onChange={e => { setNftAddr(e.target.value); clearTxStatus(); }} placeholder="0x…" spellCheck={false} />
        </div>
        {nftAddressOk && (
          <button className="btn btn-secondary btn-sm" disabled={statsLoading} onClick={refreshStats} style={{ marginTop: "0.25rem" }}>
            {statsLoading ? "…" : "🔄 Refresh Stats"}
          </button>
        )}
      </div>

      {/* ── Collection Stats ── */}
      {nftAddressOk && (
        <div className="card">
          <div className="card-header">📊 Collection Stats</div>
          {statsLoading ? (
            <p style={{ color: "#94a3b8", fontSize: "0.8rem" }}>Loading stats…</p>
          ) : (
            <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: "0.75rem", fontSize: "0.85rem" }}>
              {nftName && (
                <div>
                  <div style={{ color: "#64748b", fontSize: "0.72rem", marginBottom: "0.15rem" }}>Name</div>
                  <div style={{ color: "#e2e8f0", fontWeight: 600 }}>{nftName} ({nftSymbol})</div>
                </div>
              )}
              <div>
                <div style={{ color: "#64748b", fontSize: "0.72rem", marginBottom: "0.15rem" }}>Owner</div>
                {nftOwner ? <AddressLabel address={nftOwner} mono /> : <span style={{ color: "#94a3b8" }}>—</span>}
              </div>
              <div>
                <div style={{ color: "#64748b", fontSize: "0.72rem", marginBottom: "0.15rem" }}>Total Minted</div>
                <div style={{ color: "#e2e8f0", fontFamily: "'SF Mono','Fira Code',monospace" }}>
                  {totalMinted !== null ? String(totalMinted) : "—"}
                </div>
              </div>
              <div>
                <div style={{ color: "#64748b", fontSize: "0.72rem", marginBottom: "0.15rem" }}>Next Token ID</div>
                <div style={{ color: "#e2e8f0", fontFamily: "'SF Mono','Fira Code',monospace" }}>
                  {nextTokenId !== null ? String(nextTokenId) : "—"}
                </div>
              </div>
              <div>
                <div style={{ color: "#64748b", fontSize: "0.72rem", marginBottom: "0.15rem" }}>Max Supply</div>
                <div style={{
                  color: maxSupply === 0n ? "#fcd34d" : "#e2e8f0",
                  fontFamily: "'SF Mono','Fira Code',monospace",
                  fontWeight: 600,
                }}>
                  {maxSupply === null ? "—" : maxSupply === 0n ? "Unlimited" : String(maxSupply)}
                </div>
              </div>
              <div>
                <div style={{ color: "#64748b", fontSize: "0.72rem", marginBottom: "0.15rem" }}>Remaining</div>
                <div style={{
                  color: remaining === "∞" ? "#fcd34d" : remaining === "0" ? "#fca5a5" : "#6ee7b7",
                  fontFamily: "'SF Mono','Fira Code',monospace",
                  fontWeight: 700,
                  fontSize: "1.05rem",
                }}>
                  {remaining === null ? "—" : remaining === "∞" ? "∞" : remaining}
                </div>
              </div>
            </div>
          )}
          {isOwner && (
            <div style={{ marginTop: "0.5rem", color: "#fcd34d", fontSize: "0.75rem" }}>👑 You are the owner — mint controls unlocked below.</div>
          )}
          {!isOwner && nftOwner && (
            <div style={{ marginTop: "0.5rem", color: "#94a3b8", fontSize: "0.75rem" }}>👤 Mint controls are hidden — only the contract owner can mint.</div>
          )}
        </div>
      )}

      {/* ── My NFTs Gallery ── */}
      {nftAddressOk && (
        <div className="card">
          <div className="card-header" style={{ display: "flex", justifyContent: "space-between", alignItems: "center" }}>
            <span>🎴 My NFTs</span>
            <button className="btn btn-secondary btn-sm" disabled={!account || myNFTsLoading} onClick={() => loadMyNFTs(account)}>
              {myNFTsLoading ? "…" : "🔄 Refresh"}
            </button>
          </div>
          {!account && (
            <p style={{ color: "#94a3b8", fontSize: "0.8rem", marginTop: "0.5rem" }}>Connect wallet to see your NFTs.</p>
          )}
          {account && myNFTs === null && !myNFTsLoading && (
            <p style={{ color: "#94a3b8", fontSize: "0.8rem", marginTop: "0.5rem" }}>Loading your NFTs…</p>
          )}
          {myNFTsLoading && (
            <p style={{ color: "#94a3b8", fontSize: "0.8rem", marginTop: "0.5rem" }}>⏳ Loading…</p>
          )}
          {myNFTs !== null && myNFTs.length === 0 && !myNFTsLoading && (
            <div style={{ marginTop: "0.5rem", textAlign: "center", padding: "2rem 0" }}>
              <div style={{ fontSize: "2.5rem", marginBottom: "0.5rem" }}>🖼️</div>
              <p style={{ color: "#64748b", fontSize: "0.85rem" }}>You don't own any NFTs from this collection yet.</p>
              <p style={{ color: "#475569", fontSize: "0.75rem", marginTop: "0.25rem" }}>
                {nftName ? `${nftName} (${nftSymbol})` : "Ask the owner to mint you one!"}
              </p>
            </div>
          )}
          {myNFTs && myNFTs.length > 0 && (
            <>
              <div style={{ marginBottom: "0.5rem", color: "#94a3b8", fontSize: "0.75rem" }}>
                {myNFTs.length} NFT{myNFTs.length > 1 ? "s" : ""} owned
              </div>
              <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fill, minmax(240px, 1fr))", gap: "0.75rem" }}>
                {myNFTs.map((nft) => (
                  <div key={nft.tokenId}
                    style={{
                      borderRadius: "12px", overflow: "hidden",
                      border: "1px solid #1e293b", backgroundColor: "#0f172a",
                      transition: "border-color 0.2s, transform 0.15s",
                    }}
                    onMouseEnter={(e) => { e.currentTarget.style.borderColor = "#fcd34d"; e.currentTarget.style.transform = "scale(1.02)" }}
                    onMouseLeave={(e) => { e.currentTarget.style.borderColor = "#1e293b"; e.currentTarget.style.transform = "scale(1)" }}>
                    {/* 图片 */}
                    {nft.image ? (
                      <img src={ipfsToHttp(nft.image)}
                        alt={nft.name || `#${nft.tokenId}`}
                        style={{ width: "100%", aspectRatio: "1", objectFit: "cover", display: "block", backgroundColor: "#1e293b" }}
                        onError={(e) => { e.target.src = "data:image/svg+xml," + encodeURIComponent('<svg xmlns="http://www.w3.org/2000/svg" width="200" height="200"><rect fill="#1e293b" width="200" height="200"/><text fill="#94a3b8" font-size="14" x="50%" y="50%" dominant-baseline="middle" text-anchor="middle">No Image</text></svg>'); }} />
                    ) : (
                      <div style={{ width: "100%", aspectRatio: "1", backgroundColor: "#1e293b", display: "flex", alignItems: "center", justifyContent: "center" }}>
                        <span style={{ color: "#94a3b8", fontSize: "2.5rem" }}>🖼️</span>
                      </div>
                    )}
                    {/* 信息 */}
                    <div style={{ padding: "0.65rem" }}>
                      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", marginBottom: "0.3rem" }}>
                        <span style={{ fontFamily: "'SF Mono','Fira Code',monospace", fontSize: "0.8rem", color: "#fcd34d", fontWeight: 600 }}>
                          #{nft.tokenId}
                        </span>
                        {nft.attributes && nft.attributes.length > 0 && (
                          <span style={{ fontSize: "0.65rem", color: "#64748b" }}>{nft.attributes.length} attr{nft.attributes.length > 1 ? "s" : ""}</span>
                        )}
                      </div>
                      {nft.name ? (
                        <div style={{ fontSize: "0.82rem", color: "#e2e8f0", fontWeight: 600, lineHeight: 1.3, marginBottom: "0.25rem" }}>
                          {nft.name}
                        </div>
                      ) : (
                        <div style={{ fontSize: "0.82rem", color: "#475569", marginBottom: "0.25rem", fontStyle: "italic" }}>
                          Unnamed NFT
                        </div>
                      )}
                      {nft.description && (
                        <div style={{ fontSize: "0.72rem", color: "#94a3b8", lineHeight: 1.4, display: "-webkit-box", WebkitLineClamp: 3, WebkitBoxOrient: "vertical", overflow: "hidden" }}>
                          {nft.description}
                        </div>
                      )}
                    </div>
                  </div>
                ))}
              </div>
            </>
          )}
        </div>
      )}

      {/* ── Single Mint ── */}
      {nftAddressOk && isOwner && (
        <div className="card">
          <div className="card-header">🎨 Mint Single NFT</div>
          <p style={{ color: "#94a3b8", fontSize: "0.8rem", marginBottom: "0.75rem" }}>
            Mint one NFT to a specified address (owner only).
          </p>
          <div className="form-group">
            <label className="form-label">Recipient Address</label>
            <input className="input" value={mintTo} onChange={e => setMintTo(e.target.value)}
              placeholder={account ? `Your wallet: ${account.slice(0, 6)}…${account.slice(-4)}` : "0x…"} spellCheck={false} />
          </div>
          <div className="form-group">
            <label className="form-label">URI (IPFS CID or path)</label>
            <input className="input" value={mintUri} onChange={e => setMintUri(e.target.value)} placeholder={DEFAULT_MINT_URI} spellCheck={false} />
          </div>
          {isSupplyExhausted && (
            <div style={{ color: "#fca5a5", fontSize: "0.75rem", marginBottom: "0.5rem" }}>❌ Max supply reached. No more NFTs can be minted.</div>
          )}
          <button className="btn btn-primary"
            disabled={!isRecipientValid || txPending || isSupplyExhausted}
            onClick={async () => {
              const to = mintTo && isAddress(mintTo) ? mintTo : account;
              await safeMint(to, mintUri || DEFAULT_MINT_URI);
              setMintUri("");
              if (account) loadMyNFTs(account);
            }}>
            {txPending ? "⏳ Minting…" : "🎨 Mint Single NFT"}
          </button>
          <TxStatus status={txStatus} />
        </div>
      )}

      {/* ── Batch Mint ── */}
      {nftAddressOk && isOwner && (
        <div className="card">
          <div className="card-header" style={{ display: "flex", justifyContent: "space-between", alignItems: "center" }}>
            <span>🎨🖼️ Batch Mint</span>
            <button className="btn btn-secondary btn-sm" onClick={addBatchRow} style={{ fontSize: "0.75rem" }}>+ Add Row</button>
          </div>
          <p style={{ color: "#94a3b8", fontSize: "0.8rem", marginBottom: "0.75rem" }}>
            Mint multiple NFTs in a single transaction (owner only).
          </p>

          {batchRows.map((row, i) => (
            <div key={i} style={{
              display: "grid", gridTemplateColumns: isAddress(row.to) ? "1fr 2fr 56px" : "1fr 2fr 56px",
              gap: "0.5rem", marginBottom: "0.5rem", alignItems: "end",
            }}>
              <div>
                {i === 0 && <div className="form-label" style={{ fontSize: "0.7rem", marginBottom: "0.15rem" }}>Recipient</div>}
                <input className="input"
                  value={row.to}
                  onChange={e => updateBatchRow(i, "to", e.target.value)}
                  placeholder="0x…"
                  spellCheck={false}
                  style={{ borderColor: row.to && !isAddress(row.to) ? "#fca5a5" : undefined }} />
              </div>
              <div>
                {i === 0 && <div className="form-label" style={{ fontSize: "0.7rem", marginBottom: "0.15rem" }}>URI</div>}
                <input className="input"
                  value={row.uri}
                  onChange={e => updateBatchRow(i, "uri", e.target.value)}
                  placeholder={DEFAULT_MINT_URI}
                  spellCheck={false} />
              </div>
              <div>
                {i === 0 && <div className="form-label" style={{ fontSize: "0.7rem", marginBottom: "0.15rem" }}>&nbsp;</div>}
                <button className="btn btn-danger btn-sm"
                  disabled={batchRows.length <= 1}
                  onClick={() => removeBatchRow(i)}
                  style={{ padding: "0.35rem 0.5rem", fontSize: "0.75rem" }}>
                  ✕
                </button>
              </div>
            </div>
          ))}

          {batchRows.length > 0 && (
            <div style={{ color: "#94a3b8", fontSize: "0.72rem", marginBottom: "0.75rem" }}>
              {batchRows.length} recipient{batchRows.length > 1 ? "s" : ""} ·{" "}
              {batchRows.filter(r => r.to && isAddress(r.to)).length} valid address{batchRows.filter(r => r.to && isAddress(r.to)).length !== 1 ? "es" : ""}
            </div>
          )}

          {isSupplyExhausted && (
            <div style={{ color: "#fca5a5", fontSize: "0.75rem", marginBottom: "0.5rem" }}>❌ Max supply reached.</div>
          )}
          {maxSupply !== null && maxSupply !== 0n && totalMinted !== null && batchRows.length > (maxSupply - totalMinted) && !isSupplyExhausted && (
            <div style={{ color: "#fbbf24", fontSize: "0.75rem", marginBottom: "0.5rem" }}>
              ⚠ Only {String(maxSupply - totalMinted)} remaining — batch has {batchRows.length} rows.
            </div>
          )}

          <button className="btn btn-primary"
            disabled={!batchValid || txPending || isSupplyExhausted}
            onClick={async () => {
              const recipients = batchRows.map(r => r.to);
              const uris = batchRows.map(r => r.uri || DEFAULT_MINT_URI);
              await safeMintBatch(recipients, uris);
              if (account) loadMyNFTs(account);
            }}>
            {txPending ? "⏳ Minting…" : `🎨 Batch Mint (${batchRows.length} NFT${batchRows.length > 1 ? "s" : ""})`}
          </button>
          <TxStatus status={txStatus} />
        </div>
      )}
    </>
  );
}
