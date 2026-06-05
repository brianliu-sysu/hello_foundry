import { useState, useCallback } from "react";
import { Contract, Signature, hashAuthorization, isAddress } from "ethers";
import {
  BATCHTRANSFERDELEGATION_ABI,
  ERC20_ABI,
  shortenHash,
  explorerUrl,
} from "../utils/contract";

/**
 * useBatchTransfer — EIP-7702 batch transfers
 *
 * Wallet support:
 *   ✅ OKX Wallet — natively supports authorizationList in eth_sendTransaction
 *   ⚠️ MetaMask    — blocks external EIP-7702 (error: "External EIP-7702 transactions are not supported")
 *
 * Flow (two strategies, tried in order):
 *   A. Native: pass UNSIGNED authorizationList to eth_sendTransaction.
 *      OKX Wallet internally computes the digest, shows a confirmation, and fills in the signature.
 *   B. eth_sign: if A fails, compute the 7702 digest and sign via eth_sign,
 *      then pass the SIGNED auth to eth_sendTransaction.
 *
 * @param {object}   provider          ethers BrowserProvider
 * @param {object}   signer            ethers JsonRpcSigner (connected wallet)
 * @param {string}   delegationAddress deployed BatchTransferDelegation address
 */
export function useBatchTransfer(provider, signer, delegationAddress) {
  const [txStatus,  setTxStatus]  = useState(null);
  const [txPending, setTxPending] = useState(false);

  const clearTxStatus = useCallback(() => setTxStatus(null), []);

  // ─────────────────────────────────────────────
  // Strategy B: sign the 7702 authorization digest via eth_sign,
  //             then pass the signed auth in authorizationList.
  // ─────────────────────────────────────────────
  const signAuthDigest = useCallback(async (chainId, nonce) => {
    const account = await signer.getAddress();

    const digest = hashAuthorization({ chainId, address: delegationAddress, nonce });

    setTxStatus({ type: "pending", message: "Signing EIP-7702 authorization…" });
    const sigHex = await provider.send("eth_sign", [account, digest]);
    const sig = Signature.from(sigHex);

    return {
      chainId:   "0x" + chainId.toString(16),
      address:   delegationAddress,
      nonce:     "0x" + nonce.toString(16),
      yParity:   "0x" + sig.yParity.toString(16),
      r:         sig.r,
      s:         sig.s,
    };
  }, [signer, provider, delegationAddress, setTxStatus]);

  // ─────────────────────────────────────────────
  // Core: send type-4 tx with authorizationList
  //   strategy: "native" → pass unsigned auth (OKX fills sig)
  //             "signed" → pass pre-signed auth
  // ─────────────────────────────────────────────
  const sendType4Tx = useCallback(async (encodedData, strategy) => {
    if (!signer)          throw new Error("Wallet not connected.");
    if (!provider)        throw new Error("Provider not available.");
    if (!delegationAddress || !isAddress(delegationAddress)) {
      throw new Error("Invalid delegation contract address.");
    }

    const account    = await signer.getAddress();
    const network    = await provider.getNetwork();
    const chainId    = BigInt(network.chainId);
    const nonce      = await signer.getNonce();

    let authListEntry;
    if (strategy === "native") {
      // Unsigned — wallet fills in yParity/r/s
      authListEntry = {
        chainId: "0x" + chainId.toString(16),
        address: delegationAddress,
        nonce:   "0x" + nonce.toString(16),
      };
      setTxStatus({ type: "pending", message: "Sending EIP-7702 type-4 transaction (native)…" });
    } else {
      // Pre-signed via eth_sign
      authListEntry = await signAuthDigest(chainId, nonce);
      setTxStatus({ type: "pending", message: "Sending EIP-7702 type-4 transaction (signed)…" });
    }

    const txHash = await window.ethereum.request({
      method: "eth_sendTransaction",
      params: [{
        from:              account,
        to:                account,
        data:              encodedData,
        type:              "0x4",
        authorizationList: [authListEntry],
      }],
    });

    setTxStatus({ type: "pending", message: `Submitted: ${shortenHash(txHash)} — waiting…`, hash: txHash });

    const receipt = await provider.waitForTransaction(txHash);
    setTxStatus({
      type:    "success",
      message: `Confirmed in block ${receipt.blockNumber}.`,
      hash:    receipt.hash,
      block:   receipt.blockNumber,
      explorerUrl: explorerUrl(receipt),
    });
  }, [signer, provider, delegationAddress, signAuthDigest, setTxStatus]);

  // ─────────────────────────────────────────────
  // Smart dispatcher: try native first, fall back to eth_sign
  // ─────────────────────────────────────────────
  const is7702Blocked = (msg) =>
    msg.includes("External EIP-7702") ||
    msg.includes("not supported");

  const isEthSignBlocked = (msg) =>
    msg.includes("eth_sign") && (msg.includes("not available") || msg.includes("does not exist"));

  const callWithFallback = useCallback(async (encodedData, label) => {
    // Strategy A: Native (unsigned auth — OKX supports this)
    try {
      await sendType4Tx(encodedData, "native");
      return;
    } catch (err1) {
      const msg1 = (err1 && (err1.reason || err1.message)) || String(err1);
      if (is7702Blocked(msg1)) {
        // Strategy B: eth_sign + signed auth
        setTxStatus({ type: "pending", message: "Native EIP-7702 blocked. Trying eth_sign approach…" });
        try {
          await sendType4Tx(encodedData, "signed");
          return;
        } catch (err2) {
          const msg2 = (err2 && (err2.reason || err2.message)) || String(err2);
          if (isEthSignBlocked(msg2)) {
            throw new Error(
              `This wallet does not support EIP-7702 batch transfers.\n\n` +
              `• MetaMask: currently blocks external EIP-7702 and disables eth_sign.\n` +
              `• Recommendation: use OKX Wallet, which natively supports EIP-7702.\n\n` +
              `Original error: ${msg2}`
            );
          }
          throw err2;
        }
      }
      throw err1;
    }
  }, [sendType4Tx, setTxStatus]);

  // ─────────────────────────────────────────────
  // batchTransfer  — ERC20
  // ─────────────────────────────────────────────
  const batchTransfer = useCallback(async (tokens, recipients, amounts) => {
    if (!delegationAddress || !isAddress(delegationAddress)) {
      setTxStatus({ type: "error", message: "Invalid delegation contract address." });
      return;
    }

    setTxPending(true);
    try {
      const temp = new Contract(delegationAddress, BATCHTRANSFERDELEGATION_ABI);
      const data = temp.interface.encodeFunctionData("batchTransfer", [tokens, recipients, amounts]);
      await callWithFallback(data, "ERC20 batch transfer");
    } catch (err) {
      let msg = (err && (err.reason || err.message)) || String(err);
      if (msg.includes("User rejected") || msg.includes("user rejected")) {
        msg = "Transaction rejected in wallet.";
      }
      setTxStatus({ type: "error", message: msg });
      throw err;
    } finally { setTxPending(false); }
  }, [delegationAddress, callWithFallback, setTxStatus]);

  // ─────────────────────────────────────────────
  // batchTransferETH  — native ETH
  // ─────────────────────────────────────────────
  const batchTransferETH = useCallback(async (recipients, amounts) => {
    if (!delegationAddress || !isAddress(delegationAddress)) {
      setTxStatus({ type: "error", message: "Invalid delegation contract address." });
      return;
    }

    setTxPending(true);
    try {
      const temp = new Contract(delegationAddress, BATCHTRANSFERDELEGATION_ABI);
      const data = temp.interface.encodeFunctionData("batchTransferETH", [recipients, amounts]);
      await callWithFallback(data, "ETH batch transfer");
    } catch (err) {
      let msg = (err && (err.reason || err.message)) || String(err);
      if (msg.includes("User rejected") || msg.includes("user rejected")) {
        msg = "Transaction rejected in wallet.";
      }
      setTxStatus({ type: "error", message: msg });
      throw err;
    } finally { setTxPending(false); }
  }, [delegationAddress, callWithFallback, setTxStatus]);

  // ─────────────────────────────────────────────
  // checkDelegation
  // ─────────────────────────────────────────────
  const checkDelegation = useCallback(async (address) => {
    if (!provider) throw new Error("Provider not available.");
    const code = await provider.getCode(address);
    if (code === "0x" || code === "0x0") return { delegated: false };
    if (code.startsWith("0xef0100")) {
      const impl = "0x" + code.slice(8);
      return { delegated: true, impl };
    }
    return { delegated: false, hasCode: true };
  }, [provider]);

  // ─────────────────────────────────────────────
  // getTokenInfo
  // ─────────────────────────────────────────────
  const getTokenInfo = useCallback(async (tokenAddr, userAddr) => {
    if (!isAddress(tokenAddr)) throw new Error("Invalid token address");
    if (!provider) throw new Error("Provider not available");
    const token = new Contract(tokenAddr, ERC20_ABI, provider);
    const [symbol, decimals, balance] = await Promise.all([
      token.symbol(),
      token.decimals(),
      userAddr ? token.balanceOf(userAddr) : Promise.resolve(null),
    ]);
    return { symbol, decimals: Number(decimals), balance };
  }, [provider]);

  return {
    txStatus, txPending, clearTxStatus,
    batchTransfer, batchTransferETH,
    checkDelegation, getTokenInfo,
  };
}
