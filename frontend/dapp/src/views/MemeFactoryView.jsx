import { useState, useCallback, useEffect, useRef } from "react";
import { isAddress, parseUnits, formatUnits } from "ethers";
import { useMemeFactory } from "../hooks/useMemeFactory";
import { MEMEFACTORY_DEPLOYED } from "../utils/contract";
import { DEFAULT_NETWORK, NETWORK_LABELS } from "../config";
import TxStatus from "../components/TxStatus";

const PAGE_SIZE = 10;

export default function MemeFactoryView({ signer, account, chainId }) {
  const networkKey = chainId != null ? String(chainId) : DEFAULT_NETWORK;
  const networkLabel = NETWORK_LABELS[networkKey] || `Chain ${networkKey}`;

  const [factoryAddr, setFactoryAddr] = useState(MEMEFACTORY_DEPLOYED[networkKey] || "");

  const prevNetwork = useRef(networkKey);
  useEffect(() => {
    if (prevNetwork.current !== networkKey) {
      prevNetwork.current = networkKey;
      setFactoryAddr(MEMEFACTORY_DEPLOYED[networkKey] || "");
      clearTxStatus();
    }
  }, [networkKey]); // eslint-disable-line react-hooks/exhaustive-deps

  const { txStatus, txPending, clearTxStatus, createMeme, loadMemeTokens, getMemeCount } =
    useMemeFactory(signer, factoryAddr);

  // ── Create state ──
  const [memeName, setMemeName] = useState("");
  const [memeSymbol, setMemeSymbol] = useState("");
  const [memeSupply, setMemeSupply] = useState("");
  const [memeDecimals, setMemeDecimals] = useState("18");

  // ── List state ──
  const [tokens, setTokens] = useState([]);
  const [totalCount, setTotalCount] = useState(null);
  const [page, setPage] = useState(0);
  const [listLoading, setListLoading] = useState(false);
  const [listError, setListError] = useState(null);

  // ── Refresh list ──
  const refreshList = useCallback(async (p) => {
    if (!account) { setListError("Please connect MetaMask first."); return; }
    if (!factoryAddr || !isAddress(factoryAddr)) { setListError("Invalid factory address"); return; }
    setListError(null); setListLoading(true);
    try {
      const result = await loadMemeTokens(p * PAGE_SIZE, PAGE_SIZE, account);
      setTokens(result.tokens);
      setTotalCount(result.total);
      setPage(p);
    } catch (e) {
      setListError(e.message || "Failed to load meme tokens");
      setTokens([]);
    } finally { setListLoading(false); }
  }, [factoryAddr, account, loadMemeTokens]);

  // ── Actions ──
  const mkCreate = async () => {
    try {
      const supply = parseUnits(memeSupply, Number(memeDecimals) || 18);
      await createMeme(memeName, memeSymbol, supply);
      setMemeName(""); setMemeSymbol(""); setMemeSupply("");
      await refreshList(page);
    } catch { /* in txStatus */ }
  };

  const canCreate = () =>
    memeName.trim() && memeSymbol.trim() &&
    memeSupply && !isNaN(memeSupply) && Number(memeSupply) > 0 &&
    memeDecimals && !isNaN(memeDecimals) && Number(memeDecimals) >= 0 &&
    !txPending && factoryAddr && isAddress(factoryAddr);

  const _totalCount = Number(totalCount ?? 0);
  const totalPages = _totalCount ? Math.ceil(_totalCount / PAGE_SIZE) : 0;

  return (
    <>
      {/* ── Factory Config ── */}
      <div className="card">
        <div className="card-header" style={{ display: "flex", justifyContent: "space-between", alignItems: "center" }}>
          <span>🏭 MemeFactory Contract</span>
          <span className="chip active" style={{ fontSize: "0.7rem" }}>🟢 {networkLabel}</span>
        </div>
        <div className="form-group">
          <label className="form-label">MemeFactory Address</label>
          <input className="input" value={factoryAddr} onChange={e => { setFactoryAddr(e.target.value); clearTxStatus(); }} placeholder="0x…" spellCheck={false} />
        </div>
      </div>

      {/* ── Create Meme ── */}
      <div className="card">
        <div className="card-header">🚀 Create Meme Token</div>
        <p style={{ color: "#94a3b8", fontSize: "0.8rem", marginBottom: "0.75rem" }}>
          Deploy a new ERC20 meme token via minimal proxy (EIP-1167). Only ~55K gas per token.
        </p>
        <div className="form-group">
          <label className="form-label">Token Name</label>
          <input className="input" value={memeName} onChange={e => setMemeName(e.target.value)} placeholder="Dogecoin" spellCheck={false} />
        </div>
        <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: "0.75rem" }}>
          <div className="form-group">
            <label className="form-label">Symbol</label>
            <input className="input" value={memeSymbol} onChange={e => setMemeSymbol(e.target.value)} placeholder="DOGE" spellCheck={false} />
          </div>
          <div className="form-group">
            <label className="form-label">Decimals</label>
            <input className="input" value={memeDecimals} onChange={e => setMemeDecimals(e.target.value)} placeholder="18" spellCheck={false} />
          </div>
        </div>
        <div className="form-group">
          <label className="form-label">Total Supply</label>
          <input className="input" value={memeSupply} onChange={e => setMemeSupply(e.target.value)} placeholder="1000000000" spellCheck={false} />
        </div>
        <button className="btn btn-primary" disabled={!canCreate()} onClick={mkCreate}>
          {txPending ? "⏳ Deploying…" : "🚀 Deploy Meme Token"}
        </button>
        <TxStatus status={txStatus} />
      </div>

      {/* ── Meme Token List ── */}
      <div className="card">
        <div className="card-header" style={{ display: "flex", justifyContent: "space-between", alignItems: "center" }}>
          <span>📋 Meme Tokens</span>
          <button className="btn btn-secondary btn-sm" disabled={!account || listLoading} onClick={() => refreshList(page)}>
            {listLoading ? "…" : "🔄 Refresh"}
          </button>
        </div>
        {totalCount !== null && (
          <p style={{ color: "#94a3b8", fontSize: "0.8rem", marginBottom: "0.5rem" }}>
            Total: {String(totalCount)} token{totalCount !== 1 ? "s" : ""}
          </p>
        )}
        {listError && <div style={{ color: "#fca5a5", fontSize: "0.8rem", marginBottom: "0.5rem" }}>❌ {listError}</div>}

        {tokens.length > 0 && (
          <div style={{ overflowX: "auto" }}>
            <table className="info-table" style={{ width: "100%", borderCollapse: "collapse", fontSize: "0.78rem" }}>
              <thead>
                <tr style={{ borderBottom: "1px solid #334155" }}>
                  <th style={{ textAlign: "left", padding: "0.4rem 0.3rem", color: "#94a3b8" }}>Name</th>
                  <th style={{ textAlign: "left", padding: "0.4rem 0.3rem", color: "#94a3b8" }}>Symbol</th>
                  <th style={{ textAlign: "right", padding: "0.4rem 0.3rem", color: "#94a3b8" }}>Supply</th>
                  <th style={{ textAlign: "right", padding: "0.4rem 0.3rem", color: "#94a3b8" }}>Your Balance</th>
                  <th style={{ textAlign: "left", padding: "0.4rem 0.3rem", color: "#94a3b8" }}>Address</th>
                </tr>
              </thead>
              <tbody>
                {tokens.map((t, i) => (
                  <tr key={t.address} style={{ borderBottom: "1px solid #1e293b" }}>
                    <td style={{ padding: "0.4rem 0.3rem", color: t.owner?.toLowerCase() === account?.toLowerCase() ? "#fcd34d" : "#e2e8f0" }}>
                      {t.owner?.toLowerCase() === account?.toLowerCase() ? "👑 " : ""}{t.name}
                    </td>
                    <td style={{ padding: "0.4rem 0.3rem", color: "#cbd5e1" }}>{t.symbol}</td>
                    <td style={{ padding: "0.4rem 0.3rem", textAlign: "right", fontFamily: "'SF Mono','Fira Code',monospace", color: "#e2e8f0" }}>
                      {t.totalSupply != null ? Number(formatUnits(t.totalSupply, 18)).toLocaleString() : "…"}
                    </td>
                    <td style={{ padding: "0.4rem 0.3rem", textAlign: "right", fontFamily: "'SF Mono','Fira Code',monospace", color: t.balance ? "#6ee7b7" : "#94a3b8" }}>
                      {t.balance != null ? Number(formatUnits(t.balance, 18)).toLocaleString() : "…"}
                    </td>
                    <td style={{ padding: "0.4rem 0.3rem", fontFamily: "'SF Mono','Fira Code',monospace", fontSize: "0.68rem", color: "#94a3b8" }}>
                      {t.address.slice(0, 6) + "…" + t.address.slice(-4)}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}

        {totalPages > 1 && (
          <div style={{ display: "flex", justifyContent: "center", gap: "0.5rem", marginTop: "1rem" }}>
            <button className="btn btn-secondary btn-sm" disabled={page === 0 || listLoading} onClick={() => refreshList(page - 1)}>← Prev</button>
            <span style={{ padding: "0.3rem 0.6rem", color: "#94a3b8", fontSize: "0.8rem" }}>{page + 1} / {totalPages}</span>
            <button className="btn btn-secondary btn-sm" disabled={page >= totalPages - 1 || listLoading} onClick={() => refreshList(page + 1)}>Next →</button>
          </div>
        )}
      </div>
    </>
  );
}
