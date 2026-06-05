import { useState, useEffect, useCallback } from "react";
import { Contract, isAddress } from "ethers";
import {
  MEMEFACTORY_ABI,
  ERC20_ABI,
  MEMETOKEN_EXTRA_ABI,
  shortenHash,
  explorerUrl,
} from "../utils/contract";

export function useMemeFactory(signer, factoryAddress) {
  const [factoryContract, setFactoryContract] = useState(null);
  const [factoryAddressOk, setFactoryAddressOk] = useState(false);
  const [txStatus, setTxStatus] = useState(null);
  const [txPending, setTxPending] = useState(false);

  useEffect(() => {
    if (signer && factoryAddress && isAddress(factoryAddress)) {
      setFactoryContract(new Contract(factoryAddress, MEMEFACTORY_ABI, signer));
      setFactoryAddressOk(true);
    } else {
      setFactoryContract(null);
      setFactoryAddressOk(false);
    }
  }, [signer, factoryAddress]);

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

  // ── createMeme ──
  const createMeme = useCallback(async (name, symbol, totalSupply) => {
    if (!factoryContract) {
      setTxStatus({ type: "error", message: "Invalid MemeFactory address." });
      return;
    }
    try {
      await sendTx(() => factoryContract.createMeme(name, symbol, totalSupply));
    } catch {
      /* surfaced via sendTx */
    }
  }, [factoryContract, sendTx]);

  // ── 分页加载 meme token 基本信息 ──
  const loadMemeTokens = useCallback(async (offset, limit, account) => {
    if (!factoryContract) throw new Error("Factory contract not ready");
    if (!signer) throw new Error("Wallet not connected");

    try {
      const factoryRead = new Contract(factoryContract.target, MEMEFACTORY_ABI, signer.provider);
      const [page, total] = await factoryRead.getMemeTokensPaginated(offset, limit);

      const tokens = [];
      for (const addr of page) {
        try {
          const meme = new Contract(addr, [...ERC20_ABI, ...MEMETOKEN_EXTRA_ABI], signer.provider);
          const [name, symbol, totalSupply, balance, owner] = await Promise.all([
            meme.name(),
            meme.symbol(),
            meme.totalSupply(),
            account ? meme.balanceOf(account).catch(() => null) : Promise.resolve(null),
            meme.owner().catch(() => null),
          ]);
          tokens.push({ address: addr, name, symbol, totalSupply, balance, owner });
        } catch (e) {
          tokens.push({ address: addr, name: "???", symbol: "???", totalSupply: null, balance: null, owner: null, error: e.message });
        }
      }
      return { tokens, total };
    } catch (e) {
      throw new Error(
        `Failed to read MemeFactory at ${factoryContract.target}. `
        + `Is MemeFactory deployed on this network? (${e.message})`
      );
    }
  }, [factoryContract, signer]);

  const getMemeCount = useCallback(async () => {
    if (!factoryContract) throw new Error("Factory contract not ready");
    const factoryRead = new Contract(factoryContract.target, MEMEFACTORY_ABI, signer?.provider);
    return await factoryRead.memeCount();
  }, [factoryContract, signer]);

  return {
    factoryContract, factoryAddressOk,
    txStatus, txPending, clearTxStatus,
    createMeme, loadMemeTokens, getMemeCount,
  };
}
