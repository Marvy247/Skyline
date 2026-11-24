'use client'

/**
 * The exit ladder.
 *
 * A three-stage visual of where a depositor's withdrawal is served from, and
 * what each stage is for. It is the fastest way to explain the economic
 * asymmetry to a judge who has never heard of Skyline.
 */

import { motion } from "framer-motion"
import { ArrowDown, Users, ShieldAlert, Scale } from "lucide-react"

import { cn } from "@/lib/utils"
import { formatLiquidity } from "@/lib/format"

interface Stage {
  key: string
  title: string
  source: string
  amount: bigint
  tone: "sky" | "amber" | "red"
  icon: React.ElementType
  note: string
}

export function ExitLadder({
  pending,
  depositorLiquidity,
  curatorLiquidity,
}: {
  pending: bigint
  depositorLiquidity: bigint
  curatorLiquidity: bigint
}) {
  const servedByDepositors = pending < depositorLiquidity ? pending : depositorLiquidity
  const shortfall = pending > depositorLiquidity ? pending - depositorLiquidity : 0n
  const bondLastResort = shortfall < curatorLiquidity ? shortfall : curatorLiquidity
  const remainder = shortfall > bondLastResort ? shortfall - bondLastResort : 0n

  const stages: Stage[] = [
    {
      key: "depositor",
      title: "1 · Depositor liquidity",
      source: "the pool's depositor position",
      amount: servedByDepositors,
      tone: "sky",
      icon: Users,
      note: "The depositors' own capital serves their claims. Everyone else stays whole.",
    },
    {
      key: "bond",
      title: "2 · Curator bond — last resort",
      source: "the curator's own bonded position",
      amount: bondLastResort,
      tone: "amber",
      icon: ShieldAlert,
      note: "Only if depositor liquidity provably cannot cover the obligation. The bond supplies at most the shortfall, and the proceeds go to the depositor. A market loss is not charged to it.",
    },
    {
      key: "proRata",
      title: "3 · Pro-rata / expiry fallback",
      source: "remaining claims, shared",
      amount: remainder,
      tone: "red",
      icon: Scale,
      note: "Any remainder is served pro rata across remaining claims. After the claim's TTL anyone can expire it and restore the unserved shares. A depositor is never locked out.",
    },
  ]

  const tones = {
    sky: {
      bar: "from-sky-500 to-cyan-400",
      chip: "bg-sky-50 text-sky-700 ring-sky-200",
      icon: "bg-sky-500/10 text-sky-600",
    },
    amber: {
      bar: "from-amber-500 to-orange-400",
      chip: "bg-amber-50 text-amber-700 ring-amber-200",
      icon: "bg-amber-500/10 text-amber-600",
    },
    red: {
      bar: "from-red-500 to-rose-400",
      chip: "bg-red-50 text-red-700 ring-red-200",
      icon: "bg-red-500/10 text-red-600",
    },
  } as const

  return (
    <div className="space-y-3">
      {stages.map((stage, i) => {
        const t = tones[stage.tone]
        const Icon = stage.icon
        const active = stage.amount > 0n

        return (
          <motion.div
            key={stage.key}
            initial={{ opacity: 0, x: -10 }}
            animate={{ opacity: 1, x: 0 }}
            transition={{ delay: i * 0.08, duration: 0.35 }}
            className={cn(
              "relative overflow-hidden rounded-xl border p-4 transition-opacity",
              active ? "border-slate-200 bg-white" : "border-slate-200 bg-slate-50/50 opacity-60",
            )}
          >
            <div className="flex items-start gap-3">
              <div className={cn("flex h-9 w-9 shrink-0 items-center justify-center rounded-xl", t.icon)}>
                <Icon className="h-4 w-4" />
              </div>
              <div className="min-w-0 flex-1">
                <div className="flex flex-wrap items-center justify-between gap-2">
                  <p className="text-sm font-bold text-slate-900">{stage.title}</p>
                  <span className={cn("rounded-full px-2.5 py-0.5 text-[11px] font-bold ring-1", t.chip)}>
                    {formatLiquidity(stage.amount)} liq
                  </span>
                </div>
                <p className="mt-0.5 text-xs text-slate-500">source: {stage.source}</p>

                <div className="mt-2.5 h-1.5 w-full overflow-hidden rounded-full bg-slate-100">
                  <motion.div
                    initial={{ width: 0 }}
                    animate={{
                      width: `${pending > 0n ? Number((stage.amount * 100n) / pending) : 0}%`,
                    }}
                    transition={{ duration: 0.6, delay: 0.1 + i * 0.08 }}
                    className={cn("h-full rounded-full bg-gradient-to-r", t.bar)}
                  />
                </div>

                <p className="mt-2 text-xs leading-relaxed text-slate-500">{stage.note}</p>
              </div>
            </div>

            {i < stages.length - 1 ? (
              <div className="absolute -bottom-3 left-7 z-10 flex h-6 w-6 items-center justify-center rounded-full border border-slate-200 bg-white text-slate-400">
                <ArrowDown className="h-3 w-3" />
              </div>
            ) : null}
          </motion.div>
        )
      })}

      <p className="pt-1 text-xs leading-relaxed text-slate-500">
        Outstanding obligation:{" "}
        <span className="font-bold text-slate-800">{formatLiquidity(pending)} liquidity units</span> ·
        served from depositor liquidity{" "}
        <span className="font-bold text-slate-800">{formatLiquidity(servedByDepositors)}</span> · bond
        last resort{" "}
        <span className="font-bold text-amber-700">{formatLiquidity(bondLastResort)}</span>{" "}
        · pro-rata remainder{" "}
        <span className="font-bold text-red-700">{formatLiquidity(remainder)}</span>. A market loss
        between request and settlement stays with shares; the bond is untouched.
      </p>
    </div>
  )
}
