'use client'

/**
 * Verifier panel — "anyone can check".
 *
 * The hook recomputes the curator's bond and the outstanding obligations
 * directly from pool state and compares them with its own records. Matching
 * numbers mean the vault's books and the chain agree, without trusting either.
 *
 * This is the strongest answer to "isn't this just a vault?" — the dashboard
 * shows the protocol's own independent check.
 */

import { Fingerprint, CheckCircle2, XCircle } from "lucide-react"

import { cn } from "@/lib/utils"
import { formatLiquidity } from "@/lib/format"
import { Panel, PanelHeader } from "@/components/dashboard/primitives"
import type { MandateState } from "@/hooks/use-mandate"

export function VerifierPanel({ state }: { state: MandateState }) {
  const bondMatch = state.verifyCuratorBond.poolDerived === state.verifyCuratorBond.recorded
  const pendingMatch = state.verifyPending.derived === state.verifyPending.recorded
  const allMatch = bondMatch && pendingMatch && state.verifyCep.cepHolds

  return (
    <Panel>
      <PanelHeader
        icon={<Fingerprint className="h-4 w-4" />}
        title="Independent verification"
        subtitle="Recomputed from pool state. No trust in the vault's books required."
        accent={allMatch ? "emerald" : "red"}
        right={
          <span
            className={cn(
              "rounded-full px-2.5 py-1 text-[11px] font-bold ring-1",
              allMatch
                ? "bg-emerald-50 text-emerald-700 ring-emerald-200"
                : "bg-red-50 text-red-700 ring-red-200",
            )}
          >
            {allMatch ? "All checks pass" : "Mismatch"}
          </span>
        }
      />

      <div className="space-y-3 px-6 py-5">
        <Check
          ok={bondMatch}
          label="Curator bond"
          leftLabel="derived from pool state"
          leftValue={`${formatLiquidity(state.verifyCuratorBond.poolDerived)} liq`}
          rightLabel="recorded by the hook"
          rightValue={`${formatLiquidity(state.verifyCuratorBond.recorded)} liq`}
        />
        <Check
          ok={pendingMatch}
          label="Outstanding obligation"
          leftLabel="derived from the claim set"
          leftValue={`${formatLiquidity(state.verifyPending.derived)} liq`}
          rightLabel="recorded by the hook"
          rightValue={`${formatLiquidity(state.verifyPending.recorded)} liq`}
        />
        <Check
          ok={state.verifyCep.cepHolds}
          label="Curator Exit Parity"
          leftLabel="invariant"
          leftValue={state.verifyCep.cepHolds ? "holds" : "breached"}
          rightLabel="curator may exit"
          rightValue={state.verifyCep.curatorMayExit ? "yes" : "no"}
        />

        <p className="rounded-xl border border-slate-200 bg-slate-50/60 p-4 text-xs leading-relaxed text-slate-500">
          These values come from <code className="font-mono">verifyCep</code>,{" "}
          <code className="font-mono">verifyCuratorBond</code> and{" "}
          <code className="font-mono">verifyPending</code> on the Skyline hook. The hook derives
          them from the Uniswap v4 pool itself, so a depositor, an auditor or a rival curator can
          confirm the protocol&apos;s state without trusting the vault — and without trusting this
          dashboard.
        </p>
      </div>
    </Panel>
  )
}

function Check({
  ok,
  label,
  leftLabel,
  leftValue,
  rightLabel,
  rightValue,
}: {
  ok: boolean
  label: string
  leftLabel: string
  leftValue: string
  rightLabel: string
  rightValue: string
}) {
  return (
    <div
      className={cn(
        "flex items-center justify-between gap-4 rounded-xl border p-4",
        ok ? "border-emerald-200 bg-emerald-50/50" : "border-red-200 bg-red-50/50",
      )}
    >
      <div className="flex min-w-0 items-center gap-3">
        {ok ? (
          <CheckCircle2 className="h-5 w-5 shrink-0 text-emerald-600" />
        ) : (
          <XCircle className="h-5 w-5 shrink-0 text-red-600" />
        )}
        <div className="min-w-0">
          <p className="text-sm font-bold text-slate-900">{label}</p>
          <p className="truncate text-xs text-slate-500">
            {leftLabel}: <span className="font-mono">{leftValue}</span>
          </p>
        </div>
      </div>
      <div className="shrink-0 text-right">
        <p className="text-[10px] uppercase tracking-wider text-slate-400">{rightLabel}</p>
        <p className="font-mono text-sm font-bold text-slate-800">{rightValue}</p>
      </div>
    </div>
  )
}
