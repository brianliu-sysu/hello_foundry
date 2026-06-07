import { useState, useEffect, useCallback } from "react";
import { Contract, isAddress, formatEther } from "ethers";
import { FAUCET_ABI, ERC20_ABI, shortenHash, explorerUrl } from "../utils/contract";

export function useFaucet(signer, faucetAddress) {
  const [faucetContract, setFaucetContract] = useState(null);
  const [faucetAddressOk, setFaucetAddressOk] = useState(false);
  const [txStatus, setTxStatus] = useState(null);
  const [txPending, setTxPending] = useState(false);

  // ── Faucet state ──
  const [faucetOwner, setFaucetOwner] = useState(null);
  const [faucetPaused, setFaucetPaused] = useState(false);
  const [faucetETHBalance, setFaucetETHBalance] = useState(null);
  const [tokenAddr, setTokenAddr] = useState(null);
  const [maxTokenWithdraw, setMaxTokenWithdraw] = useState(null);
  const [tokenInfo, setTokenInfo] = useState(null); // { symbol, decimals, balance }
  const [statsLoading, setStatsLoading] = useState(false);

  useEffect(() => {
    if (signer && faucetAddress && isAddress(faucetAddress)) {
      const c = new Contract(faucetAddress, FAUCET_ABI, signer);
      setFaucetContract(c);
      setFaucetAddressOk(true);
    } else {
      setFaucetContract(null);
      setFaucetAddressOk(false);
    }
  }, [signer, faucetAddress]);

  const sendTx = useCallback(async (txFn) => {
    setTxPending(true);
    setTxStatus({ type: "pending", message: "Waiting for wallet confirmation…" });
    try {
      const tx = await txFn();
      setTxStatus({ type: "pending", message: `Submitted: ${shortenHash(tx.hash)} — waiting…`, hash: tx.hash });
      const receipt = await tx.wait();
      setTxStatus({ type: "success", message: `Confirmed in block ${receipt.blockNumber}.`, hash: receipt.hash, block: receipt.blockNumber, explorerUrl: explorerUrl(receipt) });
    } catch (err) {
      const msg = err.reason || err.message || String(err);
      setTxStatus({ type: "error", message: msg });
      throw err;
    } finally { setTxPending(false); }
  }, []);

  const clearTxStatus = useCallback(() => setTxStatus(null), []);

  // ── 加载水龙头状态 ──
  const refreshFaucet = useCallback(async () => {
    if (!faucetContract || !signer) return;
    setStatsLoading(true);
    try {
      const provider = signer.provider;
      const [owner, paused, balance, token, max] = await Promise.all([
        faucetContract.owner().catch(() => null),
        faucetContract.paused().catch(() => false),
        provider.getBalance(faucetContract.target),
        faucetContract.token().catch(() => null),
        faucetContract.MAX_TOKEN_WITHDRAW().catch(() => null),
      ]);
      setFaucetOwner(owner);
      setFaucetPaused(paused);
      setFaucetETHBalance(balance);
      const validToken = (token && token !== "0x0000000000000000000000000000000000000000") ? token : null;
      setTokenAddr(validToken);
      setMaxTokenWithdraw(max);

      // 如果有 token，加载代币信息
      if (validToken) {
        try {
          const t = new Contract(validToken, ERC20_ABI, provider);
          const [symbol, decimals, tb] = await Promise.all([
            t.symbol().catch(() => "???"),
            t.decimals().catch(() => 18),
            t.balanceOf(faucetContract.target).catch(() => 0n),
          ]);
          setTokenInfo({ symbol, decimals: Number(decimals), balance: tb });
        } catch { setTokenInfo(null); }
      } else {
        setTokenInfo(null);
      }
    } catch (err) {
      console.error("Failed to load faucet stats:", err);
    } finally { setStatsLoading(false); }
  }, [faucetContract, signer]);

  useEffect(() => { if (faucetContract) refreshFaucet(); }, [faucetContract, refreshFaucet]);

  // ── 读取冷却时间 ──
  const getCooldown = useCallback(async (userAddr) => {
    if (!faucetContract || !userAddr) return { eth: 0n, token: 0n };
    const [eth, token] = await Promise.all([
      faucetContract.lastWithdrawTime(userAddr).catch(() => 0n),
      faucetContract.lastTokenWithdrawTime(userAddr).catch(() => 0n),
    ]);
    return { eth, token };
  }, [faucetContract]);

  // ── ETH 提款 ──
  const withdrawETH = useCallback(async (amount, to) => {
    if (!faucetContract) { setTxStatus({ type: "error", message: "Invalid Faucet address." }); return; }
    await sendTx(() => faucetContract.withdraw(amount, to));
    await refreshFaucet();
  }, [faucetContract, sendTx, refreshFaucet]);

  // ── Token 提款 ──
  const withdrawToken = useCallback(async (amount) => {
    if (!faucetContract) { setTxStatus({ type: "error", message: "Invalid Faucet address." }); return; }
    await sendTx(() => faucetContract.withdrawToken(amount));
    await refreshFaucet();
  }, [faucetContract, sendTx, refreshFaucet]);

  // ── Owner: setToken ──
  const setToken = useCallback(async (tAddr) => {
    if (!faucetContract) { setTxStatus({ type: "error", message: "Invalid Faucet address." }); return; }
    await sendTx(() => faucetContract.setToken(tAddr));
    await refreshFaucet();
  }, [faucetContract, sendTx, refreshFaucet]);

  // ── Owner: adminWithdrawToken ──
  const adminWithdrawToken = useCallback(async () => {
    if (!faucetContract) { setTxStatus({ type: "error", message: "Invalid Faucet address." }); return; }
    await sendTx(() => faucetContract.adminWithdrawToken());
    await refreshFaucet();
  }, [faucetContract, sendTx, refreshFaucet]);

  // ── Owner: pause / unpause ──
  const pause = useCallback(async () => {
    if (!faucetContract) { setTxStatus({ type: "error", message: "Invalid Faucet address." }); return; }
    await sendTx(() => faucetContract.pause());
    await refreshFaucet();
  }, [faucetContract, sendTx, refreshFaucet]);

  const unpause = useCallback(async () => {
    if (!faucetContract) { setTxStatus({ type: "error", message: "Invalid Faucet address." }); return; }
    await sendTx(() => faucetContract.unpause());
    await refreshFaucet();
  }, [faucetContract, sendTx, refreshFaucet]);

  return {
    faucetAddressOk,
    txStatus, txPending, clearTxStatus,
    // State
    faucetOwner, faucetPaused, faucetETHBalance,
    tokenAddr, maxTokenWithdraw, tokenInfo,
    statsLoading, refreshFaucet,
    getCooldown,
    // Actions
    withdrawETH, withdrawToken,
    setToken, adminWithdrawToken, pause, unpause,
  };
}
