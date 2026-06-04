import { useState, useEffect, useCallback } from "react";
import { BrowserProvider } from "ethers";

export function useWallet() {
  const [account,   setAccount]   = useState(null);
  const [signer,    setSigner]    = useState(null);
  const [chainId,   setChainId]   = useState(null);
  const [ethBalance, setEthBalance] = useState(null);
  const [connecting, setConnecting] = useState(false);

  const refreshInfo = useCallback(async (_account, _signer) => {
    if (!_account || !_signer) return;
    try {
      const provider = new BrowserProvider(window.ethereum);
      const [balance, network] = await Promise.all([
        provider.getBalance(_account), provider.getNetwork(),
      ]);
      setEthBalance(balance);
      setChainId(Number(network.chainId));
    } catch (err) { console.error("useWallet.refreshInfo:", err); }
  }, []);

  const connect = useCallback(async () => {
    if (!window.ethereum) {
      alert("MetaMask is not installed.");
      return;
    }
    setConnecting(true);
    try {
      const provider = new BrowserProvider(window.ethereum);
      const accounts = await provider.send("eth_requestAccounts", []);
      if (!accounts.length) return;
      const _signer  = await provider.getSigner();
      const _account = accounts[0];
      setAccount(_account);
      setSigner(_signer);
      await refreshInfo(_account, _signer);
    } catch (err) {
      console.error("connect error:", err);
      if (err.code === 4001) alert("Connection rejected by user.");
    } finally { setConnecting(false); }
  }, [refreshInfo]);

  const disconnect = useCallback(() => {
    setAccount(null); setSigner(null); setChainId(null); setEthBalance(null);
  }, []);

  useEffect(() => {
    if (!window.ethereum) return;
    const onAccounts = (accounts) => { if (!accounts.length) disconnect(); else connect(); };
    const onChain    = () => window.location.reload();
    window.ethereum.on("accountsChanged", onAccounts);
    window.ethereum.on("chainChanged", onChain);
    return () => {
      window.ethereum.removeListener("accountsChanged", onAccounts);
      window.ethereum.removeListener("chainChanged", onChain);
    };
  }, [connect, disconnect]);

  useEffect(() => {
    if (window.ethereum && window.ethereum.selectedAddress && !account) connect();
  }, []); // eslint-disable-line react-hooks/exhaustive-deps

  return { account, signer, chainId, ethBalance, connecting, connect, disconnect, refreshInfo };
}
