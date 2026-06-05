import { useState } from "react";
import { useWallet } from "./hooks/useWallet";
import WalletCard      from "./components/WalletCard";
import TokenBankView   from "./views/TokenBankView";
import NFTMarketView   from "./views/NFTMarketView";
import MemeFactoryView from "./views/MemeFactoryView";
import BatchTransferView from "./views/BatchTransferView";
import "./App.css";

const TABS = [
  { key: "tokenbank", label: "🏦 TokenBank" },
  { key: "nftmarket", label: "🏪 NFTMarket" },
  { key: "memefactory", label: "🏭 MemeFactory" },
  { key: "batchtransfer", label: "💸 BatchTransfer" },
];

export default function App() {
  const { account, signer, chainId, ethBalance, connecting, connect, disconnect } = useWallet();
  const [activeTab, setActiveTab] = useState("tokenbank");

  return (
    <div className="container">
      <h1>⚡ DApp</h1>
      <p className="subtitle">TokenBank + NFTMarket — one app, one wallet</p>

      <WalletCard account={account} chainId={chainId} ethBalance={ethBalance} connecting={connecting} onConnect={connect} onDisconnect={disconnect} />

      {/* ── Tab bar ── */}
      <div className="tabs">
        {TABS.map(t => (
          <button key={t.key} className={`tab ${activeTab === t.key ? "active" : ""}`} onClick={() => setActiveTab(t.key)}>
            {t.label}
          </button>
        ))}
      </div>

      {/* ── Active view ── */}
      {activeTab === "tokenbank" && <TokenBankView signer={signer} account={account} chainId={chainId} />}
      {activeTab === "nftmarket" && <NFTMarketView signer={signer} account={account} chainId={chainId} />}
      {activeTab === "memefactory" && <MemeFactoryView signer={signer} account={account} chainId={chainId} />}
      {activeTab === "batchtransfer" && <BatchTransferView signer={signer} account={account} chainId={chainId} />}
    </div>
  );
}
