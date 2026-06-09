import { useState } from "react";
import { useWallet } from "./hooks/useWallet";
import WalletCard      from "./components/WalletCard";
import TokenBankView   from "./views/TokenBankView";
import NFTMarketView   from "./views/NFTMarketView";
import MemeFactoryView from "./views/MemeFactoryView";
import BatchTransferView from "./views/BatchTransferView";
import NFTMintView     from "./views/NFTMintView";
import FaucetView      from "./views/FaucetView";
import UniswapV2View   from "./views/UniswapV2View";
import LendingMarketView from "./views/LendingMarketView";
import StakingPoolView   from "./views/StakingPoolView";
import LeveragedDEXView  from "./views/LeveragedDEXView";
import "./App.css";

const TABS = [
  { key: "leveraged",  label: "📈 Leveraged" },
  { key: "staking",   label: "🥩 Staking" },
  { key: "lending",    label: "🏦 Lending" },
  { key: "uniswap",    label: "🦄 Uniswap V2" },
  { key: "faucet",     label: "🚰 Faucet" },
  { key: "tokenbank",  label: "🏦 TokenBank" },
  { key: "nftmarket",  label: "🏪 NFTMarket" },
  { key: "nftmint",    label: "🎨 Mint NFT" },
  { key: "memefactory", label: "🏭 MemeFactory" },
  { key: "batchtransfer", label: "💸 BatchTransfer" },
];

export default function App() {
  const { account, signer, chainId, ethBalance, connecting, connect, disconnect } = useWallet();
  const [activeTab, setActiveTab] = useState("leveraged");

  return (
    <div className="container">
      {/* ── Sidebar ── */}
      <div className="sidebar">
        <h1>⚡ DApp</h1>
        <p className="subtitle">TokenBank + NFTMarket + Uniswap</p>

        <WalletCard account={account} chainId={chainId} ethBalance={ethBalance}
          connecting={connecting} onConnect={connect} onDisconnect={disconnect} />

        <nav className="sidebar-nav">
          {TABS.map(t => (
            <button key={t.key}
              className={`sidebar-item ${activeTab === t.key ? "active" : ""}`}
              onClick={() => setActiveTab(t.key)}>
              {t.label}
            </button>
          ))}
        </nav>
      </div>

      {/* ── Main content ── */}
      <div className="main-content">
        {activeTab === "leveraged"  && <LeveragedDEXView signer={signer} account={account} chainId={chainId} />}
        {activeTab === "staking"    && <StakingPoolView signer={signer} account={account} chainId={chainId} />}
        {activeTab === "faucet"     && <FaucetView      signer={signer} account={account} chainId={chainId} />}
        {activeTab === "nftmint"   && <NFTMintView   signer={signer} account={account} chainId={chainId} />}
        {activeTab === "tokenbank" && <TokenBankView signer={signer} account={account} chainId={chainId} />}
        {activeTab === "nftmarket" && <NFTMarketView signer={signer} account={account} chainId={chainId} />}
        {activeTab === "memefactory" && <MemeFactoryView signer={signer} account={account} chainId={chainId} />}
        {activeTab === "batchtransfer" && <BatchTransferView signer={signer} account={account} chainId={chainId} />}
        {activeTab === "lending"    && <LendingMarketView signer={signer} account={account} chainId={chainId} />}
        {activeTab === "uniswap"    && <UniswapV2View signer={signer} account={account} chainId={chainId} />}
      </div>
    </div>
  );
}
