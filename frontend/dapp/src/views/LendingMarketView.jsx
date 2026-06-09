import { useState, useEffect, useCallback, useRef, useMemo } from "react";
import { Contract } from "ethers";
import { useLendingMarket } from "../hooks/useLendingMarket";
import { LENDINGMARKET_DEPLOYED, WETH9_DEPLOYED, WETH9_ABI, shortenHash } from "../utils/contract";
import { DEFAULT_NETWORK, NETWORK_LABELS } from "../config";
import TxStatus from "../components/TxStatus";

const RAY = BigInt("1000000000000000000000000000"); // 1e27
const BPS = 10000n;

function InfoRow({ label, children }) {
  return (
    <div className="info-row">
      <span className="info-label">{label}</span>
      <span className="info-value">{children}</span>
    </div>
  );
}

export default function LendingMarketView({ signer, account, chainId }) {
  const networkKey = String(chainId ?? DEFAULT_NETWORK);
  const networkLabel = NETWORK_LABELS[networkKey] || `Chain ${networkKey}`;
  const prevNet = useRef(networkKey);

  const marketAddr = LENDINGMARKET_DEPLOYED[networkKey] || "";
  const wethAddr    = WETH9_DEPLOYED[networkKey] || "";
  const hook = useLendingMarket(signer, marketAddr);

  const [tab, setTab] = useState("supply");

  // ── ETH balance (for WETH Supply) ──
  const [ethBalance, setEthBalance] = useState(null);
  useEffect(() => {
    if (!signer || !account) { setEthBalance(null); return; }
    let active = true;
    (async () => {
      try { const b = await signer.provider.getBalance(account); if (active) setEthBalance(b); }
      catch { if (active) setEthBalance(null); }
    })();
    return () => { active = false; };
  }, [signer, account]);
  const refreshEthBalance = useCallback(async () => {
    if (!signer || !account) return;
    try { setEthBalance(await signer.provider.getBalance(account)); } catch {}
  }, [signer, account]);

  // ── Reserve list + selected asset ──
  const [reservesList, setReservesList] = useState([]);
  const [selectedAsset, setSelectedAsset] = useState("");
  const [selectedTip, setSelectedTip] = useState(null);

  // ── Supply / Withdraw amounts ──
  const [supplyAmt, setSupplyAmt] = useState("");
  const [withdrawAmt, setWithdrawAmt] = useState("");

  // ── Borrow / Repay amounts ──
  const [borrowAmt, setBorrowAmt] = useState("");
  const [repayAmt, setRepayAmt] = useState("");

  // ── Flash Loan ──
  const [flReceiver, setFlReceiver] = useState("");
  const [flAmount, setFlAmount] = useState("");

  // ── Dashboard ──
  const [dashboard, setDashboard] = useState(null); // account data
  const [userBalances, setUserBalances] = useState({});

  // ── Reserve detail card ──
  const [reserveInfo, setReserveInfo] = useState(null);

  // ── Owner check ──
  const [isOwner, setIsOwner] = useState(false);

  // ── Collateral check ──
  const [collateralOn, setCollateralOn] = useState(false);

  // ── Admin form state ──
  const [adminAsset, setAdminAsset] = useState("");
  const [adminCF, setAdminCF] = useState("7500");
  const [adminLT, setAdminLT] = useState("8500");
  const [adminLB, setAdminLB] = useState("10500");
  const [adminFLP, setAdminFLP] = useState("9");
  const [adminPrice, setAdminPrice] = useState("1");
  const [adminOptUtil, setAdminOptUtil] = useState("0.8");
  const [adminBaseRate, setAdminBaseRate] = useState("0.02");
  const [adminSlope1, setAdminSlope1] = useState("0.06");
  const [adminSlope2, setAdminSlope2] = useState("3");

  // ── Safe human-to-wei conversion (avoids JS float precision loss) ──
  const toWei = useCallback((humanAmount, decimals = 18) => {
    if (!humanAmount || parseFloat(humanAmount) <= 0) return 0n;
    const [whole, frac = ""] = humanAmount.split(".");
    const padded = (frac + "0".repeat(decimals)).slice(0, decimals);
    return BigInt(whole) * (BigInt(10) ** BigInt(decimals)) + BigInt(padded || "0");
  }, []);

  // ── Derived ──
  const isWETH = selectedAsset.toLowerCase() === wethAddr?.toLowerCase();

  // ── Available-to-borrow for selected asset in borrow tab ──
  const availableToBorrow = useMemo(() => {
    if (!dashboard || !reserveInfo || !reserveInfo.price || reserveInfo.price <= 0n) return null;
    // Convert USD (1e8 price scale) to token amount:
    //   borrowableTokens = availableBorrowsUSD * 1e8 / price
    const availUSD = dashboard.availableBorrowsUSD;
    if (availUSD <= 0n) return { assetMax: 0n, poolMax: reserveInfo.availableLiquidity };
    const assetMax = (availUSD * BigInt(1e8)) / reserveInfo.price;
    return {
      assetMax,
      poolMax: reserveInfo.availableLiquidity,
    };
  }, [dashboard, reserveInfo]);

  // ── Helpers ──
  const formatToken = (v, decimals = 18) => {
    try {
      const n = Number(v) / 10 ** decimals;
      if (n < 0.0001 && n > 0) return "<0.0001";
      return n.toLocaleString(undefined, { maximumSignificantDigits: 6 });
    } catch { return "—"; }
  };

  const formatPercent = (ray, decimals = 2) => {
    try {
      const pct = (Number(ray) / 1e25) * 100;
      return pct.toFixed(decimals) + "%";
    } catch { return "—"; }
  };

  const formatRay = (ray) => formatPercent(ray, 2);

  // ── Load reserves ──
  const loadReserves = useCallback(async () => {
    if (!hook.marketC) return;
    const list = await hook.getReservesList();
    setReservesList(list);
    if (list.length > 0 && !selectedAsset) {
      setSelectedAsset(list[0]);
    }
  }, [hook.marketC]);

  useEffect(() => { loadReserves(); }, [loadReserves]);

  // ── Load selected token info ──
  useEffect(() => {
    if (!selectedAsset || !signer) { setSelectedTip(null); return; }
    let active = true;
    hook.getTokenInfo(selectedAsset).then(info => { if (active) setSelectedTip(info); });
    return () => { active = false; };
  }, [selectedAsset, signer, hook]);

  // ── Load reserve detail ──
  const loadReserveInfo = useCallback(async () => {
    if (!selectedAsset || !hook.marketC) { setReserveInfo(null); return; }
    try {
      const [r, borrowRate, supplyRate] = await Promise.all([
        hook.getReserve(selectedAsset),
        hook.getCurrentBorrowRate(selectedAsset),
        hook.getCurrentSupplyRate(selectedAsset),
      ]);
      // ethers v6 Result — use numeric index, not spread
      setReserveInfo({
        liquidityIndex:          r[0],
        borrowIndex:             r[1],
        totalLiquidity:          r[2],
        totalDebt:               r[3],
        lastUpdateTimestamp:     r[4],
        optimalUtilizationRate:  r[5],
        baseBorrowRate:          r[6],
        slope1:                  r[7],
        slope2:                  r[8],
        collateralFactor:        r[9],
        liquidationThreshold:    r[10],
        liquidationBonus:        r[11],
        flashLoanPremium:        r[12],
        price:                   r[13],
        isActive:                r[14],
        borrowRate,
        supplyRate,
        availableLiquidity: r[2] > r[3] ? r[2] - r[3] : 0n,
        utilization: r[2] > 0n ? (r[3] * RAY) / r[2] : 0n,
      });
    } catch { setReserveInfo(null); }
  }, [selectedAsset, hook]);

  useEffect(() => { loadReserveInfo(); }, [loadReserveInfo]);

  // ── Load user balances for selected asset ──
  useEffect(() => {
    if (!account || !selectedAsset || !hook.marketC) { setUserBalances({}); return; }
    let active = true;
    hook.getUserBalances(account, selectedAsset).then(b => {
      if (active) setUserBalances(b);
    });
    return () => { active = false; };
  }, [account, selectedAsset, hook]);

  // ── Load collateral state ──
  useEffect(() => {
    if (!hook.marketC || !account || !selectedAsset) { setCollateralOn(false); return; }
    let active = true;
    hook.marketC.isUsingAsCollateral(account, selectedAsset).then(v => {
      if (active) setCollateralOn(v);
    });
    return () => { active = false; };
  }, [account, selectedAsset, hook]);

  // ── Owner check ──
  useEffect(() => {
    if (!hook.marketC || !account) { setIsOwner(false); return; }
    let active = true;
    hook.getOwner().then(o => {
      if (active) setIsOwner(o?.toLowerCase() === account.toLowerCase());
    });
    return () => { active = false; };
  }, [hook.marketC, account, hook]);

  // ── Load dashboard ──
  const loadDashboard = useCallback(async () => {
    if (!hook.marketC || !account) { setDashboard(null); return; }
    try {
      const d = await hook.getUserAccountData(account);
      setDashboard(d);
    } catch { setDashboard(null); }
  }, [hook, account]);

  useEffect(() => { if (tab === "dashboard" || tab === "borrow") loadDashboard(); }, [tab, account, hook]);

  // ── Network switch ──
  useEffect(() => {
    if (prevNet.current !== networkKey) {
      prevNet.current = networkKey;
      setReservesList([]); setSelectedAsset(""); setReserveInfo(null);
      setSupplyAmt(""); setWithdrawAmt(""); setBorrowAmt(""); setRepayAmt("");
      setFlReceiver(""); setFlAmount(""); setDashboard(null); setUserBalances({});
      setEthBalance(null);
    }
  }, [networkKey]);

  // ── Actions ──
  const refreshAfterAction = async () => {
    await loadReserveInfo();
    await loadReserves();
    if (account && selectedAsset) {
      const b = await hook.getUserBalances(account, selectedAsset);
      setUserBalances(b);
    }
    await loadDashboard();
  };

  const mkAction = (fn) => async () => {
    try { await fn(); } catch {}
    await refreshAfterAction();
  };

  const max = (balWei, decimals = 18) => {
    if (balWei == null) return "0";
    try {
      // BigInt division for safety (Number() loses precision > 2^53)
      const dec = BigInt(10) ** BigInt(decimals);
      const whole = balWei / dec;
      const frac = balWei % dec;
      const fracStr = frac.toString().padStart(decimals, "0").slice(0, 6);
      return whole.toString() + "." + fracStr;
    } catch { return "0"; }
  };

  // ── Click MAX for supply input (WETH uses ETH balance, others use token balance)
  const supplyMax = useCallback(() => {
    if (!selectedTip) return;
    if (isWETH) {
      if (ethBalance && ethBalance > 0n) {
        const dec = BigInt(10) ** 18n;
        const whole = ethBalance / dec;
        const frac = (ethBalance % dec).toString().padStart(18, "0").slice(0, 6);
        setSupplyAmt(whole.toString() + "." + frac);
      }
    } else {
      if (selectedTip.balanceOf && selectedTip.balanceOf > 0n) {
        setSupplyAmt(max(selectedTip.balanceOf, selectedTip.decimals));
      }
    }
  }, [isWETH, ethBalance, selectedTip]);

  // ==========================================================================
  // RENDER
  // ==========================================================================

  if (!marketAddr) {
    return (
      <div className="card">
        <div className="card-header">🏦 Lending Market</div>
        <p style={{ color: "#fbbf24" }}>LendingMarket not deployed on {networkLabel} yet. Run the deploy script first.</p>
      </div>
    );
  }

  return (
    <div>
      {/* ── Header ── */}
      <div className="card">
        <div className="card-header">🏦 Lending Market — {networkLabel}</div>
        <InfoRow label="Contract">{shortenHash(marketAddr)}</InfoRow>
      </div>

      <TxStatus status={hook.txStatus} />

      {/* ── Tabs ── */}
      <div className="tabs">
        {[
          { key: "supply",    label: "💰 Supply / Withdraw" },
          { key: "borrow",    label: "💳 Borrow / Repay" },
          { key: "flashloan", label: "⚡ Flash Loan" },
          { key: "dashboard", label: "📊 Dashboard" },
          ...(isOwner ? [{ key: "admin", label: "🔧 Admin" }] : []),
        ].map(t => (
          <button key={t.key} className={`tab ${tab === t.key ? "active" : ""}`} onClick={() => setTab(t.key)}>
            {t.label}
          </button>
        ))}
      </div>

      {/* ── Asset Selector (shared) ── */}
      {tab !== "dashboard" && (
        <div className="card">
          <div className="card-header">🪙 Select Asset</div>
          <div style={{ display: "flex", gap: "8px", flexWrap: "wrap" }}>
            {reservesList.map(a => (
              <button key={a}
                className={`tab ${selectedAsset.toLowerCase() === a.toLowerCase() ? "active" : ""}`}
                onClick={() => setSelectedAsset(a)}>
                {shortenHash(a)}
              </button>
            ))}
          </div>
        </div>
      )}

      {/* ── Reserve Info Card ── */}
      {reserveInfo && tab !== "dashboard" && (
        <div className="card" style={{ background: "rgba(99,102,241,0.08)" }}>
          <div className="card-header" style={{ fontSize: "14px" }}>
            📋 {selectedTip?.symbol ?? shortenHash(selectedAsset)} Reserve
          </div>
          <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: "6px", fontSize: "13px", color: "#cbd5e1" }}>
            <InfoRow label="Total Liquidity">{formatToken(reserveInfo.totalLiquidity, selectedTip?.decimals ?? 18)} {selectedTip?.symbol}</InfoRow>
            <InfoRow label="Total Debt">{formatToken(reserveInfo.totalDebt, selectedTip?.decimals ?? 18)} {selectedTip?.symbol}</InfoRow>
            <InfoRow label="Available">{formatToken(reserveInfo.availableLiquidity, selectedTip?.decimals ?? 18)} {selectedTip?.symbol}</InfoRow>
            <InfoRow label="Utilization">{formatRay(reserveInfo.utilization)}</InfoRow>
            <InfoRow label="Supply APY">{formatRay(reserveInfo.supplyRate)}</InfoRow>
            <InfoRow label="Borrow APY">{formatRay(reserveInfo.borrowRate)}</InfoRow>
            <InfoRow label="Your Supply">{formatToken(userBalances.supply, selectedTip?.decimals ?? 18)} {selectedTip?.symbol}</InfoRow>
            <InfoRow label="Your Borrow">{formatToken(userBalances.borrow, selectedTip?.decimals ?? 18)} {selectedTip?.symbol}</InfoRow>
            <InfoRow label="Collateral Factor">{reserveInfo.collateralFactor ? `${Number(reserveInfo.collateralFactor) / 100}%` : "—"}</InfoRow>
            <InfoRow label="Liquidation Threshold">{reserveInfo.liquidationThreshold ? `${Number(reserveInfo.liquidationThreshold) / 100}%` : "—"}</InfoRow>
          </div>
        </div>
      )}

      {/* ════════════════════════════════════════════════════════════
          TAB: SUPPLY / WITHDRAW
          ════════════════════════════════════════════════════════════ */}
      {tab === "supply" && signer && selectedAsset && (
        <>
          {/* Supply */}
          <div className="card">
            <div className="card-header">💰 Supply {selectedTip?.symbol ?? ""}</div>

            {/* WETH dual-balance bar */}
            {isWETH && (
              <div style={{
                padding: "8px 12px", marginBottom: "12px", borderRadius: "8px",
                background: "rgba(99,102,241,0.12)", fontSize: "13px", color: "#cbd5e1",
                display: "flex", alignItems: "center", gap: "16px", flexWrap: "wrap",
              }}>
                <span>💎 ETH: <strong>{ethBalance != null ? (Number(ethBalance) / 1e18).toFixed(6) : "—"}</strong></span>
                <span>🔷 WETH: <strong>{selectedTip?.balanceOf != null ? formatToken(selectedTip.balanceOf, 18) : "—"}</strong></span>
                <button className="btn btn-secondary" style={{ fontSize: "12px", padding: "4px 12px" }}
                  onClick={mkAction(async () => {
                    const wethC = new Contract(wethAddr, WETH9_ABI, signer);
                    const amt = toWei(supplyAmt, 18);
                    const value = amt > 0n ? amt : ethBalance;
                    await hook.sendTx(() => wethC.deposit({ value }));
                    refreshEthBalance();
                    const tip = await hook.getTokenInfo(selectedAsset);
                    setSelectedTip(tip);
                  })}
                  disabled={hook.txPending}>
                  🔄 Wrap ETH → WETH
                </button>
              </div>
            )}

            <div className="form-group">
              <label className="form-label">Amount to Supply</label>
              <input className="input" type="number" step="any" placeholder="0.0"
                value={supplyAmt} onChange={e => setSupplyAmt(e.target.value)} />
              <div style={{ fontSize: "12px", color: "#94a3b8", marginTop: "4px" }}>
                {isWETH ? (
                  <>Balance: {ethBalance != null ? (Number(ethBalance) / 1e18).toFixed(6) : "—"} ETH + {selectedTip?.balanceOf != null ? formatToken(selectedTip.balanceOf, selectedTip.decimals) : "—"} WETH</>
                ) : (
                  <>Balance: {selectedTip?.balanceOf != null ? formatToken(selectedTip.balanceOf, selectedTip.decimals) : "—"} {selectedTip?.symbol ?? ""}</>
                )}
                {(() => {
                  const hasBalance = isWETH
                    ? (ethBalance != null && ethBalance > 0n)
                    : (selectedTip?.balanceOf != null && selectedTip.balanceOf > 0n);
                  return hasBalance ? (
                    <span style={{ cursor: "pointer", color: "#6366f1", marginLeft: "8px" }}
                      onClick={supplyMax}>MAX</span>
                  ) : null;
                })()}
              </div>
            </div>
            <div style={{ display: "flex", gap: "10px", marginTop: "10px", flexWrap: "wrap" }}>
              <button className="btn"
                onClick={mkAction(() => {
                  const raw = toWei(supplyAmt, selectedTip?.decimals ?? 18);
                  if (raw <= 0n) return;
                  return hook.supply(selectedAsset, raw);
                })}
                disabled={hook.txPending || !supplyAmt || parseFloat(supplyAmt) <= 0}>
                Supply
              </button>
              <button className="btn btn-secondary"
                onClick={mkAction(() => hook.approveToken(selectedAsset, marketAddr))}
                disabled={hook.txPending}>
                Approve {selectedTip?.symbol ?? ""}
              </button>
            </div>
          </div>

          {/* Withdraw */}
          <div className="card">
            <div className="card-header">💸 Withdraw {selectedTip?.symbol ?? ""}</div>
            <div className="form-group">
              <label className="form-label">Amount to Withdraw</label>
              <input className="input" type="number" step="any" placeholder="0.0"
                value={withdrawAmt} onChange={e => setWithdrawAmt(e.target.value)} />
              <div style={{ fontSize: "12px", color: "#94a3b8", marginTop: "4px" }}>
                Supplied: {formatToken(userBalances.supply, selectedTip?.decimals ?? 18)} {selectedTip?.symbol}
                <span style={{ cursor: "pointer", color: "#6366f1", marginLeft: "8px" }}
                  onClick={() => setWithdrawAmt(max(userBalances.supply, selectedTip?.decimals ?? 18))}>MAX</span>
              </div>
            </div>
            <div style={{ display: "flex", gap: "10px", marginTop: "10px", flexWrap: "wrap" }}>
              <button className="btn"
                onClick={mkAction(() => {
                  const raw = toWei(withdrawAmt, selectedTip?.decimals ?? 18);
                  if (raw <= 0n) return;
                  return hook.withdraw(selectedAsset, raw);
                })}
                disabled={hook.txPending || !withdrawAmt || parseFloat(withdrawAmt) <= 0}>
                Withdraw
              </button>
            </div>
          </div>

          {/* Collateral toggle */}
          <div className="card">
            <div className="card-header">🛡️ Collateral Setting</div>
            <InfoRow label="Using as collateral">{collateralOn ? "✅ Yes" : "❌ No"}</InfoRow>
            <div style={{ display: "flex", gap: "10px", marginTop: "10px" }}>
              {!collateralOn && (
                <button className="btn btn-primary"
                  onClick={mkAction(() => hook.setCollateral(selectedAsset, true))}
                  disabled={hook.txPending}>
                  🔒 Enable as Collateral
                </button>
              )}
              {collateralOn && (
                <button className="btn btn-secondary"
                  onClick={mkAction(() => hook.setCollateral(selectedAsset, false))}
                  disabled={hook.txPending}>
                  🔓 Disable Collateral
                </button>
              )}
            </div>
          </div>
        </>
      )}

      {/* ════════════════════════════════════════════════════════════
          TAB: BORROW / REPAY
          ════════════════════════════════════════════════════════════ */}
      {tab === "borrow" && signer && selectedAsset && (
        <>
          {/* Borrow */}
          <div className="card">
            <div className="card-header">💳 Borrow {selectedTip?.symbol ?? ""}</div>

            {/* Available-to-borrow summary */}
            {availableToBorrow && (
              <div style={{
                padding: "8px 12px", marginBottom: "12px", borderRadius: "8px",
                background: "rgba(99,102,241,0.12)", fontSize: "13px", color: "#cbd5e1",
              }}>
                <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: "6px" }}>
                  <InfoRow label="Pool available">{formatToken(availableToBorrow.poolMax, selectedTip?.decimals ?? 18)} {selectedTip?.symbol}</InfoRow>
                  <InfoRow label="You can borrow (collateral limit)">{formatToken(availableToBorrow.assetMax, selectedTip?.decimals ?? 18)} {selectedTip?.symbol}</InfoRow>
                </div>
                <div style={{ marginTop: "6px", fontSize: "12px", color: "#94a3b8" }}>
                  Effective: <strong style={{ color: "#a5b4fc" }}>
                    {availableToBorrow.poolMax < availableToBorrow.assetMax
                      ? formatToken(availableToBorrow.poolMax, selectedTip?.decimals ?? 18)
                      : formatToken(availableToBorrow.assetMax, selectedTip?.decimals ?? 18)
                    } {selectedTip?.symbol}
                  </strong> (capped by {availableToBorrow.poolMax < availableToBorrow.assetMax ? "pool liquidity" : "collateral"})
                </div>
              </div>
            )}

            <div className="form-group">
              <label className="form-label">Amount to Borrow</label>
              <input className="input" type="number" step="any" placeholder="0.0"
                value={borrowAmt} onChange={e => setBorrowAmt(e.target.value)} />
            </div>
            <button className="btn" style={{ marginTop: "10px" }}
              onClick={mkAction(() => {
                const raw = toWei(borrowAmt, selectedTip?.decimals ?? 18);
                if (raw <= 0n) return;
                return hook.borrow(selectedAsset, raw);
              })}
              disabled={hook.txPending || !borrowAmt || parseFloat(borrowAmt) <= 0}>
              Borrow
            </button>
          </div>

          {/* Repay */}
          <div className="card">
            <div className="card-header">📤 Repay {selectedTip?.symbol ?? ""}</div>
            <div className="form-group">
              <label className="form-label">Amount to Repay</label>
              <input className="input" type="number" step="any" placeholder="0.0"
                value={repayAmt} onChange={e => setRepayAmt(e.target.value)} />
              <div style={{ fontSize: "12px", color: "#94a3b8", marginTop: "4px" }}>
                Outstanding: {formatToken(userBalances.borrow, selectedTip?.decimals ?? 18)} {selectedTip?.symbol}
                <span style={{ cursor: "pointer", color: "#6366f1", marginLeft: "8px" }}
                  onClick={() => setRepayAmt(max(userBalances.borrow, selectedTip?.decimals ?? 18))}>MAX</span>
              </div>
            </div>
            <button className="btn" style={{ marginTop: "10px" }}
              onClick={mkAction(() => {
                const raw = toWei(repayAmt, selectedTip?.decimals ?? 18);
                if (raw <= 0n) return;
                return hook.repay(selectedAsset, raw);
              })}
              disabled={hook.txPending || !repayAmt || parseFloat(repayAmt) <= 0}>
              Repay
            </button>
          </div>
        </>
      )}

      {/* ════════════════════════════════════════════════════════════
          TAB: FLASH LOAN
          ════════════════════════════════════════════════════════════ */}
      {tab === "flashloan" && signer && selectedAsset && (
        <div className="card">
          <div className="card-header">⚡ Flash Loan — {selectedTip?.symbol ?? ""}</div>
          <p style={{ fontSize: "13px", color: "#94a3b8", marginBottom: "12px" }}>
            Premium: {reserveInfo?.flashLoanPremium != null ? `${Number(reserveInfo.flashLoanPremium) / 100}%` : "0.09%"} (paid in one tx, no collateral)
          </p>
          <div className="form-group">
            <label className="form-label">Receiver Contract Address</label>
            <input className="input" placeholder="0x…" value={flReceiver}
              onChange={e => setFlReceiver(e.target.value)} />
          </div>
          <div className="form-group">
            <label className="form-label">Loan Amount</label>
            <input className="input" type="number" step="any" placeholder="0.0"
              value={flAmount} onChange={e => setFlAmount(e.target.value)} />
            <div style={{ fontSize: "12px", color: "#94a3b8", marginTop: "4px" }}>
              Max available: {formatToken(reserveInfo?.availableLiquidity ?? 0n, selectedTip?.decimals ?? 18)} {selectedTip?.symbol}
            </div>
          </div>
          <button className="btn" style={{ marginTop: "10px" }}
            onClick={mkAction(() => {
              const raw = toWei(flAmount, selectedTip?.decimals ?? 18);
              if (raw <= 0n) return;
              return hook.flashLoan(flReceiver, selectedAsset, raw);
            })}
            disabled={hook.txPending || !flReceiver || !flAmount || parseFloat(flAmount) <= 0}>
            Execute Flash Loan
          </button>
        </div>
      )}

      {/* ════════════════════════════════════════════════════════════
          TAB: DASHBOARD
          ════════════════════════════════════════════════════════════ */}
      {tab === "dashboard" && signer && (
        <div className="card">
          <div className="card-header">📊 Your Account Dashboard</div>
          {!dashboard ? (
            <p style={{ color: "#94a3b8" }}>Loading account data…</p>
          ) : (
            <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: "6px", fontSize: "13px", color: "#cbd5e1" }}>
              <InfoRow label="Total Collateral (USD)">${formatToken(dashboard.totalCollateralUSD, 8)}</InfoRow>
              <InfoRow label="Total Debt (USD)">${formatToken(dashboard.totalDebtUSD, 8)}</InfoRow>
              <InfoRow label="Available to Borrow (USD)">${formatToken(dashboard.availableBorrowsUSD, 8)}</InfoRow>
              <InfoRow label="Weighted LTV">{dashboard.ltv != null ? `${Number(dashboard.ltv) / 100}%` : "—"}</InfoRow>
              <InfoRow label="Liquidation Threshold">{dashboard.currentLiquidationThreshold != null ? `${Number(dashboard.currentLiquidationThreshold) / 100}%` : "—"}</InfoRow>
              <InfoRow label="Health Factor">
                <span style={{
                  color: dashboard.healthFactor >= RAY ? "#6ee7b7" : "#fca5a5",
                  fontWeight: "bold",
                }}>
                  {dashboard.healthFactor === BigInt("0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff") ? "∞" :
                    (Number(dashboard.healthFactor) / 1e27).toFixed(4)}
                </span>
              </InfoRow>
            </div>
          )}
          <div style={{ marginTop: "14px" }}>
            <button className="btn btn-secondary" onClick={loadDashboard} disabled={hook.txPending}>
              🔄 Refresh
            </button>
          </div>
        </div>
      )}

      {/* ════════════════════════════════════════════════════════════
          TAB: ADMIN (owner only)
          ════════════════════════════════════════════════════════════ */}
      {tab === "admin" && signer && isOwner && (
        <>
          {/* ── Init Reserve ── */}
          <div className="card" style={{ borderColor: "#f59e0b" }}>
            <div className="card-header" style={{ color: "#fbbf24" }}>🆕 Init New Reserve</div>
            <p style={{ fontSize: "12px", color: "#94a3b8", marginBottom: "12px" }}>
              Register a new ERC20 asset for lending/borrowing. Defaults match the deploy script.
            </p>

            <div className="form-group">
              <label className="form-label">Token Address *</label>
              <input className="input" placeholder="0x…" value={adminAsset}
                onChange={e => setAdminAsset(e.target.value)} />
            </div>

            <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: "12px" }}>
              {/* Column 1 — Risk params */}
              <div>
                <label style={{ fontSize: "12px", color: "#94a3b8", display: "block", marginBottom: "8px" }}>
                  ⚠️ Risk Parameters (bps)
                </label>
                <div className="form-group">
                  <label className="form-label">Collateral Factor</label>
                  <input className="input" type="number" step="1" value={adminCF}
                    onChange={e => setAdminCF(e.target.value)} />
                  <small style={{ color: "#64748b" }}>7500 = 75%</small>
                </div>
                <div className="form-group">
                  <label className="form-label">Liquidation Threshold</label>
                  <input className="input" type="number" step="1" value={adminLT}
                    onChange={e => setAdminLT(e.target.value)} />
                  <small style={{ color: "#64748b" }}>8500 = 85%</small>
                </div>
                <div className="form-group">
                  <label className="form-label">Liquidation Bonus</label>
                  <input className="input" type="number" step="1" value={adminLB}
                    onChange={e => setAdminLB(e.target.value)} />
                  <small style={{ color: "#64748b" }}>10500 = 5% bonus</small>
                </div>
                <div className="form-group">
                  <label className="form-label">Flash Loan Premium</label>
                  <input className="input" type="number" step="1" value={adminFLP}
                    onChange={e => setAdminFLP(e.target.value)} />
                  <small style={{ color: "#64748b" }}>9 = 0.09%</small>
                </div>
              </div>

              {/* Column 2 — Rate params */}
              <div>
                <label style={{ fontSize: "12px", color: "#94a3b8", display: "block", marginBottom: "8px" }}>
                  📈 Interest Rate Model (RAY)
                </label>
                <div className="form-group">
                  <label className="form-label">Price (USD, 1e8)</label>
                  <input className="input" type="text" value={adminPrice}
                    onChange={e => setAdminPrice(e.target.value)} />
                  <small style={{ color: "#64748b" }}>$1.00 = 100000000 (1e8)</small>
                </div>
                <div className="form-group">
                  <label className="form-label">Optimal Utilization</label>
                  <input className="input" type="text" value={adminOptUtil}
                    onChange={e => setAdminOptUtil(e.target.value)} />
                  <small style={{ color: "#64748b" }}>0.8 = 80% (as RAY: 0.8e27)</small>
                </div>
                <div className="form-group">
                  <label className="form-label">Base Borrow Rate</label>
                  <input className="input" type="text" value={adminBaseRate}
                    onChange={e => setAdminBaseRate(e.target.value)} />
                  <small style={{ color: "#64748b" }}>0.02 = 2% APY</small>
                </div>
                <div className="form-group">
                  <label className="form-label">Slope 1 (pre-optimal)</label>
                  <input className="input" type="text" value={adminSlope1}
                    onChange={e => setAdminSlope1(e.target.value)} />
                  <small style={{ color: "#64748b" }}>0.06 = 6%</small>
                </div>
                <div className="form-group">
                  <label className="form-label">Slope 2 (post-optimal jump)</label>
                  <input className="input" type="text" value={adminSlope2}
                    onChange={e => setAdminSlope2(e.target.value)} />
                  <small style={{ color: "#64748b" }}>3 = 300%</small>
                </div>
              </div>
            </div>

            <button className="btn btn-primary" style={{ marginTop: "14px", width: "100%" }}
              onClick={mkAction(async () => {
                const toRay = (v) => BigInt(Math.floor(parseFloat(v) * 1e27));
                const toPrice = (v) => BigInt(Math.floor(parseFloat(v) * 1e8));
                return hook.initReserve(
                  adminAsset,
                  BigInt(adminCF), BigInt(adminLT), BigInt(adminLB),
                  BigInt(adminFLP), toPrice(adminPrice),
                  toRay(adminOptUtil), toRay(adminBaseRate),
                  toRay(adminSlope1), toRay(adminSlope2),
                );
              })}
              disabled={hook.txPending || !adminAsset || !adminPrice}>
              🚀 Init Reserve
            </button>
          </div>

          {/* ── Update existing reserve ── */}
          {selectedAsset && reservesList.length > 0 && (
            <div className="card" style={{ borderColor: "#6366f1" }}>
              <div className="card-header" style={{ color: "#a5b4fc" }}>🔧 Update Reserve — {selectedTip?.symbol ?? shortenHash(selectedAsset)}</div>
              <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: "12px" }}>
                {/* Update Price */}
                <div>
                  <div className="form-group">
                    <label className="form-label">New Price (USD, 1e8)</label>
                    <input className="input" type="text" placeholder="100000000"
                      id="adminUpdatePrice" />
                    <small style={{ color: "#64748b" }}>Current: {reserveInfo?.price?.toString?.() ?? "—"}</small>
                  </div>
                  <button className="btn btn-secondary" style={{ width: "100%" }}
                    onClick={mkAction(() => {
                      const el = document.getElementById("adminUpdatePrice");
                      const val = BigInt(Math.floor(parseFloat(el?.value || "1") * 1e8));
                      return hook.setAssetPrice(selectedAsset, val);
                    })}
                    disabled={hook.txPending}>
                    Update Price
                  </button>
                </div>

                {/* Update Collateral Factor */}
                <div>
                  <div className="form-group">
                    <label className="form-label">New Collateral Factor (bps)</label>
                    <input className="input" type="number" step="1" placeholder="7500"
                      id="adminUpdateCF" />
                    <small style={{ color: "#64748b" }}>Current: {reserveInfo?.collateralFactor?.toString?.() ?? "—"}</small>
                  </div>
                  <button className="btn btn-secondary" style={{ width: "100%" }}
                    onClick={mkAction(() => {
                      const el = document.getElementById("adminUpdateCF");
                      const val = BigInt(el?.value || "7500");
                      return hook.setCollateralFactorAdmin(selectedAsset, val);
                    })}
                    disabled={hook.txPending}>
                    Update CF
                  </button>
                </div>

                {/* Update Flash Loan Premium */}
                <div style={{ gridColumn: "1 / -1" }}>
                  <div className="form-group">
                    <label className="form-label">New Flash Loan Premium (bps)</label>
                    <input className="input" type="number" step="1" placeholder="9"
                      id="adminUpdateFLP" style={{ maxWidth: "300px" }} />
                    <small style={{ color: "#64748b" }}>Current: {reserveInfo?.flashLoanPremium?.toString?.() ?? "—"} → {reserveInfo?.flashLoanPremium ? `${Number(reserveInfo.flashLoanPremium) / 100}%` : "—"}</small>
                  </div>
                  <button className="btn btn-secondary" style={{ width: "300px" }}
                    onClick={mkAction(() => {
                      const el = document.getElementById("adminUpdateFLP");
                      const val = BigInt(el?.value || "9");
                      return hook.setFlashLoanPremium(selectedAsset, val);
                    })}
                    disabled={hook.txPending}>
                    Update FL Premium
                  </button>
                </div>
              </div>
            </div>
          )}
        </>
      )}
    </div>
  );
}
