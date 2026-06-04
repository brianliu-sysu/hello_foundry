import { useState, useCallback } from "react";
import { isAddress, parseUnits, formatUnits } from "ethers";
import { useTokenBank } from "../hooks/useTokenBank";
import { TOKENBANK_DEPLOYED, BRIANICOTOKEN_DEPLOYED } from "../utils/contract";
import TxStatus from "../components/TxStatus";

const DEFAULT_NETWORK = "31337";

export default function TokenBankView({ signer, account }) {
  const [bankAddress,    setBankAddress]    = useState(TOKENBANK_DEPLOYED[DEFAULT_NETWORK] || "");
  const [tokenAddr,      setTokenAddr]      = useState(BRIANICOTOKEN_DEPLOYED[DEFAULT_NETWORK] || "");
  const [network,        setNetwork]        = useState(DEFAULT_NETWORK);
  const [symbol,         setSymbol]         = useState("");
  const [decimals,       setDecimals]       = useState(null);
  const [balance,        setBalance]        = useState(null);
  const [depositBalance, setDepositBalance] = useState(null);
  const [bankBalance,    setBankBalance]    = useState(null);
  const [allowance,      setAllowance]      = useState(null);
  const [infoError,      setInfoError]      = useState(null);
  const [loading,        setLoading]        = useState(false);

  const { txStatus, txPending, clearTxStatus, deposit, permitDeposit, withdraw, getTokenInfo, getAllowance } = useTokenBank(signer, bankAddress);

  const onNetwork = useCallback((key) => {
    setNetwork(key);
    setBankAddress(TOKENBANK_DEPLOYED[key] || "");
    setTokenAddr(BRIANICOTOKEN_DEPLOYED[key] || "");
    clearTxStatus();
  }, [clearTxStatus]);

  const refresh = useCallback(async () => {
    if (!tokenAddr || !isAddress(tokenAddr)) { setInfoError("Invalid token address"); return; }
    if (!account) { setInfoError("Please connect MetaMask first."); return; }
    setInfoError(null); setLoading(true);
    try {
      const tok = await getTokenInfo(tokenAddr, account);
      setSymbol(tok.symbol); setDecimals(tok.decimals);
      setBalance(tok.balance); setDepositBalance(tok.depositBalance); setBankBalance(tok.bankBalance);
      try { setAllowance(await getAllowance(tokenAddr, account)); } catch { setAllowance(null); }
    } catch (e) {
      setInfoError(e.message || "Failed to read token info.");
      setSymbol(""); setDecimals(null); setBalance(null); setDepositBalance(null); setBankBalance(null); setAllowance(null);
    } finally { setLoading(false); }
  }, [tokenAddr, account, getTokenInfo, getAllowance]);

  const mkAction = (fn) => async (...args) => { try { await fn(...args); await refresh(); } catch { /* in txStatus */ } };

  const [depAmt, setDepAmt] = useState("");
  const [permitAmt, setPermitAmt] = useState("");
  const [wdrwAmt, setWdrwAmt] = useState("");

  const canDeposit = () => tokenAddr && isAddress(tokenAddr) && depAmt && !isNaN(depAmt) && Number(depAmt) > 0 && decimals;
  const canPermit  = () => tokenAddr && isAddress(tokenAddr) && permitAmt && !isNaN(permitAmt) && Number(permitAmt) > 0 && decimals;
  const canWithdraw = () => tokenAddr && isAddress(tokenAddr) && wdrwAmt && !isNaN(wdrwAmt) && Number(wdrwAmt) > 0 && decimals;

  return (
    <>
      {/* ── Contract Config ── */}
      <div className="card">
        <div className="card-header">📄 TokenBank Contract</div>
        <div className="network-select">
          {["31337","11155111"].map(k => (
            <span key={k} className={`chip ${network === k ? "active" : ""}`} onClick={() => onNetwork(k)}>{k === "31337" ? "Anvil Local" : "Sepolia"}</span>
          ))}
        </div>
        <div className="form-group">
          <label className="form-label">TokenBank Address</label>
          <input className="input" value={bankAddress} onChange={e => { setBankAddress(e.target.value); clearTxStatus(); }} placeholder="0x…" spellCheck={false} />
        </div>
      </div>

      {/* ── Token Info ── */}
      <div className="card">
        <div className="card-header">🪙 Token</div>
        <div className="form-group">
          <label className="form-label">ERC20 Token Address</label>
          <div className="input-row">
            <input className="input" value={tokenAddr} onChange={e => { setTokenAddr(e.target.value); setSymbol(""); setDecimals(null); setBalance(null); setDepositBalance(null); setAllowance(null); setInfoError(null); }} placeholder="0x…" spellCheck={false} />
            <button className="btn btn-secondary btn-sm" disabled={!isAddress(tokenAddr) || loading || !account} onClick={refresh}>{loading ? "…" : "🔍 Load"}</button>
          </div>
        </div>
        {infoError && <div style={{ color: "#fca5a5", fontSize: "0.8rem", marginBottom: "0.5rem" }}>❌ {infoError}</div>}
        {!infoError && !account && <div style={{ color: "#fbbf24", fontSize: "0.8rem", marginBottom: "0.5rem" }}>⚠ Connect MetaMask first, then click Load.</div>}
        {symbol && Number(decimals) >= 0 && (
          <div style={{ marginTop: "0.75rem" }}>
            <InfoRow label="Symbol" value={symbol} />
            <InfoRow label="Decimals" value={String(decimals)} />
            <InfoRow label="Wallet Balance" value={balance != null ? formatUnits(balance, decimals) : "…"} />
            <InfoRow label="Bank Deposit" value={depositBalance != null ? formatUnits(depositBalance, decimals) : "…"} mono highlight />
            <InfoRow label="Bank Balance" value={bankBalance != null ? formatUnits(bankBalance, decimals) : "…"} mono />
            {allowance != null && <InfoRow label="Allowance" value={formatUnits(allowance, decimals)} />}
          </div>
        )}
      </div>

      {/* ── Deposit ── */}
      <div className="card">
        <div className="card-header">💰 Deposit</div>
        <p style={{ color: "#94a3b8", fontSize: "0.8rem", marginBottom: "0.75rem" }}>Approve TokenBank to spend your tokens, then deposit them.</p>
        <div className="form-group">
          <label className="form-label">Amount ({symbol || "TOKEN"})</label>
          <input className="input" value={depAmt} onChange={e => setDepAmt(e.target.value)} placeholder="0.0" spellCheck={false} />
        </div>
        <button className="btn btn-primary" disabled={!canDeposit() || txPending} onClick={() => { if (canDeposit()) { mkAction(deposit)(tokenAddr, parseUnits(depAmt, decimals)); setDepAmt(""); } }}>{txPending ? "⏳ Processing…" : "💰 Approve & Deposit"}</button>
        <TxStatus status={txStatus} />
      </div>

      {/* ── Permit Deposit ── */}
      <div className="card">
        <div className="card-header">✍️ Permit Deposit (Gasless)</div>
        <p style={{ color: "#94a3b8", fontSize: "0.8rem", marginBottom: "0.75rem" }}>Sign EIP-2612 permit off-chain, then deposit in one tx. No separate approve.
          {account && <span style={{ display: "block", marginTop: "0.25rem", color: "#6ee7b7" }}>Signer: {account.slice(0,6)+"…"+account.slice(-4)}</span>}
        </p>
        <div className="form-group">
          <label className="form-label">Amount ({symbol || "TOKEN"})</label>
          <input className="input" value={permitAmt} onChange={e => setPermitAmt(e.target.value)} placeholder="0.0" spellCheck={false} />
        </div>
        <button className="btn btn-primary" disabled={!canPermit() || txPending} onClick={() => { if (canPermit()) { mkAction(permitDeposit)(tokenAddr, parseUnits(permitAmt, decimals)); setPermitAmt(""); } }}>{txPending ? "⏳ Processing…" : "✍️ Sign & Deposit"}</button>
        <TxStatus status={txStatus} />
      </div>

      {/* ── Withdraw ── */}
      <div className="card">
        <div className="card-header">🏦 Withdraw</div>
        <div className="form-group">
          <label className="form-label">Amount ({symbol || "TOKEN"})</label>
          <input className="input" value={wdrwAmt} onChange={e => setWdrwAmt(e.target.value)} placeholder="0.0" spellCheck={false} />
        </div>
        <button className="btn btn-danger" disabled={!canWithdraw() || txPending} onClick={() => { if (canWithdraw()) { mkAction(withdraw)(tokenAddr, parseUnits(wdrwAmt, decimals)); setWdrwAmt(""); } }}>{txPending ? "⏳ Processing…" : "🏦 Withdraw"}</button>
        <TxStatus status={txStatus} />
      </div>
    </>
  );
}

function InfoRow({ label, value, mono, highlight }) {
  return (
    <div className="info-row">
      <span className="info-label">{label}</span>
      <span className="info-value" style={{ fontFamily: mono || highlight ? "'SF Mono','Fira Code',monospace" : undefined, color: highlight ? "#6ee7b7" : undefined, fontWeight: highlight ? 600 : undefined }}>{value}</span>
    </div>
  );
}
