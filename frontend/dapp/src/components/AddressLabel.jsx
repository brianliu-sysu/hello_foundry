import { useState, useCallback } from "react";

/**
 * 地址展示组件，hover 显示完整地址，点击可复制。
 * @param {string} address   - 完整地址
 * @param {string} mono      - 是否使用等宽字体
 * @param {object} style     - 额外样式
 */
export default function AddressLabel({ address, mono, style: extraStyle }) {
  const [copied, setCopied] = useState(false);

  const copy = useCallback((e) => {
    e.stopPropagation();
    if (!address) return;
    navigator.clipboard.writeText(address).then(() => {
      setCopied(true);
      setTimeout(() => setCopied(false), 1500);
    }).catch(() => {});
  }, [address]);

  if (!address) return null;

  const short = address.slice(0, 6) + "…" + address.slice(-4);

  return (
    <span
      style={{
        position: "relative",
        cursor: "pointer",
        fontFamily: mono ? "'SF Mono','Fira Code',monospace" : undefined,
        ...extraStyle,
      }}
      title={`Click to copy: ${address}`}
      onClick={copy}
    >
      {copied ? (
        <span style={{ color: "#6ee7b7" }}>✓ Copied</span>
      ) : (
        short
      )}
    </span>
  );
}
