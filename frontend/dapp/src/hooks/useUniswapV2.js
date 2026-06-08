import { useState, useEffect, useCallback } from "react";
import { Contract, isAddress, formatEther, parseEther } from "ethers";
import {
  UNISWAPV2_FACTORY_ABI,
  UNISWAPV2_PAIR_ABI,
  UNISWAPV2_ROUTER_ABI,
  WETH9_ABI,
  ERC20_ABI,
  shortenHash,
  explorerUrl,
} from "../utils/contract";

export function useUniswapV2(signer, factoryAddr, routerAddr, wethAddr) {
  const [factoryC, setFactoryC] = useState(null);
  const [routerC, setRouterC] = useState(null);
  const [wethC, setWethC] = useState(null);
  const [txStatus, setTxStatus] = useState(null);
  const [txPending, setTxPending] = useState(false);

  useEffect(() => {
    if (signer && factoryAddr && isAddress(factoryAddr)) {
      setFactoryC(new Contract(factoryAddr, UNISWAPV2_FACTORY_ABI, signer));
    } else {
      setFactoryC(null);
    }
  }, [signer, factoryAddr]);

  useEffect(() => {
    if (signer && routerAddr && isAddress(routerAddr)) {
      setRouterC(new Contract(routerAddr, UNISWAPV2_ROUTER_ABI, signer));
    } else {
      setRouterC(null);
    }
  }, [signer, routerAddr]);

  useEffect(() => {
    if (signer && wethAddr && isAddress(wethAddr)) {
      setWethC(new Contract(wethAddr, WETH9_ABI, signer));
    } else {
      setWethC(null);
    }
  }, [signer, wethAddr]);

  const sendTx = useCallback(async (txFn, onConfirmed) => {
    setTxPending(true);
    setTxStatus({ type: "pending", message: "Waiting for wallet confirmation…" });
    try {
      const tx = await txFn();
      setTxStatus({
        type: "pending",
        message: `Submitted: ${shortenHash(tx.hash)} — waiting…`,
        hash: tx.hash,
      });
      const receipt = await tx.wait();
      setTxStatus({
        type: "success",
        message: `Confirmed in block ${receipt.blockNumber}.`,
        hash: receipt.hash,
        block: receipt.blockNumber,
        explorerUrl: explorerUrl(receipt),
      });
      if (onConfirmed) await onConfirmed();
    } catch (err) {
      const msg = (err && (err.reason || err.message)) || String(err);
      setTxStatus({ type: "error", message: msg });
      throw err;
    } finally {
      setTxPending(false);
    }
  }, []);

  const clearTxStatus = useCallback(() => setTxStatus(null), []);

  // ── createPair ──
  const createPair = useCallback(async (tokenA, tokenB) => {
    if (!factoryC) return null;
    await sendTx(() => factoryC.createPair(tokenA, tokenB));
    const read = new Contract(factoryC.target, UNISWAPV2_FACTORY_ABI, signer.provider);
    return await read.getPair(tokenA, tokenB);
  }, [factoryC, signer, sendTx]);

  // ── getPair ──
  const getPair = useCallback(async (tokenA, tokenB) => {
    if (!factoryC) return null;
    try {
      const fc = new Contract(factoryC.target, UNISWAPV2_FACTORY_ABI, signer.provider);
      return await fc.getPair(tokenA, tokenB);
    } catch {
      return null;
    }
  }, [factoryC, signer]);

  // ── getPairInfo ──
  const getPairInfo = useCallback(async (pairAddr, account) => {
    if (!pairAddr || pairAddr === "0x0000000000000000000000000000000000000000") return null;
    const pair = new Contract(pairAddr, UNISWAPV2_PAIR_ABI, signer.provider);
    const [token0, token1, reserves, totalSupply, balance, allowance] = await Promise.all([
      pair.token0(),
      pair.token1(),
      pair.getReserves(),
      pair.totalSupply(),
      account ? pair.balanceOf(account).catch(() => 0n) : Promise.resolve(0n),
      account ? pair.allowance(account, routerC?.target || "0x0000000000000000000000000000000000000000").catch(() => 0n) : Promise.resolve(0n),
    ]);
    const t0 = new Contract(token0, ERC20_ABI, signer.provider);
    const t1 = new Contract(token1, ERC20_ABI, signer.provider);
    const [s0, s1, d0, d1] = await Promise.all([
      t0.symbol(), t1.symbol(),
      t0.decimals(), t1.decimals(),
    ]);
    return {
      address: pairAddr,
      token0, token1, symbol0: s0, symbol1: s1,
      decimals0: Number(d0), decimals1: Number(d1),
      reserve0: reserves[0], reserve1: reserves[1],
      totalSupply, balance, allowance,
    };
  }, [signer, routerC]);

  // ── getTokenBalance ──
  const getTokenBalance = useCallback(async (tokenAddr, account) => {
    if (!tokenAddr || !account) return 0n;
    try {
      const t = new Contract(tokenAddr, ERC20_ABI, signer.provider);
      return await t.balanceOf(account);
    } catch { return 0n; }
  }, [signer]);

  // ── getTokenInfo ──
  const getTokenInfo = useCallback(async (tokenAddr) => {
    try {
      const t = new Contract(tokenAddr, ERC20_ABI, signer.provider);
      const [sym, dec, bal] = await Promise.all([
        t.symbol(), t.decimals(), signer ? t.balanceOf(await signer.getAddress()) : Promise.resolve(0n),
      ]);
      return { symbol: sym, decimals: Number(dec), balanceOf: bal };
    } catch { return { symbol: "???", decimals: 18, balanceOf: 0n }; }
  }, [signer]);

  // ── addLiquidity ──
  const addLiquidity = useCallback(async (tokenA, tokenB, amtADesired, amtBDesired, account, slippage) => {
    if (!routerC) return;
    const deadline = Math.floor(Date.now() / 1000) + 1200; // 20 min
    const amtAMin = (amtADesired * (1000n - slippage)) / 1000n;
    const amtBMin = (amtBDesired * (1000n - slippage)) / 1000n;
    await sendTx(() => routerC.addLiquidity(tokenA, tokenB, amtADesired, amtBDesired, amtAMin, amtBMin, account, deadline));
  }, [routerC, sendTx]);

  // ── addLiquidityETH ──
  const addLiquidityETH = useCallback(async (token, amtTokenDesired, amtETH, account, slippage) => {
    if (!routerC) return;
    const deadline = Math.floor(Date.now() / 1000) + 1200;
    const amtTokenMin = (amtTokenDesired * (1000n - slippage)) / 1000n;
    const amtETHMin = (amtETH * (1000n - slippage)) / 1000n;
    await sendTx(() => routerC.addLiquidityETH(token, amtTokenDesired, amtTokenMin, amtETHMin, account, deadline, { value: amtETH }));
  }, [routerC, sendTx]);

  // ── removeLiquidity ──
  const removeLiquidity = useCallback(async (tokenA, tokenB, liquidity, account, slippage) => {
    if (!routerC) return;
    const deadline = Math.floor(Date.now() / 1000) + 1200;
    await sendTx(() => routerC.removeLiquidity(tokenA, tokenB, liquidity, 0, 0, account, deadline));
  }, [routerC, sendTx]);

  // ── removeLiquidityETH ──
  const removeLiquidityETH = useCallback(async (token, liquidity, account, slippage) => {
    if (!routerC) return;
    const deadline = Math.floor(Date.now() / 1000) + 1200;
    await sendTx(() => routerC.removeLiquidityETH(token, liquidity, 0, 0, account, deadline));
  }, [routerC, sendTx]);

  // ── swapExactTokensForTokens ──
  const swapExactTokensForTokens = useCallback(async (amountIn, amountOutMin, path, account) => {
    if (!routerC) return;
    const deadline = Math.floor(Date.now() / 1000) + 1200;
    await sendTx(() => routerC.swapExactTokensForTokens(amountIn, amountOutMin, path, account, deadline));
  }, [routerC, sendTx]);

  // ── swapExactETHForTokens ──
  const swapExactETHForTokens = useCallback(async (amountOutMin, path, account, ethValue) => {
    if (!routerC) return;
    const deadline = Math.floor(Date.now() / 1000) + 1200;
    await sendTx(() => routerC.swapExactETHForTokens(amountOutMin, path, account, deadline, { value: ethValue }));
  }, [routerC, sendTx]);

  // ── swapExactTokensForETH ──
  const swapExactTokensForETH = useCallback(async (amountIn, amountOutMin, path, account) => {
    if (!routerC) return;
    const deadline = Math.floor(Date.now() / 1000) + 1200;
    await sendTx(() => routerC.swapExactTokensForETH(amountIn, amountOutMin, path, account, deadline));
  }, [routerC, sendTx]);

  // ── getAmountsOut (quoted) ──
  const getAmountsOut = useCallback(async (amountIn, path) => {
    if (!routerC) return [];
    try {
      const rc = new Contract(routerC.target, UNISWAPV2_ROUTER_ABI, signer.provider);
      return await rc.getAmountsOut(amountIn, path);
    } catch { return []; }
  }, [routerC, signer]);

  // ── approve pair ──
  const approvePair = useCallback(async (pairAddr) => {
    if (!routerC || !pairAddr) return;
    const pair = new Contract(pairAddr, UNISWAPV2_PAIR_ABI, signer);
    await sendTx(() => pair.approve(routerC.target, (2n ** 256n) - 1n));
  }, [routerC, signer, sendTx]);

  // ── approve token ──
  const approveToken = useCallback(async (tokenAddr, spender) => {
    const t = new Contract(tokenAddr, ERC20_ABI, signer);
    await sendTx(() => t.approve(spender, (2n ** 256n) - 1n));
  }, [signer, sendTx]);

  return {
    factoryC, routerC, wethC,
    txStatus, txPending, clearTxStatus,
    createPair, getPair, getPairInfo, getTokenBalance, getTokenInfo,
    addLiquidity, addLiquidityETH,
    removeLiquidity, removeLiquidityETH,
    swapExactTokensForTokens, swapExactETHForTokens, swapExactTokensForETH,
    getAmountsOut,
    approvePair, approveToken,
  };
}
