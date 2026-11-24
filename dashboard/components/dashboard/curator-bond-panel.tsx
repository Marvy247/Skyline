'use client'

/**
 * Curator bond panel — the skin in the game.
 *
 * Shows the curator's bonded liquidity, the resulting skin ratio against the
 * mandate minimum, and any bond value delivered to depositors in the
 * last-resort branch.
 */

import { motion } from "framer-motion"
import { ShieldCheck, TrendingDown, Loader2 } from "lucide-react"

import { cn } from "@/lib/utils"
import { formatBps, formatLiquidity, formatUnits, shortAddress } from "@/lib/format"
import { Panel, PanelHeader, StatTile, Meter, KeyValue } from "@/components/dashboard/primitives"
import type { MandateState } from "@/hooks/use-mandate"
import { useMandateActions } from "@/hooks/use-mandate-actions"

export function CuratorBondPanel({
  state,
  derived,
}: {
  state: MandateState
  derived: { total: bigint; skinBps: number; shortfall: bigint }
}) {
  const actions = useMandateActions()

  const belowMinimum = derived.skinBps < state.mandate.minSkinBps
  const delivered = state.uncoveredShortfall > 0n

  return (
    <Panel>
      <PanelHeader
        icon={<ShieldCheck className="h-4 w-4" />}
        title="Curator bond"
        subtitle="Capital at risk, in its own v4 position, subordinated to depositor claims."
        accent={belowMinimum ? "amber" : "sky"}
        right={
          <span className="font-mono text-xs text-slate-500">
            {shortAddress(state.curatorAddress)}
          </span>
        }
      />

      <div className="space-y-5 px-6 py-5">
        <div className="grid grid-cols-2 gap-3 lg:grid-cols-4">
          <StatTile
            label="Curator liquidity"
            value={`${formatLiquidity(state.curatorLiquidity)}`}
            hint="liquidity units"
          />
          <StatTile
            label="Bond value"
            value={formatUnits(state.curatorBondValue, 6)}
            hint="USDC, from pool state"
            tone="sky"
          />
          <StatTile
            label="Skin"
            value={formatBps(derived.skinBps)}
            hint={`mandate minimum ${formatBps(state.mandate.minSkinBps)}`}
            tone={belowMinimum ? "red" : "emerald"}
          />
          <StatTile
            label="Delivered to depositors"
            value={formatUnits(state.uncoveredShortfall, 6)}
            hint={delivered ? "USDC, last-resort branch" : "none"}
            tone={delivered ? "amber" : "neutral"}
          />
        </div>

        <div>
          <p className="mb-2 text-xs font-semibold uppercase tracking-wider text-slate-500">
            Composition of vault-side liquidity
          </p>
          <Meter
            value={state.curatorLiquidity}
            total={derived.total}
            threshold={state.mandate.minSkinBps}
            segments={[
              {
                label: "Curator bond",
                value: state.curatorLiquidity,
                color: "bg-gradient-to-r from-amber-400 to-orange-400",
              },
              {
                label: "Depositor capital",
                value: state.depositorLiquidity,
                color: "bg-gradient-to-r from-sky-500 to-cyan-400",
              },
            ]}
          />
        </div>

        <div className="rounded-xl border border-slate-200 bg-slate-50/60 p-4">
          <KeyValue label="Exit proceeds if the curator exits now" value={`${formatUnits(state.curatorExitProceeds, 6)} USDC`} mono />
          <KeyValue
            label="Deduction at exit"
            value={
              state.uncoveredShortfall > 0n
                ? "none — the delivered value already left the position"
                : "none"
            }
          />
          <KeyValue label="Minimum skin" value={formatBps(state.mandate.minSkinBps)} mono />
        </div>

        {delivered ? (
          <motion.div
            initial={{ opacity: 0, y: 6 }}
            animate={{ opacity: 1, y: 0 }}
            className="rounded-xl border border-amber-200 bg-amber-50/80 p-4"
          >
            <div className="flex items-start gap-3">
              <TrendingDown className="mt-0.5 h-5 w-5 shrink-0 text-amber-600" />
              <div>
                <p className="text-sm font-bold text-amber-900">
                  The bond supplied a last-resort shortfall
                </p>
                <p className="mt-1 text-sm leading-relaxed text-amber-800">
                  Depositor liquidity provably could not cover the obligation. The bond supplied the
                  remainder — {formatUnits(state.uncoveredShortfall, 6)} USDC — and it went to the
                  depositor. The remaining bond is paid out in full; the same value is not deducted
                  twice, and a market loss is never charged here.
                </p>
              </div>
            </div>
          </motion.div>
        ) : null}

        <button
          onClick={() => void actions.curatorDeposit(10_000_000n)}
          disabled={actions.state.status === "pending"}
          className="inline-flex items-center gap-2 rounded-xl border border-slate-300 bg-white px-4 py-2.5 text-sm font-semibold text-slate-700 shadow-sm transition-colors hover:border-sky-400 hover:text-sky-700 disabled:opacity-60"
        >
          {actions.state.status === "pending" ? (
            <Loader2 className="h-4 w-4 animate-spin" />
          ) : null}
          Top up bond (10,000 USDC)
        </button>
      </div>
    </Panel>
  )
}
