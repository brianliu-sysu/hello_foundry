import { useState, useEffect, useCallback } from "react";
import { Contract, isAddress } from "ethers";
import { LEVERAGEDDEX_ABI, shortenHash, explorerUrl } from "../utils/contract";

export function useLeveragedDEX(signer, dexAddr) {
  const [dexC, setDexC] = useState(null);
  const [txStatus, setTxStatus] = useState(null);
  const [txPending, setTxPending] = useState(false);

  useEffect(() => {
    if (signer && dexAddr && isAddress(dexAddr)) {
      setDexC(new Contract(dexAddr, LEVERAGEDDEX_ABI, signer));
    } else {
      setDexC(null);
    }
  }, [signer, dexAddr]);

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

  const getDexData = useCallback(async (account) => {
    if (!dexC) return null;
    const [vBase, vQuote, price, nextId] = await Promise.all([
      dexC.vBase(), dexC.vQuote(), dexC.getMarkPrice(), dexC.nextPositionId(),
    ]);
    let userPositions = [];
    if (account) {
      const ids = await dexC.getUserPositions(account);
      const rawPositions = ids.length > 0 ? await Promise.all(ids.map(id => dexC.positions(id))) : [];
      userPositions = rawPositions.map((p, i) => ({
        id: Number(ids[i]),
        trader: p[0], collateral: p[1], size: p[2], notional: p[3],
        leverage: p[4], isLong: p[5], isOpen: p[6],
      }));
      // Use .staticCall to force fresh eth_call on the latest block for every query
      for (let i = 0; i < userPositions.length; i++) {
        try {
          userPositions[i].pnl = await dexC.getUnrealizedPnL.staticCall(userPositions[i].id);
        } catch (e) {
          console.error("getUnrealizedPnL failed for id", userPositions[i].id, e);
          userPositions[i].pnl = 0n;
        }
      }
    }
    return { vBase, vQuote, price, nextId, positions: userPositions };
  }, [dexC]);

  const openPosition = useCallback(async (leverage, isLong, marginWei) => {
    if (!dexC) return;
    await sendTx(() => dexC.openPosition(leverage, isLong, { value: marginWei }));
  }, [dexC, sendTx]);

  const closePosition = useCallback(async (positionId) => {
    if (!dexC) return;
    await sendTx(() => dexC.closePosition(positionId));
  }, [dexC, sendTx]);

  const liquidate = useCallback(async (positionId) => {
    if (!dexC) return 0n;
    await sendTx(() => dexC.liquidate(positionId));
  }, [dexC, sendTx]);

  return {
    dexC, txStatus, txPending, sendTx, clearTxStatus,
    getDexData, openPosition, closePosition, liquidate,
  };
}
