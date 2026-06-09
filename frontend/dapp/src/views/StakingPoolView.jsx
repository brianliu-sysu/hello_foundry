import { useState, useEffect, useCallback, useRef } from "react";
import { useStakingPool } from "../hooks/useStakingPool";
import { STAKINGPOOL_DEPLOYED, KTKOKEN_DEPLOYED, WETH9_DEPLOYED, LENDINGMARKET_DEPLOYED, shortenHash } from "../utils/contract";
import { DEFAULT_NETWORK, NETWORK_LABELS } from "../config";
import TxStatus from "../components/TxStatus";

function InfoRow({ label, children }) {
  return (
    <div className="info-row">
      <span className="info-label">{label}</span>
      <span className="info-value">{children}</span>
    </div>
  );
}

export default function StakingPoolView({ signer, account, chainId }) {
  const networkKey = String(chainId ?? DEFAULT_NETWORK);
  const networkLabel = NETWORK_LABELS[networkKey] || `Chain ${networkKey}`;
  const prevNet = useRef(networkKey);

  const poolAddr   = STAKINGPOOL_DEPLOYED[networkKey] || "";
  const kkAddr     = KTKOKEN_DEPLOYED[networkKey] || "";
  const wethAddr   = WETH9_DEPLOYED[networkKey] || "";
  const marketAddr = LENDINGMARKET_DEPLOYED[networkKey] || "";

  const hook = useStakingPool(signer, poolAddr);

  // ── Amounts ──
  const [stakeAmt,    setStakeAmt]    = useState("");
  const [withdrawAmt, setWithdrawAmt] = useState("");

  // ── Pool data ──
  const [poolData,  setPoolData]  = useState(null);
  const [kkInfo,    setKkInfo]    = useState(null);
  const [ethBalance, setEthBalance] = useState(null);

  // ── Load ETH balance ──
  useEffect(() => {
    if (!signer || !account) { setEthBalance(null); return; }
    let active = true;
    (async () => {
      try {
        // In ethers v6, signer.provider is the BrowserProvider / JsonRpcProvider
        const b = await signer.provider.getBalance(account);
        if (active) setEthBalance(b);
      } catch (err) {
        console.error("StakingPoolView: getBalance failed", err);
        if (active) setEthBalance(null);
      }
    })();
    return () => { active = false; };
  }, [signer, account]);

  // ── Load pool data ──
  const loadPoolData = useCallback(async () => {
    if (!hook.poolC) { setPoolData(null); return; }
    setPoolData(await hook.getPoolData(account));
  }, [hook, account]);

  // ── Load KK info ──
  useEffect(() => {
    if (!kkAddr) { setKkInfo(null); return; }
    let active = true;
    hook.getKKInfo(poolAddr, kkAddr).then(info => { if (active) setKkInfo(info); });
    return () => { active = false; };
  }, [kkAddr, poolAddr, hook]);

  useEffect(() => { loadPoolData(); }, [loadPoolData]);

  // ── Network switch reset ──
  useEffect(() => {
    if (prevNet.current !== networkKey) {
      prevNet.current = networkKey;
      setStakeAmt(""); setWithdrawAmt(""); setPoolData(null); setKkInfo(null); setEthBalance(null);
    }
  }, [networkKey]);

  // ── Refresh ──
  const refresh = async () => {
    setPoolData(await hook.getPoolData(account));
    if (signer && account) {
      try { setEthBalance(await signer.provider.getBalance(account)); } catch {}
    }
    if (kkAddr) {
      const info = await hook.getKKInfo(poolAddr, kkAddr);
      setKkInfo(info);
    }
  };

  const mk = (fn) => async () => {
    try { await fn(); } catch {}
    await refresh();
  };

  // ── Safe human → wei (string-based, no float precision loss) ──
  const toWei = (v) => {
    if (!v) return 0n;
    const trimmed = v.trim();
    if (!trimmed || trimmed === "0") return 0n;
    const [w, f = ""] = trimmed.split(".");
    const frac = (f + "0".repeat(18)).slice(0, 18);
    return BigInt(w || "0") * (10n ** 18n) + BigInt(frac || "0");
  };

  // ── BigInt-safe ETH formatter (no Number() conversion) ──
  const fmtETH = (wei) => {
    if (wei == null) return "—";
    try {
      const dec = 10n ** 18n;
      const whole = wei / dec;
      const frac = (wei % dec).toString().padStart(18, "0").slice(0, 6);
      return whole.toString() + "." + frac;
    } catch { return "—"; }
  };

  const fmtKK = (wei) => {
    if (wei == null) return "—";
    try {
      const dec = 10n ** 18n;
      const whole = wei / dec;
      const frac = (wei % dec).toString().padStart(18, "0").slice(0, 2);
      // Format whole part with commas using regex
      const wholeStr = whole.toString().replace(/\B(?=(\d{3})+(?!\d))/g, ",");
      const fracClean = frac.replace(/0+$/, "");
      return fracClean ? `${wholeStr}.${fracClean}` : wholeStr;
    } catch { return "—"; }
  };

  // ==========================================================================

  if (!poolAddr) {
    return (
      <div className="card">
        <div className="card-header">🥩 Staking Pool</div>
        <p style={{ color: "#fbbf24" }}>StakingPool not deployed on {networkLabel} yet.</p>
      </div>
    );
  }

  return (
    <div>
      {/* ── Header ── */}
      <div className="card">
        <div className="card-header">🥩 Staking Pool — {networkLabel}</div>
        <InfoRow label="Pool">{shortenHash(poolAddr)}</InfoRow>
        <InfoRow label="KK Token">{shortenHash(kkAddr)}</InfoRow>
        <InfoRow label="WETH">{shortenHash(wethAddr)}</InfoRow>
        <InfoRow label="LendingMarket">{shortenHash(marketAddr)}</InfoRow>
      </div>

      <TxStatus status={hook.txStatus} />

      {/* ── Pool Stats ── */}
      {poolData && (
        <div className="card" style={{ background: "rgba(99,102,241,0.08)" }}>
          <div className="card-header" style={{ fontSize: "14px" }}>📊 Pool Stats</div>
          <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: "6px", fontSize: "13px", color: "#cbd5e1" }}>
            <InfoRow label="Total Staked">{fmtETH(poolData.totalStaked)} ETH</InfoRow>
            <InfoRow label="Total KK Minted">{fmtKK(poolData.totalRewardsMinted)} KK</InfoRow>
            <InfoRow label="Pool WETH in Lending">{fmtETH(poolData.poolWeth)} WETH</InfoRow>
            <InfoRow label="Interest Earned">{fmtETH(poolData.interest)} ETH</InfoRow>
            <InfoRow label="Last Update Block">#{poolData.lastBlock?.toString()}</InfoRow>
            <InfoRow label="Reward Rate">10 KK / block</InfoRow>
          </div>
        </div>
      )}

      {/* ── Your Position ── */}
      {signer && poolData && (
        <div className="card" style={{ background: "rgba(34,197,94,0.06)" }}>
          <div className="card-header" style={{ fontSize: "14px" }}>👤 Your Position</div>
          <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: "8px", fontSize: "13px", color: "#cbd5e1" }}>
            <InfoRow label="Staked">
              <strong>{fmtETH(poolData.userStaked)} ETH</strong>
            </InfoRow>
            <InfoRow label="Share">{poolData.totalStaked > 0n
              ? ((Number(poolData.userStaked * 10000n / poolData.totalStaked)) / 100).toFixed(2) + "%"
              : "—"}</InfoRow>
            <InfoRow label="Earned KK">
              <strong style={{ color: "#fbbf24" }}>{fmtKK(poolData.userEarned)} KK</strong>
            </InfoRow>
            <InfoRow label="KK Balance (wallet)">
              {kkInfo?.balanceOf != null ? fmtKK(kkInfo.balanceOf) : "—"} KK
            </InfoRow>
            <InfoRow label="ETH Balance (wallet)">
              {ethBalance != null ? fmtETH(ethBalance) : "—"} ETH
            </InfoRow>
          </div>
        </div>
      )}

      {/* ═══ STAKE ═══ */}
      {signer && (
        <div className="card">
          <div className="card-header">💰 Stake ETH</div>
          <p style={{ fontSize: "12px", color: "#94a3b8", marginBottom: "10px" }}>
            ETH will be wrapped into WETH and deposited into LendingMarket automatically.
          </p>
          <div className="form-group">
            <label className="form-label">ETH Amount</label>
            <input className="input" type="number" step="any" placeholder="0.0" value={stakeAmt}
              onChange={e => setStakeAmt(e.target.value)} />
            <div style={{ fontSize: "12px", color: "#94a3b8", marginTop: "4px" }}>
              Balance: {(() => {
                // Always show balance text, with loading state
                if (ethBalance != null) return <>{fmtETH(ethBalance)} ETH</>;
                if (signer && account) return <>loading…</>;
                return <>—</>;
              })()}
              <span style={{ cursor: "pointer", color: "#6366f1", marginLeft: "8px" }}
                onClick={() => setStakeAmt(ethBalance != null ? fmtETH(ethBalance) : "0")}>MAX</span>
            </div>
          </div>
          <button className="btn" style={{ marginTop: "10px" }}
            onClick={mk(() => hook.stake(toWei(stakeAmt)))}
            disabled={hook.txPending || !stakeAmt || parseFloat(stakeAmt) <= 0}>
            Stake
          </button>
        </div>
      )}

      {/* ═══ WITHDRAW ═══ */}
      {signer && poolData && poolData.userStaked > 0n && (
        <div className="card">
          <div className="card-header">💸 Withdraw Stake</div>
          <div className="form-group">
            <label className="form-label">ETH Amount to Withdraw</label>
            <input className="input" type="number" step="any" placeholder="0.0" value={withdrawAmt}
              onChange={e => setWithdrawAmt(e.target.value)} />
            <div style={{ fontSize: "12px", color: "#94a3b8", marginTop: "4px" }}>
              Staked: {fmtETH(poolData.userStaked)} ETH
              <span style={{ cursor: "pointer", color: "#6366f1", marginLeft: "8px" }}
                onClick={() => setWithdrawAmt(fmtETH(poolData.userStaked))}>MAX</span>
            </div>
          </div>
          <button className="btn" style={{ marginTop: "10px" }}
            onClick={mk(() => hook.withdraw(toWei(withdrawAmt)))}
            disabled={hook.txPending || !withdrawAmt || parseFloat(withdrawAmt) <= 0}>
            Withdraw
          </button>
          <p style={{ fontSize: "12px", color: "#94a3b8", marginTop: "8px" }}>
            💡 You'll receive ETH back, including proportional LendingMarket yield.
          </p>
        </div>
      )}

      {/* ═══ CLAIM KK ═══ */}
      {signer && (
        <div className="card">
          <div className="card-header">🎁 Claim KK Rewards</div>
          <InfoRow label="Pending KK">{poolData?.userEarned != null ? fmtKK(poolData.userEarned) : "—"} KK</InfoRow>
          <button className="btn" style={{ marginTop: "10px" }}
            onClick={mk(() => hook.claimReward())}
            disabled={hook.txPending || !poolData || poolData.userEarned <= 0n}>
            Claim Rewards
          </button>
        </div>
      )}

      {/* ═══ REFRESH ═══ */}
      <div style={{ marginTop: "10px" }}>
        <button className="btn btn-secondary" onClick={refresh} disabled={hook.txPending}>
          🔄 Refresh
        </button>
      </div>
    </div>
  );
}
