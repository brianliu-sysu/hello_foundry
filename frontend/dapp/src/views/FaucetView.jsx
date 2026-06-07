import { useState, useEffect, useRef } from "react";
import { isAddress, formatEther, formatUnits } from "ethers";
import { useFaucet } from "../hooks/useFaucet";
import { FAUCET_DEPLOYED, BRIANICOTOKEN_DEPLOYED } from "../utils/contract";
import { DEFAULT_NETWORK, NETWORK_LABELS } from "../config";
import TxStatus from "../components/TxStatus";
import AddressLabel from "../components/AddressLabel";

/// 格式化冷却倒计时
function formatCooldown(lastTimestamp) {
  if (!lastTimestamp || lastTimestamp === 0n) return null; // 从未提过款
  const now = Math.floor(Date.now() / 1000);
  const last = Number(lastTimestamp);
  const available = last + 86400; // +1 day
  if (now >= available) return { ready: true, text: "✅ Available now" };
  const secs = available - now;
  const h = Math.floor(secs / 3600);
  const m = Math.floor((secs % 3600) / 60);
  return { ready: false, text: `⏳ ${h}h ${m}m remaining` };
}

export default function FaucetView({ signer, account, chainId }) {
  const networkKey = chainId != null ? String(chainId) : DEFAULT_NETWORK;
  const networkLabel = NETWORK_LABELS[networkKey] || `Chain ${networkKey}`;

  const [faucetAddr, setFaucetAddr] = useState(FAUCET_DEPLOYED[networkKey] || "");

  const prevNetwork = useRef(networkKey);
  useEffect(() => {
    if (prevNetwork.current !== networkKey) {
      prevNetwork.current = networkKey;
      setFaucetAddr(FAUCET_DEPLOYED[networkKey] || "");
      clearTxStatus();
    }
  }, [networkKey]); // eslint-disable-line react-hooks/exhaustive-deps

  const {
    faucetAddressOk,
    txStatus, txPending, clearTxStatus,
    faucetOwner, faucetPaused, faucetETHBalance,
    tokenAddr, maxTokenWithdraw, tokenInfo,
    statsLoading, refreshFaucet,
    getCooldown,
    withdrawETH, withdrawToken,
    setToken, adminWithdrawToken, pause, unpause,
  } = useFaucet(signer, faucetAddr);

  // ── 冷却状态（按当前用户） ──
  const [cooldowns, setCooldowns] = useState({ eth: null, token: null, loading: false });
  useEffect(() => {
    if (faucetAddressOk && account) {
      getCooldown(account).then(cd => setCooldowns({ eth: formatCooldown(cd.eth), token: formatCooldown(cd.token), loading: false }));
    }
  }, [faucetAddressOk, account, getCooldown, txStatus]); // tx 完成后也会刷新

  // ── ETH withdraw 状态 ──
  const [ethAmount, setEthAmount] = useState("");
  const [ethTo, setEthTo] = useState("");
  useEffect(() => { if (account && !ethTo) setEthTo(account); }, [account]); // eslint-disable-line react-hooks/exhaustive-deps

  // ── Token withdraw 状态 ──
  const [tokenAmount, setTokenAmount] = useState("");

  // ── Owner setToken 状态 ──
  const [newTokenAddr, setNewTokenAddr] = useState(BRIANICOTOKEN_DEPLOYED[networkKey] || "");

  const isOwner = account && faucetOwner && account.toLowerCase() === faucetOwner.toLowerCase();
  const ethLimit = 0.01; // ether

  return (
    <>
      {/* ── Faucet Config ── */}
      <div className="card">
        <div className="card-header" style={{ display: "flex", justifyContent: "space-between", alignItems: "center" }}>
          <span>🚰 Faucet Contract</span>
          <span className="chip active" style={{ fontSize: "0.7rem" }}>🟢 {networkLabel}</span>
        </div>
        <div className="form-group">
          <label className="form-label">Faucet Address</label>
          <input className="input" value={faucetAddr} onChange={e => { setFaucetAddr(e.target.value); clearTxStatus(); }} placeholder="0x…" spellCheck={false} />
        </div>
        {faucetAddressOk && (
          <button className="btn btn-secondary btn-sm" disabled={statsLoading} onClick={refreshFaucet} style={{ marginTop: "0.25rem" }}>
            {statsLoading ? "…" : "🔄 Refresh"}
          </button>
        )}
      </div>

      {/* ── Faucet Status ── */}
      {faucetAddressOk && (
        <div className="card">
          <div className="card-header">📊 Faucet Status</div>
          {statsLoading ? (
            <p style={{ color: "#94a3b8", fontSize: "0.8rem" }}>Loading…</p>
          ) : (
            <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: "0.75rem", fontSize: "0.85rem" }}>
              <div>
                <div style={{ color: "#64748b", fontSize: "0.72rem", marginBottom: "0.15rem" }}>Owner</div>
                {faucetOwner ? <AddressLabel address={faucetOwner} mono /> : <span style={{ color: "#94a3b8" }}>—</span>}
              </div>
              <div>
                <div style={{ color: "#64748b", fontSize: "0.72rem", marginBottom: "0.15rem" }}>Paused</div>
                <span style={{ color: faucetPaused ? "#fca5a5" : "#6ee7b7", fontWeight: 600 }}>
                  {faucetPaused ? "⏸️ Paused" : "▶️ Running"}
                </span>
              </div>
              <div>
                <div style={{ color: "#64748b", fontSize: "0.72rem", marginBottom: "0.15rem" }}>ETH Balance</div>
                <div style={{ color: "#e2e8f0", fontFamily: "'SF Mono','Fira Code',monospace" }}>
                  {faucetETHBalance != null ? `${formatEther(faucetETHBalance)} ETH` : "—"}
                </div>
              </div>
              <div>
                <div style={{ color: "#64748b", fontSize: "0.72rem", marginBottom: "0.15rem" }}>Token</div>
                {tokenAddr ? (
                  <div>
                    <AddressLabel address={tokenAddr} mono short />
                    {tokenInfo && (
                      <span style={{ color: "#94a3b8", fontSize: "0.7rem", marginLeft: "0.25rem" }}>
                        ({formatUnits(tokenInfo.balance, tokenInfo.decimals)} {tokenInfo.symbol})
                      </span>
                    )}
                  </div>
                ) : (
                  <span style={{ color: "#64748b" }}>Not set</span>
                )}
              </div>
              <div>
                <div style={{ color: "#64748b", fontSize: "0.72rem", marginBottom: "0.15rem" }}>ETH Limit / Withdraw</div>
                <span style={{ color: "#e2e8f0" }}>{ethLimit} ETH</span>
              </div>
              <div>
                <div style={{ color: "#64748b", fontSize: "0.72rem", marginBottom: "0.15rem" }}>Token Limit / Withdraw</div>
                <span style={{ color: "#e2e8f0" }}>
                  {maxTokenWithdraw != null ? `${formatUnits(maxTokenWithdraw, 18)} tokens` : "—"}
                </span>
              </div>
            </div>
          )}
          {isOwner && (
            <div style={{ marginTop: "0.5rem", color: "#fcd34d", fontSize: "0.75rem" }}>👑 You are the owner — admin controls unlocked.</div>
          )}
        </div>
      )}

      {/* ── ETH Withdraw ── */}
      {faucetAddressOk && (
        <div className="card">
          <div className="card-header">💧 Withdraw ETH</div>
          <p style={{ color: "#94a3b8", fontSize: "0.8rem", marginBottom: "0.75rem" }}>
            Max {ethLimit} ETH per day per address.
          </p>
          {cooldowns.eth && (
            <div style={{ color: cooldowns.eth.ready ? "#6ee7b7" : "#fbbf24", fontSize: "0.78rem", marginBottom: "0.5rem" }}>
              {cooldowns.eth.text}
            </div>
          )}
          <div className="form-group">
            <label className="form-label">Recipient</label>
            <input className="input" value={ethTo} onChange={e => setEthTo(e.target.value)}
              placeholder={account ? `Your wallet: ${account.slice(0, 6)}…${account.slice(-4)}` : "0x…"} spellCheck={false} />
          </div>
          <div className="form-group">
            <label className="form-label">Amount (ETH)</label>
            <input className="input" value={ethAmount} onChange={e => setEthAmount(e.target.value)} placeholder={`Max ${ethLimit}`} spellCheck={false} />
          </div>
          {faucetPaused && (
            <div style={{ color: "#fca5a5", fontSize: "0.75rem", marginBottom: "0.5rem" }}>⚠️ Faucet is paused.</div>
          )}
          <button className="btn btn-primary"
            disabled={!ethTo || !isAddress(ethTo) || !ethAmount || isNaN(ethAmount) || Number(ethAmount) <= 0 || Number(ethAmount) > ethLimit || txPending || faucetPaused}
            onClick={async () => {
              await withdrawETH(BigInt(Math.floor(Number(ethAmount) * 1e18)), ethTo);
              setEthAmount("");
              if (account) { const cd = await getCooldown(account); setCooldowns({ ...cooldowns, eth: formatCooldown(cd.eth) }); }
            }}>
            {txPending ? "⏳ Processing…" : "💧 Withdraw ETH"}
          </button>
          <TxStatus status={txStatus} />
        </div>
      )}

      {/* ── Token Withdraw ── */}
      {faucetAddressOk && tokenAddr && (
        <div className="card">
          <div className="card-header">🪙 Withdraw Token</div>
          <p style={{ color: "#94a3b8", fontSize: "0.8rem", marginBottom: "0.75rem" }}>
            {tokenInfo ? `Max ${formatUnits(maxTokenWithdraw || 0n, tokenInfo.decimals)} ${tokenInfo.symbol} per day per address.` : "Max 10 tokens per day."}
            {" "}Balance: {tokenInfo ? `${formatUnits(tokenInfo.balance, tokenInfo.decimals)} ${tokenInfo.symbol}` : "..."}
          </p>
          {cooldowns.token && (
            <div style={{ color: cooldowns.token.ready ? "#6ee7b7" : "#fbbf24", fontSize: "0.78rem", marginBottom: "0.5rem" }}>
              {cooldowns.token.text}
            </div>
          )}
          <div className="form-group">
            <label className="form-label">Amount (tokens)</label>
            <input className="input" value={tokenAmount} onChange={e => setTokenAmount(e.target.value)}
              placeholder={`Max ${tokenInfo && maxTokenWithdraw ? formatUnits(maxTokenWithdraw, tokenInfo.decimals) : "10"}`} spellCheck={false} />
          </div>
          {faucetPaused && (
            <div style={{ color: "#fca5a5", fontSize: "0.75rem", marginBottom: "0.5rem" }}>⚠️ Faucet is paused.</div>
          )}
          <button className="btn btn-primary"
            disabled={!tokenAmount || isNaN(tokenAmount) || Number(tokenAmount) <= 0 || txPending || faucetPaused}
            onClick={async () => {
              const decimals = tokenInfo?.decimals || 18;
              const amountWei = BigInt(Math.floor(Number(tokenAmount) * 10 ** decimals));
              await withdrawToken(amountWei);
              setTokenAmount("");
              if (account) { const cd = await getCooldown(account); setCooldowns({ ...cooldowns, token: formatCooldown(cd.token) }); }
            }}>
            {txPending ? "⏳ Processing…" : "🪙 Withdraw Token"}
          </button>
          <TxStatus status={txStatus} />
        </div>
      )}

      {/* ── Owner Admin ── */}
      {faucetAddressOk && isOwner && (
        <>
          <div className="card" style={{ borderColor: "#fcd34d" }}>
            <div className="card-header" style={{ color: "#fcd34d" }}>👑 Owner Controls</div>

            {/* setToken */}
            <div style={{ marginBottom: "1rem" }}>
              <p style={{ color: "#94a3b8", fontSize: "0.8rem", marginBottom: "0.5rem" }}>
                Set the ERC20 token address for the Token Faucet.
              </p>
              <div className="form-group">
                <label className="form-label">Token Address</label>
                <div className="input-row">
                  <input className="input" value={newTokenAddr} onChange={e => setNewTokenAddr(e.target.value)} placeholder="0x…" spellCheck={false} />
                  <button className="btn btn-secondary btn-sm" disabled={!newTokenAddr || !isAddress(newTokenAddr) || txPending}
                    onClick={() => setToken(newTokenAddr)}>
                    Set Token
                  </button>
                </div>
              </div>
            </div>

            {/* adminWithdrawToken */}
            <div style={{ marginBottom: "1rem" }}>
              <p style={{ color: "#94a3b8", fontSize: "0.8rem", marginBottom: "0.5rem" }}>
                Withdraw all tokens from the Faucet back to your wallet.
                {tokenInfo && <span> Current: {formatUnits(tokenInfo.balance, tokenInfo.decimals)} {tokenInfo.symbol}</span>}
              </p>
              <button className="btn btn-danger btn-sm"
                disabled={!tokenAddr || txPending || (tokenInfo && tokenInfo.balance === 0n)}
                onClick={() => adminWithdrawToken()}>
                💰 Withdraw All Tokens
              </button>
            </div>

            {/* pause / unpause */}
            <div style={{ marginBottom: "0.25rem" }}>
              <p style={{ color: "#94a3b8", fontSize: "0.8rem", marginBottom: "0.5rem" }}>
                Toggle the Faucet pause state.
              </p>
              <div style={{ display: "flex", gap: "0.5rem" }}>
                <button className="btn btn-warning btn-sm" disabled={faucetPaused || txPending} onClick={() => pause()}>
                  ⏸️ Pause
                </button>
                <button className="btn btn-secondary btn-sm" disabled={!faucetPaused || txPending} onClick={() => unpause()}>
                  ▶️ Unpause
                </button>
              </div>
            </div>

            <TxStatus status={txStatus} />
          </div>
        </>
      )}
    </>
  );
}
