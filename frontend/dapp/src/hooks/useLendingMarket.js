import { useState, useEffect, useCallback } from "react";
import { Contract, isAddress } from "ethers";
import { LENDINGMARKET_ABI, ERC20_ABI, shortenHash, explorerUrl } from "../utils/contract";

export function useLendingMarket(signer, marketAddr) {
  const [marketC, setMarketC] = useState(null);
  const [txStatus, setTxStatus] = useState(null);
  const [txPending, setTxPending] = useState(false);

  useEffect(() => {
    if (signer && marketAddr && isAddress(marketAddr)) {
      setMarketC(new Contract(marketAddr, LENDINGMARKET_ABI, signer));
    } else {
      setMarketC(null);
    }
  }, [signer, marketAddr]);

  // ── Tx helper ──
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
      setTxPending(false);
      if (onConfirmed) await onConfirmed(receipt);
    } catch (err) {
      let msg = err.shortMessage || err.reason || err.message || String(err);
      if (msg.includes("user rejected") || msg.includes("ACTION_REJECTED")) msg = "Transaction rejected by user.";
      setTxStatus({ type: "error", message: msg });
      setTxPending(false);
    }
  }, []);

  const clearTxStatus = useCallback(() => setTxStatus(null), []);

  // ── Read helpers ──
  const getReservesList = useCallback(async () => {
    if (!marketC) return [];
    return await marketC.getReservesList();
  }, [marketC]);

  const getReserve = useCallback(async (asset) => {
    if (!marketC) return null;
    return await marketC.reserves(asset);
  }, [marketC]);

  const getUserAccountData = useCallback(async (user) => {
    if (!marketC || !user) return null;
    return await marketC.getUserAccountData(user);
  }, [marketC]);

  const getUserBalances = useCallback(async (user, asset) => {
    if (!marketC || !user || !asset) return { supply: 0n, borrow: 0n };
    const [supply, borrow] = await Promise.all([
      marketC.getUserSupply(user, asset),
      marketC.getUserBorrow(user, asset),
    ]);
    return { supply, borrow };
  }, [marketC]);

  const getCurrentBorrowRate = useCallback(async (asset) => {
    if (!marketC) return 0n;
    return await marketC.getCurrentBorrowRate(asset);
  }, [marketC]);

  const getCurrentSupplyRate = useCallback(async (asset) => {
    if (!marketC) return 0n;
    return await marketC.getCurrentSupplyRate(asset);
  }, [marketC]);

  const getTokenInfo = useCallback(async (tokenAddr) => {
    if (!signer || !tokenAddr || !isAddress(tokenAddr)) return null;
    try {
      const c = new Contract(tokenAddr, ERC20_ABI, signer);
      const [symbol, decimals, balance] = await Promise.all([
        c.symbol(), c.decimals(), signer.getAddress().then(a => c.balanceOf(a)),
      ]);
      // ethers v6 returns bigint — convert for JS arithmetic
      return { symbol, decimals: Number(decimals), balanceOf: balance };
    } catch { return null; }
  }, [signer]);

  // ── Mutations ──
  const supply = useCallback(async (asset, amount) => {
    if (!marketC) return;
    await sendTx(() => marketC.supply(asset, amount));
  }, [marketC, sendTx]);

  const withdraw = useCallback(async (asset, amount) => {
    if (!marketC) return;
    await sendTx(() => marketC.withdraw(asset, amount));
  }, [marketC, sendTx]);

  const borrow = useCallback(async (asset, amount) => {
    if (!marketC) return;
    await sendTx(() => marketC.borrow(asset, amount));
  }, [marketC, sendTx]);

  const repay = useCallback(async (asset, amount) => {
    if (!marketC) return;
    await sendTx(() => marketC.repay(asset, amount));
  }, [marketC, sendTx]);

  const setCollateral = useCallback(async (asset, enable) => {
    if (!marketC) return;
    await sendTx(() => marketC.setUserUseAsCollateral(asset, enable));
  }, [marketC, sendTx]);

  const approveToken = useCallback(async (token, spender, amount) => {
    if (!signer || !token || !isAddress(token)) return;
    const c = new Contract(token, ERC20_ABI, signer);
    const maxApproval = BigInt("0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff");
    await sendTx(() => c.approve(spender, amount ?? maxApproval));
  }, [signer, sendTx]);

  const flashLoan = useCallback(async (receiver, asset, amount) => {
    if (!marketC) return;
    await sendTx(() => marketC.flashLoan(receiver, asset, amount, "0x"));
  }, [marketC, sendTx]);

  const liquidate = useCallback(async (collateralAsset, debtAsset, borrower, debtToCover) => {
    if (!marketC) return;
    await sendTx(() => marketC.liquidate(collateralAsset, debtAsset, borrower, debtToCover));
  }, [marketC, sendTx]);

  // ── Admin ──
  const getOwner = useCallback(async () => {
    if (!marketC) return null;
    return await marketC.owner();
  }, [marketC]);

  const initReserve = useCallback(async (
    asset,
    collateralFactor, liquidationThreshold, liquidationBonus,
    flashLoanPremium, price,
    optimalUtilizationRate, baseBorrowRate, slope1, slope2,
  ) => {
    if (!marketC) return;
    await sendTx(() => marketC.initReserve(
      asset,
      collateralFactor, liquidationThreshold, liquidationBonus,
      flashLoanPremium, price,
      optimalUtilizationRate, baseBorrowRate, slope1, slope2,
    ));
  }, [marketC, sendTx]);

  const setAssetPrice = useCallback(async (asset, price) => {
    if (!marketC) return;
    await sendTx(() => marketC.setAssetPrice(asset, price));
  }, [marketC, sendTx]);

  const setCollateralFactorAdmin = useCallback(async (asset, cf) => {
    if (!marketC) return;
    await sendTx(() => marketC.setCollateralFactor(asset, cf));
  }, [marketC, sendTx]);

  const setFlashLoanPremium = useCallback(async (asset, premium) => {
    if (!marketC) return;
    await sendTx(() => marketC.setFlashLoanPremium(asset, premium));
  }, [marketC, sendTx]);

  return {
    marketC,
    txStatus, txPending, sendTx, clearTxStatus,
    getReservesList, getReserve, getUserAccountData, getUserBalances,
    getCurrentBorrowRate, getCurrentSupplyRate, getTokenInfo,
    supply, withdraw, borrow, repay, setCollateral, approveToken,
    flashLoan, liquidate,
    getOwner, initReserve, setAssetPrice, setCollateralFactorAdmin, setFlashLoanPremium,
  };
}
