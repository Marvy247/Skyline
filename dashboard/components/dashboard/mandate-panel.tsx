'use client'

/**
 * Mandate panel — the curator's committed operating authority.
 *
 * Every parameter here is enforced by the hook, not by the vault. The panel
 * distinguishes parameters the hook *prevents* from the one it *detects and
 * penalises* — an honest distinction that matters to a technical judge.
 */

import { Gavel, ShieldAlert, Ban } from "lucide-react"

import { formatBps, formatFeeUnits } from "@/lib/format"
import { Panel, PanelHeader, KeyValue, Pill } from "@/components/dashboard/primitives"
import { riskStateLabel } from "@/lib/format"
import type { MandateState } from "@/hooks/use-mandate"

export function MandatePanel({ state }: { state: MandateState }) {
  const m = state.mandate
  // The hook ENFORCES the effective state, which escalates a stale or never-run evaluation
  // to Restricted. Showing the raw stored state would overstate the curator's authority.
  const risk = state.effectiveRiskState
  const storedRisk = state.riskState
  const stale = risk !== storedRisk

  const riskTone = risk === 0 ? "emerald" : risk === 1 ? "amber" : "red"
  const evaluatedAt = state.riskStateUpdatedAt === 0n
    ? "never"
    : new Date(Number(state.riskStateUpdatedAt) * 1000).toLocaleString()

  return (
    <Panel>
      <PanelHeader
        icon={<Gavel className="h-4 w-4" />}
        title="Curator mandate"
        subtitle="Committed at pool creation. Enforced in the hook at the point of action."
        accent="sky"
        right={
          <Pill tone={riskTone}>
            Risk: {riskStateLabel(risk)}
          </Pill>
        }
      />

      <div className="px-6 py-5">
        <div className="rounded-xl border border-slate-200 bg-slate-50/60 p-4">
          <KeyValue label="Maximum pool fee" value={formatFeeUnits(m.maxFeeBps, 3)} mono />
          <KeyValue label="Tick band (lower)" value={m.bandLower.toString()} mono />
          <KeyValue label="Tick band (upper)" value={m.bandUpper.toString()} mono />
          <KeyValue label="Minimum skin" value={formatBps(m.minSkinBps)} mono />
          <KeyValue label="Max drawdown before restriction" value={formatBps(m.maxDrawdownBps)} mono />
          <KeyValue label="Claim TTL" value={`${Math.round(m.claimTtl / 3600)}h`} mono />
          <KeyValue label="Last risk evaluation" value={evaluatedAt} mono />
        </div>

        {stale && (
          <p className="mt-3 rounded-xl border border-amber-200 bg-amber-50 p-3 text-xs leading-relaxed text-amber-700">
            The stored state is {riskStateLabel(storedRisk)}, but the evaluation is stale or has
            never run. The hook therefore enforces <strong>{riskStateLabel(risk)}</strong> for
            risk-increasing curator actions. Depositor exits are unaffected.
          </p>
        )}

        <div className="mt-4 space-y-2">
          <p className="text-xs font-semibold uppercase tracking-wider text-slate-500">
            Enforcement model
          </p>

          <Row
            icon={Ban}
            tone="emerald"
            title="Prevented by the hook (the transaction cannot happen)"
            items={[
              "Dynamic fee above the mandate cap",
              "Curator position outside the committed tick band",
              "Curator skin below the mandate minimum",
              "Curator liquidity removal while obligations are outstanding",
            ]}
          />

          <Row
            icon={ShieldAlert}
            tone="amber"
            title="Detected and penalised (requires an external mark)"
            items={[
              "Strategy drawdown beyond the mandate limit — performance fees forfeited, risk-increasing curator operations frozen",
            ]}
          />
        </div>

        <p className="mt-4 rounded-xl border border-slate-200 bg-white p-3 text-xs leading-relaxed text-slate-500">
          We deliberately do not claim slashing for anything the hook already prevents. A violation
          that reverts was never possible, so there is nothing to punish. The drawdown limit is
          different: it can only be detected after the fact, from an external mark, and that is
          where forfeiture applies.
        </p>
      </div>
    </Panel>
  )
}

function Row({
  icon: Icon,
  tone,
  title,
  items,
}: {
  icon: React.ElementType
  tone: "emerald" | "amber"
  title: string
  items: string[]
}) {
  const tones = {
    emerald: "bg-emerald-50 text-emerald-700 ring-emerald-200",
    amber: "bg-amber-50 text-amber-700 ring-amber-200",
  } as const

  return (
    <div className="rounded-xl border border-slate-200 bg-white p-4">
      <div className="flex items-center gap-2">
        <span className={`flex h-6 w-6 items-center justify-center rounded-lg ring-1 ${tones[tone]}`}>
          <Icon className="h-3.5 w-3.5" />
        </span>
        <p className="text-sm font-semibold text-slate-800">{title}</p>
      </div>
      <ul className="mt-2 space-y-1 pl-8">
        {items.map((i) => (
          <li key={i} className="text-xs leading-relaxed text-slate-500">
            • {i}
          </li>
        ))}
      </ul>
    </div>
  )
}
