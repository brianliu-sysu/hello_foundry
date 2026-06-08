import { useState, useEffect, useCallback, useRef } from "react";
import { useUniswapV2 } from "../hooks/useUniswapV2";
import { UNISWAPV2_FACTORY_DEPLOYED, UNISWAPV2_ROUTER_DEPLOYED, WETH9_DEPLOYED, BRIANICOTOKEN_DEPLOYED, shortenHash } from "../utils/contract";
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

export default function UniswapV2View({ signer, account, chainId }) {
  const networkKey = String(chainId ?? DEFAULT_NETWORK);
  const networkLabel = NETWORK_LABELS[networkKey] || `Chain ${networkKey}`;
  const prevNet = useRef(networkKey);

  const factoryAddr = UNISWAPV2_FACTORY_DEPLOYED[networkKey] || "";
  const routerAddr  = UNISWAPV2_ROUTER_DEPLOYED[networkKey] || "";
  const wethAddr     = WETH9_DEPLOYED[networkKey] || "";

  const hook = useUniswapV2(signer, factoryAddr, routerAddr, wethAddr);

  const [tab, setTab] = useState("add");

  // Shared pair inputs — default to BIT + WETH
  const [tokenA, setTokenA] = useState(() => {
    const key = String(chainId ?? DEFAULT_NETWORK);
    return BRIANICOTOKEN_DEPLOYED[key] || "";
  });
  const [tokenB, setTokenB] = useState(() => {
    const key = String(chainId ?? DEFAULT_NETWORK);
    return WETH9_DEPLOYED[key] || "";
  });
  const [tipA, setTipA] = useState(null); // { symbol, decimals, balanceOf }
  const [tipB, setTipB] = useState(null);

  // Is this a token-ETH pair?
  const isAETH = tokenA.toLowerCase() === wethAddr?.toLowerCase();
  const isBETH = tokenB.toLowerCase() === wethAddr?.toLowerCase();

  // Amounts
  const [amtA, setAmtA] = useState("");
  const [amtB, setAmtB] = useState("");

  // Pair
  const [pairFound, setPairFound] = useState(null);
  const [pairInfo, setPairInfo] = useState(null);

  // Remove / Swap
  const [remLP, setRemLP] = useState("");

  // Swap: payAmt / receiveAmt
  const [swapPayAmt, setSwapPayAmt] = useState("");
  const [swapReceiveAmt, setSwapReceiveAmt] = useState("");
  const [swapPayingA, setSwapPayingA] = useState(true); // true = paying with tokenA, false = paying with tokenB
  const [swapSlippage, setSwapSlippage] = useState("1");
  const [swapQuote, setSwapQuote] = useState(null); // { expectedOut, minOut } — used to warn on slippage

  // Auto-quote: when user types pay amount, calculate receive amount
  useEffect(() => {
    let active = true;
    (async () => {
      if (!swapPayAmt || parseFloat(swapPayAmt) <= 0 || !pairInfo || !hook.routerC) {
        if (active) { setSwapReceiveAmt(""); setSwapQuote(null); }
        return;
      }
      try {
        const payToken = swapPayingA ? tokenA : tokenB;
        const recvToken = swapPayingA ? tokenB : tokenA;
        const payTip = swapPayingA ? tipA : tipB;
        const recvTip = swapPayingA ? tipB : tipA;
        const dIn = payTip?.decimals ?? 18;
        const rawIn = BigInt(Math.floor(parseFloat(swapPayAmt) * 10 ** dIn));
        if (rawIn <= 0n) { if (active) { setSwapReceiveAmt(""); setSwapQuote(null); } return; }
        const amounts = await hook.getAmountsOut(rawIn, [payToken, recvToken]);
        if (!active) return;
        if (amounts.length > 1) {
          const dOut = recvTip?.decimals ?? 18;
          const expectedOut = amounts[1];
          const slippage = BigInt(swapSlippage || "1");
          const minOut = (expectedOut * (100n - slippage)) / 100n;
          setSwapReceiveAmt((Number(expectedOut) / 10 ** dOut).toFixed(dOut > 6 ? 6 : dOut));
          setSwapQuote({ expectedOut, minOut });
        } else {
          setSwapReceiveAmt("");
          setSwapQuote(null);
        }
      } catch { if (active) { setSwapReceiveAmt(""); setSwapQuote(null); } }
    })();
    return () => { active = false; };
  }, [swapPayAmt, swapSlippage, swapPayingA, pairInfo, tokenA, tokenB, tipA, tipB, hook]);

  // ETH balance
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

  // Auto-load token info
  const loadTip = useCallback(async (addr, setter) => {
    if (!addr || !signer) return;
    setter(await hook.getTokenInfo(addr));
  }, [signer, hook]);

  useEffect(() => { loadTip(tokenA, setTipA); }, [tokenA, signer, loadTip]);
  useEffect(() => { loadTip(tokenB, setTipB); }, [tokenB, signer, loadTip]);

  // Pair loading
  const loadPair = useCallback(async () => {
    if (!tokenA || !tokenB) return;
    const p = await hook.getPair(tokenA, tokenB);
    setPairFound(p);
    if (p && p !== "0x0000000000000000000000000000000000000000") {
      setPairInfo(await hook.getPairInfo(p, account));
    } else {
      setPairInfo(null);
    }
  }, [tokenA, tokenB, account, hook]);

  const refreshPairInfo = useCallback(async () => {
    if (!pairFound || pairFound === "0x0000000000000000000000000000000000000000") return;
    setPairInfo(await hook.getPairInfo(pairFound, account));
  }, [pairFound, account, hook]);

  // Network switch reset
  useEffect(() => {
    if (prevNet.current !== networkKey) {
      prevNet.current = networkKey;
      setPairFound(null); setPairInfo(null);
      setTokenA(BRIANICOTOKEN_DEPLOYED[networkKey] || "");
      setTokenB(WETH9_DEPLOYED[networkKey] || "");
      setAmtA(""); setAmtB("");
      setRemLP(""); setSwapPayAmt(""); setSwapReceiveAmt(""); setSwapPayingA(true); setSwapQuote(null);
      setTipA(null); setTipB(null);
    }
  }, [networkKey]);

  const mkAction = (fn, then) => async () => {
    try { await fn(); } catch { /* surfaced via txStatus */ }
    if (then) await then();
  };

  const handleCreatePair = async () => {
    if (!tokenA || !tokenB) return;
    const p = await hook.createPair(tokenA, tokenB);
    if (p && p !== "0x0000000000000000000000000000000000000000") {
      setPairFound(p);
      setPairInfo(await hook.getPairInfo(p, account));
    }
  };

  const handleAddLiq = async () => {
    if (!tokenA || !tokenB || !amtA || !amtB) return;
    if (isAETH || isBETH) {
      const token = isAETH ? tokenB : tokenA;
      const tokenTip = isAETH ? tipB : tipA;
      const tokenAmt = isAETH ? amtB : amtA;
      const ethAmt   = isAETH ? amtA : amtB;
      const d0 = tokenTip?.decimals ?? 18;
      const rawToken = (parseFloat(tokenAmt) > 0 ? BigInt(Math.floor(parseFloat(tokenAmt) * 10 ** d0)) : 0n);
      const rawETH   = parseFloat(ethAmt) > 0 ? BigInt(Math.floor(parseFloat(ethAmt) * 1e18)) : 0n;
      await hook.addLiquidityETH(token, rawToken, rawETH, account, BigInt(50));
    } else {
      const d0 = tipA?.decimals ?? 18;
      const d1 = tipB?.decimals ?? 18;
      const raw0 = (parseFloat(amtA) > 0 ? BigInt(Math.floor(parseFloat(amtA) * 10 ** d0)) : 0n);
      const raw1 = (parseFloat(amtB) > 0 ? BigInt(Math.floor(parseFloat(amtB) * 10 ** d1)) : 0n);
      await hook.addLiquidity(tokenA, tokenB, raw0, raw1, account, BigInt(50));
    }
    await loadPair();
    await refreshPairInfo();
    refreshEthBalance();
    await loadTip(tokenA, setTipA);
    await loadTip(tokenB, setTipB);
  };

  const handleRemoveLiq = async () => {
    if (!pairFound || !remLP) return;

    // LP token always has 18 decimals. Input is always human-readable.
    const n = parseFloat(remLP);
    if (isNaN(n) || n <= 0) { hook.clearTxStatus(); return; }
    const lpRaw = BigInt(Math.floor(n * 1e18));
    if (lpRaw <= 0n) { hook.clearTxStatus(); return; }

    if (isAETH) {
      await hook.removeLiquidityETH(tokenB, lpRaw, account, 50n);
    } else if (isBETH) {
      await hook.removeLiquidityETH(tokenA, lpRaw, account, 50n);
    } else {
      await hook.removeLiquidity(tokenA, tokenB, lpRaw, account, 50n);
    }
    await refreshPairInfo();
    await loadTip(tokenA, setTipA);
    await loadTip(tokenB, setTipB);
    refreshEthBalance();
  };

  const handleSwap = async () => {
    if (!swapPayAmt || !pairInfo || !swapQuote) return;
    const payToken = swapPayingA ? tokenA : tokenB;
    const recvToken = swapPayingA ? tokenB : tokenA;
    const isPayETH   = (swapPayingA && isAETH) || (!swapPayingA && isBETH);
    const isRecvETH  = (swapPayingA && isBETH) || (!swapPayingA && isAETH);
    const payTip = swapPayingA ? tipA : tipB;
    const dIn = payTip?.decimals ?? 18;
    const rawIn = BigInt(Math.floor(parseFloat(swapPayAmt) * 10 ** dIn));
    const path = [payToken, recvToken];
    const minOut = swapQuote.minOut;

    if (isPayETH) {
      await hook.swapExactETHForTokens(minOut, path, account, rawIn);
    } else if (isRecvETH) {
      await hook.swapExactTokensForETH(rawIn, minOut, path, account);
    } else {
      await hook.swapExactTokensForTokens(rawIn, minOut, path, account);
    }
    await loadPair();
    await refreshPairInfo();
    await loadTip(tokenA, setTipA);
    await loadTip(tokenB, setTipB);
    refreshEthBalance();
    setSwapPayAmt("");
    setSwapReceiveAmt("");
    setSwapQuote(null);
  };

  const formatToken = (v, decimals = 18) => {
    try {
      const n = Number(v) / 10 ** decimals;
      if (n < 0.0001 && n > 0) return "<0.0001";
      return n.toLocaleString(undefined, { maximumSignificantDigits: 6 });
    } catch { return "—"; }
  };

  // Helper: balance + MAX for one token side
  const balanceRow = (isETH, tip) => {
    if (isETH) {
      const bal = ethBalance ? (Number(ethBalance) / 1e18).toFixed(6) : "—";
      return { display: `${bal} ETH`, max: ethBalance ? (Number(ethBalance) / 1e18).toFixed(6) : "0" };
    }
    const bal = tip?.balanceOf != null ? formatToken(tip.balanceOf, tip.decimals) : "—";
    return {
      display: `${bal} ${tip?.symbol || ""}`,
      max: tip ? (Number(tip.balanceOf) / 10 ** (tip.decimals || 18)).toFixed(6) : "0",
    };
  };

  // ── RENDER ──
  return (
    <div>
      {/* Config */}
      <div className="card">
        <div className="card-header">⚙️ Uniswap V2 Contracts — {networkLabel}</div>
        <InfoRow label="Factory">{shortenHash(factoryAddr) || "Not deployed"}</InfoRow>
        <InfoRow label="Router">{shortenHash(routerAddr) || "Not deployed"}</InfoRow>
        <InfoRow label="WETH">{shortenHash(wethAddr) || "Not deployed"}</InfoRow>
      </div>

      <TxStatus status={hook.txStatus} />

      {/* Tabs */}
      <div className="tabs">
        {[
          { key: "add", label: "➕ Add Liquidity" },
          { key: "remove", label: "➖ Remove Liquidity" },
          { key: "swap", label: "🔄 Swap" },
        ].map(t => (
          <button key={t.key} className={`tab ${tab === t.key ? "active" : ""}`} onClick={() => setTab(t.key)}>
            {t.label}
          </button>
        ))}
      </div>

      {/* ── Token Pair Selector ── */}
      <div className="card">
        <div className="card-header">🪙 Token Pair</div>
        <div className="form-group">
          <label className="form-label">Token A Address</label>
          <input className="input" placeholder="0x…" value={tokenA}
            onChange={e => setTokenA(e.target.value)}
            onKeyDown={e => { if (e.key === "Enter") loadPair(); }} />
        </div>
        <div className="form-group">
          <label className="form-label">Token B Address</label>
          <input className="input" placeholder={`0x… (WETH: ${wethAddr ? shortenHash(wethAddr) : "N/A"})`} value={tokenB}
            onChange={e => setTokenB(e.target.value)}
            onKeyDown={e => { if (e.key === "Enter") loadPair(); }} />
        </div>
        <div style={{ display: "flex", gap: "10px", marginTop: "12px" }}>
          <button className="btn" onClick={loadPair} disabled={hook.txPending}>🔍 Find Pair</button>
          {wethAddr && (
            <>
              <button className="btn btn-secondary" onClick={() => setTokenA(wethAddr)}>WETH as A</button>
              <button className="btn btn-secondary" onClick={() => setTokenB(wethAddr)}>WETH as B</button>
            </>
          )}
        </div>
        <div style={{ marginTop: "10px", display: "flex", gap: "20px", fontSize: "13px", color: "#94a3b8" }}>
          <span>Token A: <strong>{tipA?.symbol ?? "?"}</strong> Balance: {tipA?.balanceOf != null ? formatToken(tipA.balanceOf, tipA.decimals) : "—"}</span>
          <span>Token B: <strong>{tipB?.symbol ?? "?"}</strong> Balance: {tipB?.balanceOf != null ? formatToken(tipB.balanceOf, tipB.decimals) : "—"}</span>
        </div>
        {/* Pair found */}
        {pairFound && pairFound !== "0x0000000000000000000000000000000000000000" && pairInfo && (
          <div style={{ marginTop: "12px", padding: "10px", background: "rgba(34,197,94,0.1)", borderRadius: "8px", fontSize: "13px" }}>
            <InfoRow label="Pair">{shortenHash(pairFound)}</InfoRow>
            <InfoRow label="Reserves">{formatToken(pairInfo.reserve0, pairInfo.decimals0)} {pairInfo.symbol0} / {formatToken(pairInfo.reserve1, pairInfo.decimals1)} {pairInfo.symbol1}</InfoRow>
            <InfoRow label="Your LP">{formatToken(pairInfo.balance, 18)}</InfoRow>
          </div>
        )}
        {pairFound === "0x0000000000000000000000000000000000000000" && (
          <div style={{ marginTop: "12px", display: "flex", alignItems: "center", gap: "10px" }}>
            <button className="btn btn-primary"
              onClick={mkAction(handleCreatePair, loadPair)}
              disabled={hook.txPending || !tokenA || !tokenB}>
              🏭 Create Pair
            </button>
            <span style={{ color: "#fbbf24", fontSize: "13px" }}>⚠️ Pair does not exist yet. Click to create it first.</span>
          </div>
        )}
      </div>

      {/* ═══ ADD LIQUIDITY ═══ */}
      {tab === "add" && signer && (
        <div className="card">
          <div className="card-header">➕ Add Liquidity</div>

          {/* Amount A */}
          <div className="form-group">
            <label className="form-label">
              Amount ({tipA?.symbol ?? "Token A"}){isAETH ? " — ETH" : ""}
            </label>
            <input className="input" type="number" step="any" placeholder="0.0" value={amtA}
              onChange={e => setAmtA(e.target.value)} />
            <div style={{ fontSize: "12px", color: "#94a3b8", marginTop: "4px" }}>
              Balance: {balanceRow(isAETH, tipA).display}
              <span style={{ cursor: "pointer", color: "#6366f1", marginLeft: "8px" }}
                onClick={() => setAmtA(balanceRow(isAETH, tipA).max)}>MAX</span>
            </div>
          </div>

          {/* Amount B */}
          <div className="form-group">
            <label className="form-label">
              Amount ({tipB?.symbol ?? "Token B"}){isBETH ? " — ETH" : ""}
            </label>
            <input className="input" type="number" step="any" placeholder="0.0" value={amtB}
              onChange={e => setAmtB(e.target.value)} />
            <div style={{ fontSize: "12px", color: "#94a3b8", marginTop: "4px" }}>
              Balance: {balanceRow(isBETH, tipB).display}
              <span style={{ cursor: "pointer", color: "#6366f1", marginLeft: "8px" }}
                onClick={() => setAmtB(balanceRow(isBETH, tipB).max)}>MAX</span>
            </div>
          </div>

          <div style={{ display: "flex", gap: "10px", marginTop: "10px", flexWrap: "wrap" }}>
            <button className="btn"
              onClick={mkAction(handleAddLiq, async () => {
                await refreshPairInfo();
                await loadTip(tokenA, setTipA);
                await loadTip(tokenB, setTipB);
              })}
              disabled={hook.txPending || !amtA || !amtB || parseFloat(amtA) <= 0 || parseFloat(amtB) <= 0}>
              Add Liquidity
            </button>
            {!isAETH && (
              <button className="btn btn-secondary"
                onClick={mkAction(() => hook.approveToken(tokenA, routerAddr), refreshPairInfo)}
                disabled={hook.txPending || !tokenA}>Approve {tipA?.symbol ?? "TokenA"}</button>
            )}
            {!isBETH && (
              <button className="btn btn-secondary"
                onClick={mkAction(() => hook.approveToken(tokenB, routerAddr), refreshPairInfo)}
                disabled={hook.txPending || !tokenB}>Approve {tipB?.symbol ?? "TokenB"}</button>
            )}
          </div>
        </div>
      )}

      {/* ═══ REMOVE LIQUIDITY ═══ */}
      {tab === "remove" && signer && pairFound && pairInfo && (
        <div className="card">
          <div className="card-header">➖ Remove Liquidity</div>
          <InfoRow label="Your LP Balance">{formatToken(pairInfo.balance, 18)} LP Tokens</InfoRow>
          <div className="form-group">
            <label className="form-label">LP Amount to Remove (in LP tokens, e.g. 100)</label>
            <input className="input" type="text" placeholder="0.0"
              value={remLP} onChange={e => setRemLP(e.target.value)} />
          </div>
          <div style={{ display: "flex", gap: "10px", marginTop: "10px", flexWrap: "wrap" }}>
            <button className="btn btn-secondary"
              onClick={() => { const n = Number(pairInfo.balance) / 1e18; setRemLP(n > 0 ? n.toFixed(6) : "0"); }}
              disabled={hook.txPending}>Max</button>
            <button className="btn"
              onClick={mkAction(handleRemoveLiq, refreshPairInfo)}
              disabled={hook.txPending || !remLP}>
              Remove Liquidity
            </button>
            <button className="btn btn-secondary"
              onClick={mkAction(() => hook.approvePair(pairFound), refreshPairInfo)}
              disabled={hook.txPending || !pairFound}>
              Approve LP for Router
            </button>
          </div>
        </div>
      )}

      {/* ═══ SWAP ═══ */}
      {tab === "swap" && signer && pairFound && pairInfo && (
        <div className="card">
          <div className="card-header">🔄 Swap</div>
          <InfoRow label="Pair">{shortenHash(pairFound)}</InfoRow>
          <InfoRow label="Pool">{formatToken(pairInfo.reserve0, pairInfo.decimals0)} {pairInfo.symbol0} / {formatToken(pairInfo.reserve1, pairInfo.decimals1)} {pairInfo.symbol1}</InfoRow>

          {/* Direction toggle */}
          <div style={{ marginTop: "14px", display: "flex", gap: "8px" }}>
            <button
              className={`tab ${swapPayingA ? "active" : ""}`}
              onClick={() => { setSwapPayingA(true); setSwapPayAmt(""); setSwapReceiveAmt(""); setSwapQuote(null); }}>
              Pay {tipA?.symbol ?? "A"} → Receive {tipB?.symbol ?? "B"}
            </button>
            <button
              className={`tab ${!swapPayingA ? "active" : ""}`}
              onClick={() => { setSwapPayingA(false); setSwapPayAmt(""); setSwapReceiveAmt(""); setSwapQuote(null); }}>
              Pay {tipB?.symbol ?? "B"} → Receive {tipA?.symbol ?? "A"}
            </button>
          </div>

          <div style={{ marginTop: "16px", display: "flex", gap: "12px", alignItems: "flex-end", flexWrap: "wrap" }}>
            {/* You pay */}
            <div className="form-group" style={{ flex: "1", minWidth: "200px" }}>
              <label className="form-label">
                You Pay ({swapPayingA ? (tipA?.symbol ?? "A") : (tipB?.symbol ?? "B")})
                {((swapPayingA && isAETH) || (!swapPayingA && isBETH)) ? " — ETH" : ""}
              </label>
              <input className="input" type="number" step="any" placeholder="0.0"
                value={swapPayAmt}
                onChange={e => setSwapPayAmt(e.target.value)} />
              <div style={{ fontSize: "12px", color: "#94a3b8", marginTop: "4px" }}>
                Balance:{" "}
                {(() => {
                  const isEth = (swapPayingA && isAETH) || (!swapPayingA && isBETH);
                  const tip   = swapPayingA ? tipA : tipB;
                  return isEth
                    ? `${ethBalance ? (Number(ethBalance) / 1e18).toFixed(6) : "—"} ETH`
                    : `${tip?.balanceOf != null ? formatToken(tip.balanceOf, tip.decimals) : "—"} ${tip?.symbol || ""}`;
                })()}
                <span style={{ cursor: "pointer", color: "#6366f1", marginLeft: "8px" }}
                  onClick={() => {
                    const isEth = (swapPayingA && isAETH) || (!swapPayingA && isBETH);
                    const tip   = swapPayingA ? tipA : tipB;
                    setSwapPayAmt(isEth
                      ? (ethBalance ? (Number(ethBalance) / 1e18).toFixed(6) : "0")
                      : (tip ? (Number(tip.balanceOf) / 10 ** (tip.decimals || 18)).toFixed(6) : "0")
                    );
                  }}>MAX</span>
              </div>
            </div>

            {/* ⇄ arrow */}
            <div style={{ fontSize: "20px", paddingBottom: "8px" }}>→</div>

            {/* You receive (auto-calculated) */}
            <div className="form-group" style={{ flex: "1", minWidth: "200px" }}>
              <label className="form-label">
                You Receive ({swapPayingA ? (tipB?.symbol ?? "B") : (tipA?.symbol ?? "A")})
                {((swapPayingA && isBETH) || (!swapPayingA && isAETH)) ? " — ETH" : ""}
              </label>
              <input className="input" type="text" placeholder="0.0"
                value={swapReceiveAmt} readOnly
                style={{ background: "rgba(255,255,255,0.03)", cursor: "default" }} />
              {swapQuote && (
                <div style={{ fontSize: "12px", color: "#94a3b8", marginTop: "4px" }}>
                  Min after {swapSlippage}% slippage:{" "}
                  {(() => {
                    const recvTip = swapPayingA ? tipB : tipA;
                    const dOut = recvTip?.decimals ?? 18;
                    const n = Number(swapQuote.minOut) / 10 ** dOut;
                    return n.toLocaleString(undefined, { maximumSignificantDigits: 6 });
                  })()}
                </div>
              )}
            </div>
          </div>

          {/* Slippage + Swap button */}
          <div style={{ display: "flex", gap: "10px", alignItems: "center", marginTop: "14px", flexWrap: "wrap" }}>
            <div className="form-group" style={{ width: "80px" }}>
              <label className="form-label">Slippage%</label>
              <input className="input" type="number" step="0.1" value={swapSlippage}
                onChange={e => setSwapSlippage(e.target.value)} />
            </div>
            <button className="btn"
              onClick={mkAction(handleSwap, async () => {
                await loadTip(tokenA, setTipA);
                await loadTip(tokenB, setTipB);
              })}
              disabled={hook.txPending || !swapPayAmt || !swapQuote}>
              Swap
            </button>
            {swapQuote && (
              <span style={{ fontSize: "13px", color: "#a3e635" }}>
                1 {swapPayingA ? (tipA?.symbol ?? "A") : (tipB?.symbol ?? "B")}
                {" ≈ "}
                {(() => {
                  const payTip = swapPayingA ? tipA : tipB;
                  const dIn  = payTip?.decimals ?? 18;
                  const dOut = (swapPayingA ? tipB : tipA)?.decimals ?? 18;
                  const n = (Number(swapQuote.expectedOut) / 10 ** dOut) / (Number(parseFloat(swapPayAmt) * 10 ** dIn) / 10 ** dIn);
                  return n.toLocaleString(undefined, { maximumSignificantDigits: 4 });
                })()}
                {" "}{swapPayingA ? (tipB?.symbol ?? "B") : (tipA?.symbol ?? "A")}
              </span>
            )}
          </div>

          {/* Approval hint */}
          {pairInfo && !((swapPayingA && isAETH) || (!swapPayingA && isBETH)) && (
            <div style={{ marginTop: "10px", fontSize: "12px", color: "#94a3b8" }}>
              💡 If swap fails, first{" "}
              <span style={{ cursor: "pointer", textDecoration: "underline", color: "#6366f1" }}
                onClick={mkAction(() => {
                  const payToken = swapPayingA ? tokenA : tokenB;
                  return hook.approveToken(payToken, routerAddr);
                }, refreshPairInfo)}>
                approve {swapPayingA ? (tipA?.symbol ?? "token") : (tipB?.symbol ?? "token")}
              </span> for the Router.
            </div>
          )}
        </div>
      )}
    </div>
  );
}

