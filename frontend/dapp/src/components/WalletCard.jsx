import { formatEther } from "ethers";
import AddressLabel from "./AddressLabel";

export default function WalletCard({ account, chainId, ethBalance, connecting, onConnect, onDisconnect }) {
  const connected = !!account;
  return (
    <div className="card">
      <div className="card-header">🔌 Wallet</div>
      <div className="connect-row">
        {!connected ? (
          <button className="btn btn-primary" onClick={onConnect} disabled={connecting}>
            🦊 {connecting ? "Connecting…" : "Connect MetaMask"}
          </button>
        ) : (
          <button className="btn btn-secondary" onClick={onDisconnect}>Disconnect</button>
        )}
        <span className={`badge ${connected ? "badge-connected" : "badge-disconnected"}`}>
          {connected ? "Connected" : "Disconnected"}
        </span>
      </div>
      {connected && (
        <div style={{ marginTop: "1rem" }}>
          <InfoRow label="Address"     value={account} mono />
          <InfoRow label="ETH Balance" value={ethBalance != null ? `${formatEther(ethBalance)} ETH` : "…"} />
          <InfoRow label="Chain ID"    value={chainId ?? "…"} />
        </div>
      )}
    </div>
  );
}

function InfoRow({ label, value, mono }) {
  return (
    <div className="info-row">
      <span className="info-label">{label}</span>
      <span className="info-value" style={mono ? { fontFamily: "'SF Mono','Fira Code',monospace" } : {}}>
        {mono && typeof value === "string" && value.startsWith("0x")
          ? <AddressLabel address={value} mono />
          : value}
      </span>
    </div>
  );
}
