import { useState, useEffect, useCallback, useRef } from "react";
import { useLeveragedDEX } from "../hooks/useLeveragedDEX";
import { LEVERAGEDDEX_DEPLOYED, shortenHash } from "../utils/contract";
import { DEFAULT_NETWORK, NETWORK_LABELS } from "../config";
import TxStatus from "../components/TxStatus";

function InfoRow({ label, children }) {
  return (<div className="info-row"><span className="info-label">{label}</span><span className="info-value">{children}</span></div>);
}

export default function LeveragedDEXView({ signer, account, chainId }) {
  const networkKey = String(chainId ?? DEFAULT_NETWORK);
  const networkLabel = NETWORK_LABELS[networkKey] || `Chain ${networkKey}`;
  const prevNet = useRef(networkKey);
  const dexAddr = LEVERAGEDDEX_DEPLOYED[networkKey] || "";
  const hook = useLeveragedDEX(signer, dexAddr);

  // ── State ──
  const [ethBalance, setEthBalance] = useState(null);
  const [dexData, setDexData] = useState(null);
  const [margin, setMargin] = useState("");
  const [leverage, setLeverage] = useState(5);
  const [isLong, setIsLong] = useState(true);
  const [activePosTab, setActivePosTab] = useState("mine"); // mine | all

  // ── ETH balance ──
  useEffect(() => {
    if (!signer || !account) { setEthBalance(null); return; }
    let active = true;
    (async () => {
      try { const b = await signer.provider.getBalance(account); if (active) setEthBalance(b); }
      catch { if (active) setEthBalance(null); }
    })();
    return () => { active = false; };
  }, [signer, account]);

  // ── Load dex data ──
  const loadDexData = useCallback(async () => {
    setDexData(await hook.getDexData(account));
  }, [hook, account]);
  useEffect(() => { loadDexData(); }, [loadDexData]);

  // ── Network switch ──
  useEffect(() => {
    if (prevNet.current !== networkKey) {
      prevNet.current = networkKey;
      setMargin(""); setDexData(null); setEthBalance(null);
    }
  }, [networkKey]);

  const refresh = async () => {
    await loadDexData();
    if (signer && account) {
      try { setEthBalance(await signer.provider.getBalance(account)); } catch {}
    }
  };
  const mk = (fn) => async () => { try { await fn(); } catch {} await refresh(); };

  // ── Safe formatters ──
  const toWei = (v) => {
    if (!v) return 0n;
    const [w, f = ""] = v.trim().split(".");
    return BigInt(w || "0") * (10n ** 18n) + BigInt((f + "0".repeat(18)).slice(0, 18));
  };
  const fmtETH = (wei) => {
    if (wei == null) return "—";
    try { const d = 10n ** 18n; const w = wei / d; const f = (wei % d).toString().padStart(18, "0").slice(0, 6); return w.toString() + "." + f; } catch { return "—"; }
  };
  const fmtPrice = (price1e18) => {
    if (price1e18 == null) return "—";
    try { return "$" + (Number(price1e18) / 1e18).toFixed(2); } catch { return "—"; }
  };
  const fmtPnL = (pnlWei) => {
    if (pnlWei == null) return "—";
    try {
      // Coerce ethers Proxy/BigInt to native BigInt
      const pnl = BigInt(pnlWei);
      if (pnl === 0n) return "+0 ETH";
      const sign = pnl < 0n ? "-" : "+";
      const abs = pnl < 0n ? -pnl : pnl;
      const d = 10n ** 18n;
      const whole = abs / d;
      let frac = (abs % d).toString().padStart(18, "0");
      // Strip trailing zeros, then show up to 18 decimals (min 2)
      frac = frac.replace(/0+$/, "");
      if (frac.length < 2) frac = frac.padEnd(2, "0");
      const fracDisplay = frac.length > 6 ? frac.slice(0, 6) + "…" : frac;
      return sign + (whole > 0n ? whole.toString() + "." + fracDisplay : "0." + fracDisplay) + " ETH";
    } catch { return "—"; }
  };

  const notionalDisplay = (pos) => {
    // notional is in USD wei; show it as USD
    try { return "$" + (Number(pos.notional) / 1e18).toLocaleString(undefined, { maximumFractionDigits: 0 }); } catch { return "—"; }
  };

  if (!dexAddr) {
    return (<div className="card"><div className="card-header">📈 Leveraged DEX</div><p style={{ color: "#fbbf24" }}>LeveragedDEX not deployed on {networkLabel} yet.</p></div>);
  }

  const myOpenPositions = dexData?.positions?.filter(p => p.isOpen && p.trader?.toLowerCase() === account?.toLowerCase()) || [];
  const allOpenPositions = dexData?.positions?.filter(p => p.isOpen) || [];

  return (
    <div>
      {/* ── Header ── */}
      <div className="card">
        <div className="card-header">📈 Leveraged DEX — {networkLabel}</div>
        <InfoRow label="Contract">{shortenHash(dexAddr)}</InfoRow>
      </div>

      <TxStatus status={hook.txStatus} />

      {/* ── Pool Stats ── */}
      {dexData && (
        <div className="card" style={{ background: "rgba(99,102,241,0.08)" }}>
          <div className="card-header" style={{ fontSize: "14px" }}>📊 vAMM Pool</div>
          <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: "6px", fontSize: "13px", color: "#cbd5e1" }}>
            <InfoRow label="vBase (ETH)">{fmtETH(dexData.vBase)}</InfoRow>
            <InfoRow label="vQuote (USD)">{fmtETH(dexData.vQuote)}</InfoRow>
            <InfoRow label="Mark Price">{fmtPrice(dexData.price)}</InfoRow>
            <InfoRow label="Total Positions">#{dexData.nextId?.toString()}</InfoRow>
          </div>
        </div>
      )}

      {/* ═══ OPEN POSITION ═══ */}
      {signer && (
        <div className="card">
          <div className="card-header">🚀 Open Position</div>

          {/* Direction toggle */}
          <div style={{ marginTop: "8px", display: "flex", gap: "8px", marginBottom: "14px" }}>
            <button className={`tab ${isLong ? "active" : ""}`}
              onClick={() => setIsLong(true)}
              style={isLong ? { background: "rgba(34,197,94,0.2)", color: "#6ee7b7" } : {}}>
              📈 Long
            </button>
            <button className={`tab ${!isLong ? "active" : ""}`}
              onClick={() => setIsLong(false)}
              style={!isLong ? { background: "rgba(239,68,68,0.2)", color: "#fca5a5" } : {}}>
              📉 Short
            </button>
          </div>

          {/* Margin */}
          <div className="form-group">
            <label className="form-label">Margin (ETH)</label>
            <input className="input" type="number" step="any" placeholder="0.0" value={margin}
              onChange={e => setMargin(e.target.value)} />
            <div style={{ fontSize: "12px", color: "#94a3b8", marginTop: "4px" }}>
              Balance: {ethBalance != null ? fmtETH(ethBalance) : "—"} ETH
              {ethBalance != null && ethBalance > 0n && (
                <span style={{ cursor: "pointer", color: "#6366f1", marginLeft: "8px" }}
                  onClick={() => setMargin(fmtETH(ethBalance))}>MAX</span>
              )}
            </div>
          </div>

          {/* Leverage slider */}
          <div className="form-group">
            <label className="form-label">Leverage: <strong>{leverage}x</strong></label>
            <input className="input" type="range" min="2" max="10" step="1" value={leverage}
              onChange={e => setLeverage(Number(e.target.value))}
              style={{ width: "100%", marginTop: "4px" }} />
            <div style={{ display: "flex", justifyContent: "space-between", fontSize: "11px", color: "#64748b" }}>
              <span>2x</span><span>5x</span><span>10x</span>
            </div>
          </div>

          {/* Preview */}
          {margin && parseFloat(margin) > 0 && (
            <div style={{ padding: "8px 12px", borderRadius: "8px", background: "rgba(99,102,241,0.1)", fontSize: "13px", color: "#cbd5e1", marginBottom: "12px" }}>
              <InfoRow label="Notional">{fmtETH(toWei(margin) * BigInt(leverage))} ETH</InfoRow>
              <InfoRow label="Liquidation Price">{dexData ? fmtPrice(
                isLong
                  ? dexData.price * BigInt(10_000 - 625) / BigInt(10_000)
                  : dexData.price * BigInt(10_000 + 625) / BigInt(10_000)
              ) : "—"}</InfoRow>
            </div>
          )}

          <button className="btn" style={{ marginTop: "10px", width: "100%" }}
            onClick={mk(() => hook.openPosition(BigInt(leverage), isLong, toWei(margin)))}
            disabled={hook.txPending || !margin || parseFloat(margin) <= 0}>
            {isLong ? "📈 Open Long" : "📉 Open Short"}
          </button>
        </div>
      )}

      {/* ═══ POSITIONS ═══ */}
      {signer && (
        <div className="card">
          <div className="card-header">📋 Positions</div>

          {/* Sub-tabs */}
          <div style={{ display: "flex", gap: "8px", marginBottom: "14px" }}>
            <button className={`tab ${activePosTab === "mine" ? "active" : ""}`}
              onClick={() => setActivePosTab("mine")}>
              👤 My Positions ({myOpenPositions.length})
            </button>
            <button className={`tab ${activePosTab === "all" ? "active" : ""}`}
              onClick={() => setActivePosTab("all")}>
              🌐 All Open ({allOpenPositions.length})
            </button>
          </div>

          {activePosTab === "mine" && myOpenPositions.length === 0 && (
            <p style={{ color: "#94a3b8", fontSize: "13px" }}>No open positions.</p>
          )}
          {activePosTab === "all" && allOpenPositions.length === 0 && (
            <p style={{ color: "#94a3b8", fontSize: "13px" }}>No open positions on the market.</p>
          )}

          {(activePosTab === "mine" ? myOpenPositions : allOpenPositions).map(p => {
            const isMine = p.trader?.toLowerCase() === account?.toLowerCase();
            return (
              <div key={p.id} style={{
                padding: "10px 14px", marginBottom: "8px", borderRadius: "8px",
                background: p.isLong ? "rgba(34,197,94,0.06)" : "rgba(239,68,68,0.06)",
                border: `1px solid ${p.isLong ? "rgba(34,197,94,0.2)" : "rgba(239,68,68,0.2)"}`,
                fontSize: "13px", color: "#cbd5e1",
              }}>
                <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", flexWrap: "wrap", gap: "8px" }}>
                  <span>
                    <strong style={{ color: p.isLong ? "#6ee7b7" : "#fca5a5" }}>#{p.id.toString()} {p.isLong ? "📈 LONG" : "📉 SHORT"} {p.leverage?.toString()}x</strong>
                    {" · "}{shortenHash(p.trader)}
                  </span>
                  <span style={{ color: p.pnl != null && p.pnl > 0n ? "#6ee7b7" : p.pnl != null && p.pnl < 0n ? "#fca5a5" : "#94a3b8" }}>
                    PnL: {fmtPnL(p.pnl)}
                  </span>
                </div>
                <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr 1fr", gap: "4px", marginTop: "6px", fontSize: "12px", color: "#94a3b8" }}>
                  <span>Margin: {fmtETH(p.collateral)} ETH</span>
                  <span>Size: {fmtETH(p.size)} ETH</span>
                  <span>Notional: {notionalDisplay(p)}</span>
                </div>
                {isMine && (
                  <button className="btn btn-secondary" style={{ marginTop: "6px", fontSize: "12px", padding: "4px 14px" }}
                    onClick={mk(() => hook.closePosition(p.id))}
                    disabled={hook.txPending}>
                    Close Position
                  </button>
                )}
                {!isMine && (
                  <button className="btn btn-secondary" style={{ marginTop: "6px", fontSize: "12px", padding: "4px 14px", background: "rgba(239,68,68,0.15)", color: "#fca5a5" }}
                    onClick={mk(() => hook.liquidate(p.id))}
                    disabled={hook.txPending}>
                    Liquidate
                  </button>
                )}
              </div>
            );
          })}
        </div>
      )}

      {/* ── REFRESH ── */}
      <div style={{ marginTop: "10px" }}>
        <button className="btn btn-secondary" onClick={refresh} disabled={hook.txPending}>🔄 Refresh</button>
      </div>
    </div>
  );
}
