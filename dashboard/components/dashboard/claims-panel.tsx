'use client'

/**
 * Claims panel — the depositor-side view.
 *
 * Shows the FIFO claim queue, lets a depositor register a withdrawal, and lets
 * anyone settle the queue. Settlement is permissionless in the protocol; this
 * mirrors that.
 */

import { useState } from "react"
import { motion, AnimatePresence } from "framer-motion"
import { ClipboardList, Loader2, PlayCircle, Clock, CheckCircle2, AlertTriangle } from "lucide-react"

import { cn } from "@/lib/utils"
import {
  formatLiquidity,
  formatRelativeTime,
  formatAbsoluteTime,
  formatUnits,
  shortAddress,
  claimStatusLabel,
} from "@/lib/format"
import { Panel, PanelHeader, EmptyState, Pill } from "@/components/dashboard/primitives"
import type { MandateState } from "@/hooks/use-mandate"
import { useMandateActions, parseAssetAmount } from "@/hooks/use-mandate-actions"

export function ClaimsPanel({ state }: { state: MandateState }) {
  const actions = useMandateActions()
  const [amount, setAmount] = useState("0.5")

  const active = state.claims.filter((c) => c.status === 1 || c.status === 4)
  const closed = state.claims.filter((c) => c.status === 2 || c.status === 3)

  return (
    <Panel>
      <PanelHeader
        icon={<ClipboardList className="h-4 w-4" />}
        title="Depositor claim queue"
        subtitle="Recorded on-chain, served FIFO. The hook's ledger is authoritative."
        accent="sky"
        right={
          <Pill tone={active.length > 0 ? "amber" : "emerald"}>
            {active.length} open · {state.nextClaimId} total
          </Pill>
        }
      />

      <div className="space-y-5 px-6 py-5">
        {state.claims.length === 0 ? (
          <EmptyState>
            No claims registered. In the demo scenario, request a withdrawal to create one.
          </EmptyState>
        ) : (
          <div className="space-y-2">
            {state.claims.map((claim) => {
              const remaining = claim.liquidityAmount - claim.settledAmount
              const tone =
                claim.status === 2
                  ? "emerald"
                  : claim.status === 3
                    ? "slate"
                    : claim.status === 4
                      ? "amber"
                      : "sky"

              return (
                <motion.div
                  key={claim.claimId}
                  initial={{ opacity: 0, y: 6 }}
                  animate={{ opacity: 1, y: 0 }}
                  className="rounded-xl border border-slate-200 bg-slate-50/60 p-4"
                >
                  <div className="flex flex-wrap items-center justify-between gap-2">
                    <div className="flex items-center gap-2">
                      <span className="font-mono text-xs font-bold text-slate-500">
                        #{claim.claimId.toString()}
                      </span>
                      <Pill tone={tone as "sky" | "emerald" | "amber" | "slate"}>
                        {claim.status === 1 ? <Clock className="h-3 w-3" /> : null}
                        {claim.status === 2 ? <CheckCircle2 className="h-3 w-3" /> : null}
                        {claim.status === 4 ? <AlertTriangle className="h-3 w-3" /> : null}
                        {claimStatusLabel(claim.status)}
                      </Pill>
                    </div>
                    <span className="font-mono text-xs text-slate-500">
                      {shortAddress(claim.depositor)}
                    </span>
                  </div>

                  <div className="mt-3 grid grid-cols-2 gap-3 sm:grid-cols-4">
                    <Cell label="Liquidity owed" value={`${formatLiquidity(claim.liquidityAmount)} liq`} />
                    <Cell label="Settled" value={`${formatLiquidity(claim.settledAmount)} liq`} />
                    <Cell label="Remaining" value={`${formatLiquidity(remaining)} liq`} />
                    <Cell
                      label={claim.status === 3 ? "Expired at" : "Expires"}
                      value={formatRelativeTime(claim.expiresAt)}
                      title={formatAbsoluteTime(claim.expiresAt)}
                    />
                  </div>
                </motion.div>
              )
            })}
          </div>
        )}

        <div className="grid gap-4 border-t border-slate-100 pt-5 sm:grid-cols-2">
          <div className="rounded-xl border border-slate-200 bg-white p-4">
            <p className="text-xs font-semibold uppercase tracking-wider text-slate-500">
              Register a withdrawal (vault shares)
            </p>
            <div className="mt-3 flex gap-2">
              <input
                value={amount}
                onChange={(e) => setAmount(e.target.value)}
                inputMode="decimal"
                placeholder="0.5"
                className="h-10 w-full rounded-lg border border-slate-300 bg-white px-3 text-sm text-slate-900 outline-none transition-colors placeholder:text-slate-400 focus:border-sky-500 focus:ring-2 focus:ring-sky-500/20"
              />
              <button
                onClick={() => {
                  const shares = parseAssetAmount(amount)
                  if (shares > 0n) void actions.requestWithdraw(shares)
                }}
                disabled={actions.state.status === "pending"}
                className="inline-flex h-10 shrink-0 items-center gap-2 rounded-lg bg-sky-600 px-4 text-sm font-bold text-white shadow-sm transition-colors hover:bg-sky-500 disabled:opacity-60"
              >
                {actions.state.status === "pending" ? (
                  <Loader2 className="h-4 w-4 animate-spin" />
                ) : null}
                Request
              </button>
            </div>
            <p className="mt-2 text-xs text-slate-500">
              Registers a FIFO claim for that many shares, redeemed at NAV. The hook records the
              obligation and immediately locks the curator&apos;s exit.
            </p>
          </div>

          <div className="rounded-xl border border-slate-200 bg-white p-4">
            <p className="text-xs font-semibold uppercase tracking-wider text-slate-500">
              Settle the queue
            </p>
            <button
              onClick={() => void actions.settleClaims()}
              disabled={actions.state.status === "pending"}
              className="mt-3 inline-flex h-10 w-full items-center justify-center gap-2 rounded-lg bg-slate-900 px-4 text-sm font-bold text-white shadow-sm transition-colors hover:bg-slate-800 disabled:opacity-60"
            >
              {actions.state.status === "pending" ? (
                <Loader2 className="h-4 w-4 animate-spin" />
              ) : (
                <PlayCircle className="h-4 w-4" />
              )}
              Settle claims (permissionless)
            </button>
            <p className="mt-2 text-xs text-slate-500">
              Serves depositor liquidity first, then the curator&apos;s bond, then pro rata.
            </p>
          </div>
        </div>

        <AnimatePresence>
          {actions.state.status === "error" ? (
            <motion.div
              initial={{ opacity: 0, height: 0 }}
              animate={{ opacity: 1, height: "auto" }}
              exit={{ opacity: 0, height: 0 }}
              className="overflow-hidden"
            >
              <div className="rounded-xl border border-red-200 bg-red-50 p-3">
                <p className="text-xs font-bold text-red-800">
                  {actions.state.errorName ?? "Reverted"}
                </p>
                <p className="mt-0.5 text-xs text-red-700">{actions.state.message}</p>
              </div>
            </motion.div>
          ) : null}
        </AnimatePresence>

        {closed.length > 0 ? (
          <p className="text-xs text-slate-400">
            {closed.length} closed claim{closed.length === 1 ? "" : "s"} hidden from the active queue.
          </p>
        ) : null}
      </div>
    </Panel>
  )
}

function Cell({
  label,
  value,
  title,
}: {
  label: string
  value: string
  title?: string
}) {
  return (
    <div>
      <p className="text-[10px] font-semibold uppercase tracking-wider text-slate-400">{label}</p>
      <p className="mt-0.5 truncate font-mono text-xs font-semibold text-slate-800" title={title}>
        {value}
      </p>
    </div>
  )
}

export function VaultStatsPanel({ state }: { state: MandateState }) {
  const navPerShare = state.navPerShare
  const hwm = state.highWaterMark
  const drawdownBps =
    hwm > navPerShare ? Number(((hwm - navPerShare) * 10_000n) / hwm) : 0

  return (
    <Panel>
      <PanelHeader
        icon={<ClipboardList className="h-4 w-4" />}
        title="Vault position"
        subtitle="Depositor side. Curator bond value is deliberately excluded."
        accent="sky"
      />
      <div className="grid grid-cols-2 gap-3 px-6 py-5 lg:grid-cols-4">
        <Stat
          label="Total assets"
          value={`${formatUnits(state.totalAssets, 6)}`}
          hint="USDC"
        />
        <Stat label="Your shares" value={formatUnits(state.userShares, 6)} hint={`of ${formatUnits(state.totalSupply, 6)}`} />
        <Stat
          label="NAV / share"
          value={navPerShare > 0n ? formatUnits(navPerShare, 18, 4) : "—"}
          hint="USDC"
        />
        <Stat
          label="NAV vs HWM"
          value={`${(drawdownBps / 100).toFixed(2)}%`}
          hint={`HWM ${formatUnits(hwm, 18, 4)}`}
        />
      </div>
    </Panel>
  )
}

function Stat({
  label,
  value,
  hint,
  tone = "neutral",
}: {
  label: string
  value: string
  hint?: string
  tone?: "neutral" | "red"
}) {
  return (
    <div className="rounded-xl border border-slate-200 bg-slate-50/60 p-4">
      <p className="text-[10px] font-semibold uppercase tracking-wider text-slate-500">{label}</p>
      <p
        className={cn(
          "mt-1 text-xl font-black tracking-tight",
          tone === "red" ? "text-red-600" : "text-slate-900",
        )}
      >
        {value}
      </p>
      {hint ? <p className="mt-0.5 text-[11px] text-slate-400">{hint}</p> : null}
    </div>
  )
}
