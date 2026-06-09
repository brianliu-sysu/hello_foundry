import { useState, useEffect, useCallback } from "react";
import { Contract, isAddress } from "ethers";
import { STAKINGPOOL_ABI, KTKOKEN_ABI, ERC20_ABI, shortenHash, explorerUrl } from "../utils/contract";

export function useStakingPool(signer, poolAddr) {
  const [poolC, setPoolC] = useState(null);
  const [txStatus, setTxStatus] = useState(null);
  const [txPending, setTxPending] = useState(false);

  useEffect(() => {
    if (signer && poolAddr && isAddress(poolAddr)) {
      setPoolC(new Contract(poolAddr, STAKINGPOOL_ABI, signer));
    } else {
      setPoolC(null);
    }
  }, [signer, poolAddr]);

  const sendTx = useCallback(async (txFn, onConfirmed) => {
    setTxPending(true);
    setTxStatus({ type: "pending", message: "Waiting for wallet confirmation…" });
    try {
      const tx = await txFn();
      setTxStatus({ type: "pending", message: `Submitted: ${shortenHash(tx.hash)} — waiting…`, hash: tx.hash });
      const receipt = await tx.wait();
      setTxStatus({ type: "success", message: `Confirmed in block ${receipt.blockNumber}.`, hash: receipt.hash, block: receipt.blockNumber, explorerUrl: explorerUrl(receipt) });
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

  const getPoolData = useCallback(async (account) => {
    if (!poolC) return null;
    const [totalStaked, totalRewardsMinted, lastBlock, wethAddr] = await Promise.all([
      poolC.totalStaked(),
      poolC.totalRewardsMinted(),
      poolC.lastUpdateBlock(),
      poolC.WETH(),
    ]);
    let staked = 0n;
    let earned = 0n;
    let poolWeth = 0n;
    let interest = 0n;
    if (account) {
      [staked, earned, poolWeth, interest] = await Promise.all([
        poolC.stakedBalance(account),
        poolC.earned(account),
        poolC.getUserWETH(poolC.target),
        poolC.getTotalInterestEarned(),
      ]);
    }
    return { totalStaked, totalRewardsMinted, lastBlock, wethAddr, userStaked: staked, userEarned: earned, poolWeth, interest };
  }, [poolC]);

  const getKKInfo = useCallback(async (poolAddr, kkAddr) => {
    if (!signer || !kkAddr) return null;
    try {
      const c = new Contract(kkAddr, ERC20_ABI, signer);
      const [symbol, decimals, balance] = await Promise.all([
        c.symbol(), c.decimals(), signer.getAddress().then(a => c.balanceOf(a)),
      ]);
      return { symbol, decimals: Number(decimals), balanceOf: balance, address: kkAddr };
    } catch { return null; }
  }, [signer]);

  const stake = useCallback(async (ethAmount) => {
    if (!poolC) return;
    await sendTx(() => poolC.stake({ value: ethAmount }));
  }, [poolC, sendTx]);

  const withdraw = useCallback(async (amount) => {
    if (!poolC) return;
    await sendTx(() => poolC.withdraw(amount));
  }, [poolC, sendTx]);

  const claimReward = useCallback(async () => {
    if (!poolC) return;
    await sendTx(() => poolC.claimReward());
  }, [poolC, sendTx]);

  const setLendingMarket = useCallback(async (addr) => {
    if (!poolC) return;
    await sendTx(() => poolC.setLendingMarket(addr));
  }, [poolC, sendTx]);

  return {
    poolC, txStatus, txPending, sendTx, clearTxStatus,
    getPoolData, getKKInfo,
    stake, withdraw, claimReward, setLendingMarket,
  };
}
