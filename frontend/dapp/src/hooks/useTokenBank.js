import { useState, useEffect, useCallback } from "react";
import { Contract, Signature, isAddress } from "ethers";
import { TOKENBANK_ABI, ERC20_ABI, shortenHash, explorerUrl } from "../utils/contract";

export function useTokenBank(signer, bankAddress) {
  const [bankContract,  setBankContract]  = useState(null);
  const [bankAddressOk, setBankAddressOk] = useState(false);
  const [txStatus,  setTxStatus]  = useState(null);
  const [txPending, setTxPending] = useState(false);

  useEffect(() => {
    if (signer && bankAddress && isAddress(bankAddress)) {
      setBankContract(new Contract(bankAddress, TOKENBANK_ABI, signer));
      setBankAddressOk(true);
    } else { setBankContract(null); setBankAddressOk(false); }
  }, [signer, bankAddress]);

  const sendTx = useCallback(async (txFn, onConfirmed) => {
    setTxPending(true);
    setTxStatus({ type: "pending", message: "Waiting for wallet confirmation…" });
    try {
      const tx = await txFn();
      setTxStatus({ type: "pending", message: `Submitted: ${shortenHash(tx.hash)} — waiting…`, hash: tx.hash });
      const receipt = await tx.wait();
      setTxStatus({ type: "success", message: `Confirmed in block ${receipt.blockNumber}.`, hash: receipt.hash, block: receipt.blockNumber, explorerUrl: explorerUrl(receipt) });
      if (onConfirmed) await onConfirmed();
    } catch (err) {
      const msg = err.reason || err.message || String(err);
      setTxStatus({ type: "error", message: msg });
      throw err;
    } finally { setTxPending(false); }
  }, []);

  const clearTxStatus = useCallback(() => setTxStatus(null), []);

  // ── deposit (approve + deposit) ──
  const deposit = useCallback(async (tokenAddr, amount) => {
    if (!bankContract) { setTxStatus({ type: "error", message: "Invalid TokenBank address." }); return; }
    if (!isAddress(tokenAddr)) { setTxStatus({ type: "error", message: "Invalid token address." }); return; }
    try {
      const token = new Contract(tokenAddr, ERC20_ABI, signer);
      await sendTx(() => token.approve(bankContract.target, amount));
      await sendTx(() => bankContract.deposit(tokenAddr, amount));
    } catch { /* surfaced via sendTx */ }
  }, [bankContract, signer, sendTx]);

  // ── permitDeposit (EIP-2612) ──
  const permitDeposit = useCallback(async (tokenAddr, amount) => {
    if (!bankContract) { setTxStatus({ type: "error", message: "Invalid TokenBank address." }); return; }
    if (!signer) { setTxStatus({ type: "error", message: "Wallet not connected." }); return; }
    try {
      setTxPending(true);
      setTxStatus({ type: "pending", message: "Requesting EIP-2612 signature…" });
      const owner = await signer.getAddress();
      const token = new Contract(tokenAddr, ERC20_ABI, signer.provider);
      const nonce = await token.nonces(owner);
      const deadline = Math.floor(Date.now() / 1000) + 3600;
      const network = await signer.provider.getNetwork();
      const domain = { name: "BrianICOToken", version: "1", chainId: Number(network.chainId), verifyingContract: tokenAddr };
      const types = { Permit: [
        { name: "owner", type: "address" }, { name: "spender", type: "address" },
        { name: "value", type: "uint256" }, { name: "nonce", type: "uint256" }, { name: "deadline", type: "uint256" },
      ]};
      const value = { owner, spender: bankContract.target, value: amount, nonce, deadline };
      setTxStatus({ type: "pending", message: "Please sign the permit message in MetaMask…" });
      const signature = await signer.signTypedData(domain, types, value);
      setTxStatus({ type: "pending", message: "Signature collected — submitting…" });
      const sig = Signature.from(signature);
      await sendTx(() => bankContract.permitDeposit(owner, tokenAddr, amount, deadline, sig.v, sig.r, sig.s));
    } catch (err) {
      setTxStatus({ type: "error", message: err.reason || err.message || String(err) });
      throw err;
    } finally { setTxPending(false); }
  }, [bankContract, signer, sendTx]);

  // ── withdraw ──
  const withdraw = useCallback(async (tokenAddr, amount) => {
    if (!bankContract) { setTxStatus({ type: "error", message: "Invalid TokenBank address." }); return; }
    try { await sendTx(() => bankContract.withdraw(tokenAddr, amount)); } catch { /* surfaced */ }
  }, [bankContract, sendTx]);

  // ── reads ──
  const getTokenInfo = useCallback(async (tokenAddr, userAddr) => {
    if (!isAddress(tokenAddr)) throw new Error("Invalid token address");
    if (!signer) throw new Error("Wallet not connected");
    const token = new Contract(tokenAddr, ERC20_ABI, signer.provider);
    const [symbol, decimals, balance, depositBalance, bankBalance] = await Promise.all([
      token.symbol(), token.decimals(), token.balanceOf(userAddr),
      bankContract ? bankContract.deposits(userAddr, tokenAddr) : Promise.resolve(0n),
      bankContract ? token.balanceOf(bankContract.target) : Promise.resolve(0n),
    ]);
    return { symbol, decimals: Number(decimals), balance, depositBalance, bankBalance };
  }, [bankContract, signer]);

  const getAllowance = useCallback(async (tokenAddr, ownerAddr) => {
    if (!bankContract) throw new Error("Bank contract not ready");
    if (!signer) throw new Error("Wallet not connected");
    const token = new Contract(tokenAddr, ERC20_ABI, signer.provider);
    return await token.allowance(ownerAddr, bankContract.target);
  }, [bankContract, signer]);

  return {
    bankContract, bankAddressOk,
    txStatus, txPending, clearTxStatus,
    deposit, permitDeposit, withdraw,
    getTokenInfo, getAllowance,
  };
}
