import { useState, useCallback } from "react";
import { isAddress, parseEther, parseUnits, formatUnits } from "ethers";
import { useBatchTransfer } from "../hooks/useBatchTransfer";
import { BATCHTRANSFERDELEGATION_DEPLOYED } from "../utils/contract";
import { DEFAULT_NETWORK, NETWORK_LABELS } from "../config";
import TxStatus from "../components/TxStatus";
import AddressLabel from "../components/AddressLabel";

export default function BatchTransferView({ signer, account, chainId }) {
  const networkKey = chainId != null ? String(chainId) : DEFAULT_NETWORK;
  const networkLabel = NETWORK_LABELS[networkKey] || `Chain ${networkKey}`;

  // Provider (read-only, from signer)
  const provider = signer ? signer.provider : null;

  const [delegationAddr, setDelegationAddr] = useState(
    BATCHTRANSFERDELEGATION_DEPLOYED[networkKey] || ""
  );

  const {
    txStatus, txPending, clearTxStatus,
    batchTransfer, batchTransferETH,
    checkDelegation, getTokenInfo,
  } = useBatchTransfer(provider, signer, delegationAddr);

  // ── Delegation status ──
  const [delegated, setDelegated] = useState(false);
  const [delegationImpl, setDelegationImpl] = useState(null);

  // ── ERC20 batch rows ──
  const [erc20Rows, setErc20Rows] = useState([
    { id: 0, token: "", recipient: "", amount: "" },
  ]);

  // ── ETH batch rows ──
  const [ethRows, setEthRows] = useState([
    { id: 0, recipient: "", amount: "" },
  ]);

  // ── Token info cache ──
  const [tokenSymbol, setTokenSymbol] = useState("");
  const [tokenDecimals, setTokenDecimals] = useState(null);

  // ── Check delegation status for connected account ──
  const checkDelegationStatus = useCallback(async () => {
    if (!account) return;
    try {
      const result = await checkDelegation(account);
      setDelegated(result.delegated);
      setDelegationImpl(result.impl || null);
    } catch (e) {
      console.error("checkDelegation:", e);
    }
  }, [account, checkDelegation]);

  // ── Load token info from first ERC20 row ──
  const loadTokenInfo = useCallback(async () => {
    const firstRow = erc20Rows[0];
    if (!firstRow || !firstRow.token || !isAddress(firstRow.token)) return;
    try {
      const info = await getTokenInfo(firstRow.token, account);
      setTokenSymbol(info.symbol);
      setTokenDecimals(info.decimals);
    } catch { /* ignore */ }
  }, [erc20Rows, account, getTokenInfo]);

  // ── ERC20 row management ──
  const addErc20Row = () => {
    setErc20Rows([...erc20Rows, { id: Date.now(), token: "", recipient: "", amount: "" }]);
  };
  const removeErc20Row = (id) => {
    if (erc20Rows.length <= 1) return;
    setErc20Rows(erc20Rows.filter((r) => r.id !== id));
  };
  const updateErc20Row = (id, field, value) => {
    setErc20Rows(erc20Rows.map((r) => (r.id === id ? { ...r, [field]: value } : r)));
  };

  // ── ETH row management ──
  const addEthRow = () => {
    setEthRows([...ethRows, { id: Date.now(), recipient: "", amount: "" }]);
  };
  const removeEthRow = (id) => {
    if (ethRows.length <= 1) return;
    setEthRows(ethRows.filter((r) => r.id !== id));
  };
  const updateEthRow = (id, field, value) => {
    setEthRows(ethRows.map((r) => (r.id === id ? { ...r, [field]: value } : r)));
  };

  // ── Validation ──
  const canBatchTransferERC20 = () => {
    if (!account || !delegationAddr || !isAddress(delegationAddr)) return false;
    return erc20Rows.every((r) =>
      r.token && isAddress(r.token) &&
      r.recipient && isAddress(r.recipient) &&
      r.amount && !isNaN(r.amount) && Number(r.amount) > 0
    );
  };

  const canBatchTransferETH = () => {
    if (!account || !delegationAddr || !isAddress(delegationAddr)) return false;
    return ethRows.every((r) =>
      r.recipient && isAddress(r.recipient) &&
      r.amount && !isNaN(r.amount) && Number(r.amount) > 0
    );
  };

  // ── Executors ──
  const execBatchTransferERC20 = async () => {
    if (!canBatchTransferERC20()) return;
    const tokens = erc20Rows.map((r) => r.token);
    const recipients = erc20Rows.map((r) => r.recipient);
    const amounts = erc20Rows.map((r) => {
      const dec = tokenDecimals != null ? tokenDecimals : 18;
      return parseUnits(r.amount, dec);
    });
    try { await batchTransfer(tokens, recipients, amounts); } catch { /* surfaced in txStatus */ }
  };

  const execBatchTransferETH = async () => {
    if (!canBatchTransferETH()) return;
    const recipients = ethRows.map((r) => r.recipient);
    const amounts = ethRows.map((r) => parseEther(r.amount));
    try { await batchTransferETH(recipients, amounts); } catch { /* surfaced in txStatus */ }
  };

  // ────────────────────────────────────────────────────────────
  //  Render
  // ────────────────────────────────────────────────────────────

  return (
    <>
      {/* ── Connected Account ── */}
      <div className="card">
        <div className="card-header">👤 Connected Account</div>
        {account ? (
          <div style={{ marginBottom: "0.75rem" }}>
            <div style={{ fontSize: "0.85rem", color: "#e2e8f0", fontFamily: "'SF Mono','Fira Code',monospace" }}>
              <AddressLabel address={account} mono />
            </div>
            <div style={{ marginTop: "0.5rem" }}>
              <button className="btn btn-secondary btn-sm" onClick={checkDelegationStatus}>
                🔍 Check Delegation Status
              </button>
              {delegated && (
                <span style={{ marginLeft: "0.75rem", color: "#6ee7b7", fontSize: "0.8rem" }}>
                  ✅ Delegated → <AddressLabel address={delegationImpl} mono />
                </span>
              )}
              {!delegated && delegationImpl === null && (
                <span style={{ marginLeft: "0.75rem", color: "#fbbf24", fontSize: "0.8rem" }}>
                  ⚠ No active delegation
                </span>
              )}
            </div>
          </div>
        ) : (
          <p style={{ color: "#94a3b8", fontSize: "0.85rem" }}>
            Please connect MetaMask first using the button above.
          </p>
        )}
      </div>

      {/* ── Delegation Contract ── */}
      <div className="card">
        <div className="card-header" style={{ display: "flex", justifyContent: "space-between", alignItems: "center" }}>
          <span>📄 BatchTransferDelegation Contract</span>
          <span className="chip active" style={{ fontSize: "0.7rem" }}>🟢 {networkLabel}</span>
        </div>
        <div className="form-group">
          <label className="form-label">Delegation Contract Address</label>
          <input
            className="input"
            value={delegationAddr}
            onChange={(e) => { setDelegationAddr(e.target.value); clearTxStatus(); }}
            placeholder="0x…"
            spellCheck={false}
          />
        </div>
      </div>

      {/* ── ERC20 Batch Transfer ── */}
      <div className="card">
        <div className="card-header">🪙 ERC20 Batch Transfer</div>
        <p style={{ color: "#94a3b8", fontSize: "0.8rem", marginBottom: "0.75rem" }}>
          Send multiple ERC20 transfers atomically in one EIP-7702 transaction.
          Each row = one token transfer. The connected EOA must hold the tokens.
        </p>

        {erc20Rows.map((row, idx) => (
          <div key={row.id} style={{ display: "flex", gap: "0.5rem", marginBottom: "0.5rem", alignItems: "center", flexWrap: "wrap" }}>
            <span style={{ color: "#64748b", fontSize: "0.75rem", minWidth: "20px" }}>{idx + 1}.</span>
            <input
              className="input"
              style={{ flex: "2", minWidth: "140px" }}
              value={row.token}
              onChange={(e) => updateErc20Row(row.id, "token", e.target.value)}
              placeholder="Token address"
              spellCheck={false}
            />
            <input
              className="input"
              style={{ flex: "2", minWidth: "140px" }}
              value={row.recipient}
              onChange={(e) => updateErc20Row(row.id, "recipient", e.target.value)}
              placeholder="Recipient"
              spellCheck={false}
            />
            <input
              className="input"
              style={{ flex: "1", minWidth: "100px" }}
              value={row.amount}
              onChange={(e) => updateErc20Row(row.id, "amount", e.target.value)}
              placeholder="Amount"
              spellCheck={false}
            />
            <button
              className="btn btn-secondary btn-sm"
              disabled={erc20Rows.length <= 1}
              onClick={() => removeErc20Row(row.id)}
              title="Remove row"
            >
              ✕
            </button>
          </div>
        ))}

        <div style={{ display: "flex", gap: "0.5rem", marginBottom: "0.75rem" }}>
          <button className="btn btn-secondary btn-sm" onClick={addErc20Row}>+ Add Row</button>
          <button className="btn btn-secondary btn-sm" disabled={erc20Rows.length <= 1 || !erc20Rows[0].token || !isAddress(erc20Rows[0].token)} onClick={loadTokenInfo}>🔍 Load Token Info</button>
        </div>

        {tokenSymbol && (
          <div style={{ marginBottom: "0.75rem", fontSize: "0.8rem", color: "#94a3b8" }}>
            Token: <span style={{ color: "#6ee7b7" }}>{tokenSymbol}</span>
            {tokenDecimals != null && <>, Decimals: <span style={{ color: "#6ee7b7" }}>{tokenDecimals}</span></>}
          </div>
        )}

        <button
          className="btn btn-primary"
          disabled={!canBatchTransferERC20() || txPending}
          onClick={execBatchTransferERC20}
        >
          {txPending ? "⏳ Processing…" : "🪙 Execute ERC20 Batch Transfer"}
        </button>
        <TxStatus status={txStatus} />
      </div>

      {/* ── ETH Batch Transfer ── */}
      <div className="card">
        <div className="card-header">💎 ETH Batch Transfer</div>
        <p style={{ color: "#94a3b8", fontSize: "0.8rem", marginBottom: "0.75rem" }}>
          Send ETH to multiple recipients atomically in one EIP-7702 transaction.
          ETH comes from the connected EOA&apos;s balance.
        </p>

        {ethRows.map((row, idx) => (
          <div key={row.id} style={{ display: "flex", gap: "0.5rem", marginBottom: "0.5rem", alignItems: "center", flexWrap: "wrap" }}>
            <span style={{ color: "#64748b", fontSize: "0.75rem", minWidth: "20px" }}>{idx + 1}.</span>
            <input
              className="input"
              style={{ flex: "3", minWidth: "200px" }}
              value={row.recipient}
              onChange={(e) => updateEthRow(row.id, "recipient", e.target.value)}
              placeholder="Recipient address"
              spellCheck={false}
            />
            <input
              className="input"
              style={{ flex: "1", minWidth: "120px" }}
              value={row.amount}
              onChange={(e) => updateEthRow(row.id, "amount", e.target.value)}
              placeholder="ETH amount"
              spellCheck={false}
            />
            <button
              className="btn btn-secondary btn-sm"
              disabled={ethRows.length <= 1}
              onClick={() => removeEthRow(row.id)}
              title="Remove row"
            >
              ✕
            </button>
          </div>
        ))}

        <div style={{ marginBottom: "0.75rem" }}>
          <button className="btn btn-secondary btn-sm" onClick={addEthRow}>+ Add Row</button>
        </div>

        <button
          className="btn btn-primary"
          disabled={!canBatchTransferETH() || txPending}
          onClick={execBatchTransferETH}
        >
          {txPending ? "⏳ Processing…" : "💎 Execute ETH Batch Transfer"}
        </button>
        <TxStatus status={txStatus} />
      </div>

      {/* ── How It Works ── */}
      <div className="card">
        <div className="card-header">📖 How EIP-7702 Works Here</div>
        <ol style={{ color: "#94a3b8", fontSize: "0.8rem", paddingLeft: "1.25rem", lineHeight: "1.6" }}>
          <li>Connect an EIP-7702-compatible wallet — <strong>OKX Wallet</strong> is recommended. MetaMask currently blocks external EIP-7702 transactions.</li>
          <li>Fill in the batch transfer details (tokens, recipients, amounts).</li>
          <li>Click &quot;Execute&quot; — the wallet signs the EIP-7702 authorization, then sends a type-4 transaction in one step.</li>
          <li>The type-4 transaction atomically: (1) sets your EOA&apos;s delegation code to <code style={{ color: "#a5b4fc" }}>BatchTransferDelegation</code>, and (2) calls <code style={{ color: "#a5b4fc" }}>batchTransfer</code> / <code style={{ color: "#a5b4fc" }}>batchTransferETH</code> on your own address.</li>
          <li>The delegation contract runs <strong>in your EOA&apos;s context</strong> — tokens transfer directly from your wallet. No approve needed.</li>
        </ol>
      </div>
    </>
  );
}
