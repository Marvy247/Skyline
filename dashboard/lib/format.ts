/**
 * Formatting helpers for the Skyline dashboard.
 *
 * Everything here is display-only. No value in this file is ever used to make a
 * financial decision — the contracts are the source of truth.
 */

/** Format a raw uint256/int128 (wei or 18-decimal) as a compact USDC-style amount. */
export function formatUnits(value: bigint | undefined | null, decimals = 18, maxFrac = 2): string {
  if (value === undefined || value === null) return "—"
  const negative = value < 0n
  const v = negative ? -value : value
  const base = 10n ** BigInt(decimals)
  const whole = v / base
  const frac = v % base
  const fracStr = frac === 0n ? "" : `.${frac.toString().padStart(decimals, "0").slice(0, maxFrac)}`
  return `${negative ? "-" : ""}${whole.toLocaleString("en-US")}${fracStr}`
}

/** Format an amount of pool liquidity units. These are dimensionless, so we show them raw. */
export function formatLiquidity(value: bigint | number | undefined | null, maxFrac = 0): string {
  if (value === undefined || value === null) return "—"
  const n = typeof value === "bigint" ? Number(value) : value
  if (!Number.isFinite(n)) return "—"
  return n.toLocaleString("en-US", { maximumFractionDigits: maxFrac })
}

/** Format basis points as a percentage string, e.g. 1000 -> "10.00%". */
export function formatBps(bps: number | bigint | undefined | null, maxFrac = 2): string {
  if (bps === undefined || bps === null) return "—"
  const n = typeof bps === "bigint" ? Number(bps) : bps
  return `${(n / 100).toFixed(maxFrac)}%`
}

/** Format a unix timestamp (seconds) as a relative time, e.g. "in 23h" / "6m ago". */
export function formatRelativeTime(unixSeconds: bigint | number | undefined | null): string {
  if (unixSeconds === undefined || unixSeconds === null) return "—"
  const ts = typeof unixSeconds === "bigint" ? Number(unixSeconds) : unixSeconds
  if (!ts) return "—"
  const delta = ts - Math.floor(Date.now() / 1000)
  const abs = Math.abs(delta)
  const suffix = delta >= 0 ? "in " : ""
  const prefix = delta < 0 ? "" : ""
  if (abs < 60) return `${prefix}${suffix}${abs}s`
  if (abs < 3600) return `${prefix}${suffix}${Math.floor(abs / 60)}m`
  if (abs < 86400) return `${prefix}${suffix}${Math.floor(abs / 3600)}h`
  return `${prefix}${suffix}${Math.floor(abs / 86400)}d`
}

/** Format a unix timestamp as an absolute UTC string. */
export function formatAbsoluteTime(unixSeconds: bigint | number | undefined | null): string {
  if (unixSeconds === undefined || unixSeconds === null) return "—"
  const ts = typeof unixSeconds === "bigint" ? Number(unixSeconds) : unixSeconds
  if (!ts) return "—"
  return new Date(ts * 1000).toISOString().replace("T", " ").slice(0, 19) + " UTC"
}

/** Shorten an address for display: 0x1234…abcd */
export function shortAddress(address?: string | null, size = 4): string {
  if (!address) return "—"
  if (address.length <= size * 2 + 2) return address
  return `${address.slice(0, size + 2)}…${address.slice(-size)}`
}

/** Format a price with a sensible number of significant digits. */
export function formatPrice(value: number | undefined | null, digits = 4): string {
  if (value === undefined || value === null || !Number.isFinite(value)) return "—"
  if (value === 0) return "0"
  if (value < 0.0001) return value.toExponential(3)
  return value.toLocaleString("en-US", { maximumFractionDigits: digits })
}

/** Human label for the hook risk state enum. */
export function riskStateLabel(state: number | undefined | null): string {
  switch (state) {
    case 0:
      return "Normal"
    case 1:
      return "Restricted"
    case 2:
      return "Breached"
    default:
      return "Unknown"
  }
}

/** Human label for the claim status enum. */
export function claimStatusLabel(status: number | undefined | null): string {
  switch (status) {
    case 0:
      return "None"
    case 1:
      return "Registered"
    case 2:
      return "Settled"
    case 3:
      return "Expired"
    case 4:
      return "Partially settled"
    default:
      return "Unknown"
  }
}
