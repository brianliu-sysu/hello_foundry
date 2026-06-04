const STYLES = {
  pending: { bg: "#1e3a5f", fg: "#93c5fd" },
  success: { bg: "#064e3b", fg: "#6ee7b7" },
  error:   { bg: "#7f1d1d", fg: "#fca5a5" },
};

export default function TxStatus({ status }) {
  if (!status) return null;
  const s = STYLES[status.type] || STYLES.pending;
  return (
    <div style={{ marginTop: "0.75rem", padding: "0.6rem 0.85rem", borderRadius: "8px", fontSize: "0.8rem", background: s.bg, color: s.fg, wordBreak: "break-word" }}>
      {status.type === "success" ? "✅ " : status.type === "error" ? "❌ " : "⏳ "}
      {status.message}
      {status.explorerUrl && status.explorerUrl !== "#" && (
        <>{" "}<a href={status.explorerUrl} target="_blank" rel="noopener noreferrer" style={{ color: s.fg, textDecoration: "underline" }}>View on explorer</a></>
      )}
    </div>
  );
}
