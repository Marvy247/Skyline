'use client'

/**
 * The CEP badge — the headline element.
 *
 * It reports whether Curator Exit Parity currently holds, computed by the hook
 * itself (`verifyCep`) rather than by this dashboard. The badge is a *reader*
 * of the protocol's own invariant, which is exactly the point: anyone can
 * check.
 */

import { motion } from "framer-motion"
import { ShieldCheck, ShieldAlert, ShieldX, CircleDot } from "lucide-react"

import { cn } from "@/lib/utils"
import { formatLiquidity } from "@/lib/format"
import type { MandateState } from "@/hooks/use-mandate"

export function CepBadge({
  state,
  className,
}: {
  state: MandateState
  className?: string
}) {
  const holds = state.verifyCep.cepHolds
  const mayExit = state.verifyCep.curatorMayExit

  const config = holds
    ? {
        tone: "emerald",
        icon: ShieldCheck,
        headline: "Curator Exit Parity: ENFORCED",
        detail:
          state.pendingLiquidity > 0n
            ? `The curator cannot exit — ${formatLiquidity(state.pendingLiquidity)} liquidity units of depositor obligation are outstanding.`
            : "No outstanding obligations. The curator's exit is permitted.",
      }
    : {
        tone: "red",
        icon: ShieldX,
        headline: "Curator Exit Parity: BREACHED",
        detail: "The hook's ledger and the claim set disagree. Investigate immediately.",
      }

  const Icon = config.icon
  const tones = {
    emerald: {
      ring: "border-emerald-200 bg-emerald-50/70",
      icon: "bg-emerald-500 text-white",
      text: "text-emerald-700",
      sub: "text-emerald-600/80",
    },
    red: {
      ring: "border-red-200 bg-red-50/70",
      icon: "bg-red-500 text-white",
      text: "text-red-700",
      sub: "text-red-600/80",
    },
  } as const
  const t = tones[config.tone as "emerald" | "red"]

  return (
    <motion.div
      initial={{ opacity: 0, scale: 0.97 }}
      animate={{ opacity: 1, scale: 1 }}
      transition={{ duration: 0.5, ease: [0.22, 1, 0.36, 1] }}
      className={cn(
        "relative overflow-hidden rounded-2xl border p-6 shadow-sm",
        t.ring,
        className,
      )}
    >
      <div
        className={cn(
          "pointer-events-none absolute -right-16 -top-16 h-48 w-48 rounded-full blur-3xl",
          holds ? "bg-emerald-400/15" : "bg-red-400/15",
        )}
        aria-hidden="true"
      />
      <div className="relative z-10 flex items-start gap-4">
        <motion.div
          animate={holds ? { scale: [1, 1.04, 1] } : { scale: [1, 0.97, 1] }}
          transition={{ duration: 2.4, repeat: Infinity, ease: "easeInOut" }}
          className={cn(
            "flex h-12 w-12 shrink-0 items-center justify-center rounded-2xl shadow-lg",
            t.icon,
          )}
        >
          <Icon className="h-6 w-6" />
        </motion.div>
        <div className="min-w-0 flex-1">
          <div className="flex flex-wrap items-center gap-2">
            <p className={cn("text-lg font-black tracking-tight", t.text)}>{config.headline}</p>
            {state.demo ? (
              <span className="rounded-full bg-slate-900/80 px-2 py-0.5 text-[10px] font-bold uppercase tracking-wider text-white">
                Demo fixture
              </span>
            ) : null}
          </div>
          <p className={cn("mt-1 text-sm", t.sub)}>{config.detail}</p>

          <div className="mt-4 grid grid-cols-2 gap-3 sm:grid-cols-4">
            <Badge
              label="Pending obligation"
              value={`${formatLiquidity(state.pendingLiquidity)} liq`}
              tone={state.pendingLiquidity > 0n ? "amber" : "slate"}
            />
            <Badge
              label="Curator liquidity"
              value={`${formatLiquidity(state.curatorLiquidity)} liq`}
              tone="slate"
            />
            <Badge
              label="Depositor liquidity"
              value={`${formatLiquidity(state.depositorLiquidity)} liq`}
              tone="slate"
            />
            <Badge
              label="Curator may exit"
              value={mayExit ? "Yes" : "No"}
              tone={mayExit ? "emerald" : "red"}
            />
          </div>
        </div>
      </div>
    </motion.div>
  )
}

function Badge({
  label,
  value,
  tone,
}: {
  label: string
  value: string
  tone: "slate" | "amber" | "emerald" | "red"
}) {
  const tones = {
    slate: "bg-white/70 text-slate-700 ring-slate-200",
    amber: "bg-amber-50 text-amber-700 ring-amber-200",
    emerald: "bg-emerald-50 text-emerald-700 ring-emerald-200",
    red: "bg-red-50 text-red-700 ring-red-200",
  } as const
  return (
    <div className={cn("rounded-xl px-3 py-2 ring-1", tones[tone])}>
      <p className="flex items-center gap-1 text-[10px] font-semibold uppercase tracking-wider opacity-70">
        <CircleDot className="h-2.5 w-2.5" />
        {label}
      </p>
      <p className="mt-0.5 text-sm font-bold">{value}</p>
    </div>
  )
}
