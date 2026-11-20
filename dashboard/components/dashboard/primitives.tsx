'use client'

/**
 * Shared presentational primitives for the Skyline dashboard.
 *
 * Visual language: light slate canvas, white glass cards, sky accent for the
 * protocol, emerald for "enforced / healthy", amber for "attention", red for
 * "blocked".
 */

import { motion } from "framer-motion"
import { cn } from "@/lib/utils"

export function Panel({
  children,
  className,
  delay = 0,
}: {
  children: React.ReactNode
  className?: string
  delay?: number
}) {
  return (
    <motion.section
      initial={{ opacity: 0, y: 14 }}
      animate={{ opacity: 1, y: 0 }}
      transition={{ duration: 0.4, delay, ease: [0.22, 1, 0.36, 1] }}
      className={cn(
        "rounded-2xl border border-slate-200 bg-white shadow-sm shadow-slate-900/[0.03]",
        className,
      )}
    >
      {children}
    </motion.section>
  )
}

export function PanelHeader({
  icon,
  title,
  subtitle,
  accent = "sky",
  right,
}: {
  icon?: React.ReactNode
  title: string
  subtitle?: string
  accent?: "sky" | "emerald" | "amber" | "red"
  right?: React.ReactNode
}) {
  const accents = {
    sky: "bg-sky-500/10 text-sky-600 ring-sky-500/20",
    emerald: "bg-emerald-500/10 text-emerald-600 ring-emerald-500/20",
    amber: "bg-amber-500/10 text-amber-600 ring-amber-500/20",
    red: "bg-red-500/10 text-red-600 ring-red-500/20",
  } as const

  return (
    <div className="flex items-start justify-between gap-4 border-b border-slate-100 px-6 py-5">
      <div className="flex items-start gap-3">
        {icon ? (
          <div
            className={cn(
              "flex h-9 w-9 shrink-0 items-center justify-center rounded-xl ring-1",
              accents[accent],
            )}
          >
            {icon}
          </div>
        ) : null}
        <div>
          <h2 className="text-base font-bold tracking-tight text-slate-900">{title}</h2>
          {subtitle ? <p className="mt-0.5 text-xs text-slate-500">{subtitle}</p> : null}
        </div>
      </div>
      {right}
    </div>
  )
}

export function StatTile({
  label,
  value,
  hint,
  tone = "neutral",
  className,
}: {
  label: string
  value: React.ReactNode
  hint?: React.ReactNode
  tone?: "neutral" | "sky" | "emerald" | "amber" | "red"
  className?: string
}) {
  const tones = {
    neutral: "text-slate-900",
    sky: "text-sky-600",
    emerald: "text-emerald-600",
    amber: "text-amber-600",
    red: "text-red-600",
  } as const

  return (
    <div className={cn("rounded-xl border border-slate-200 bg-slate-50/60 p-4", className)}>
      <p className="text-[10px] font-semibold uppercase tracking-wider text-slate-500">{label}</p>
      <p className={cn("mt-1.5 text-2xl font-black tracking-tight", tones[tone])}>{value}</p>
      {hint ? <p className="mt-1 text-xs text-slate-500">{hint}</p> : null}
    </div>
  )
}

export function Pill({
  children,
  tone = "slate",
  className,
}: {
  children: React.ReactNode
  tone?: "slate" | "sky" | "emerald" | "amber" | "red"
  className?: string
}) {
  const tones = {
    slate: "bg-slate-100 text-slate-600 ring-slate-200",
    sky: "bg-sky-50 text-sky-700 ring-sky-200",
    emerald: "bg-emerald-50 text-emerald-700 ring-emerald-200",
    amber: "bg-amber-50 text-amber-700 ring-amber-200",
    red: "bg-red-50 text-red-700 ring-red-200",
  } as const

  return (
    <span
      className={cn(
        "inline-flex items-center gap-1.5 rounded-full px-2.5 py-1 text-[11px] font-semibold ring-1",
        tones[tone],
        className,
      )}
    >
      {children}
    </span>
  )
}

export function Meter({
  value,
  total,
  threshold,
  segments,
}: {
  value: bigint
  total: bigint
  threshold?: number
  segments?: { label: string; value: bigint; color: string }[]
}) {
  const denom = total > 0n ? total : 1n
  const pct = Number((value * 10_000n) / denom) / 100
  const thresholdPct = threshold !== undefined ? threshold / 100 : undefined

  return (
    <div className="space-y-2">
      <div className="relative h-3 w-full overflow-hidden rounded-full bg-slate-100">
        {segments ? (
          <div className="flex h-full w-full">
            {segments.map((s) => {
              const p = Number((s.value * 10_000n) / denom) / 100
              return (
                <div
                  key={s.label}
                  className={s.color}
                  style={{ width: `${Math.max(0, p)}%` }}
                  title={`${s.label}: ${p.toFixed(1)}%`}
                />
              )
            })}
          </div>
        ) : (
          <div
            className="h-full rounded-full bg-gradient-to-r from-sky-500 to-cyan-400"
            style={{ width: `${Math.min(100, Math.max(0, pct))}%` }}
          />
        )}
        {thresholdPct !== undefined ? (
          <div
            className="absolute top-0 h-full w-px bg-slate-900/40"
            style={{ left: `${Math.min(100, thresholdPct)}%` }}
            title={`mandate minimum ${thresholdPct}%`}
          />
        ) : null}
      </div>
      {segments ? (
        <div className="flex flex-wrap gap-x-4 gap-y-1">
          {segments.map((s) => (
            <div key={s.label} className="flex items-center gap-1.5 text-[11px] text-slate-600">
              <span className={cn("h-2 w-2 rounded-full", s.color)} />
              {s.label}
            </div>
          ))}
        </div>
      ) : null}
    </div>
  )
}

export function KeyValue({
  label,
  value,
  mono = false,
}: {
  label: string
  value: React.ReactNode
  mono?: boolean
}) {
  return (
    <div className="flex items-center justify-between gap-4 border-b border-slate-100 py-2.5 last:border-0">
      <span className="text-xs text-slate-500">{label}</span>
      <span
        className={cn(
          "text-right text-sm font-semibold text-slate-800",
          mono && "font-mono text-xs",
        )}
      >
        {value}
      </span>
    </div>
  )
}

export function EmptyState({ children }: { children: React.ReactNode }) {
  return (
    <div className="rounded-xl border border-dashed border-slate-300 bg-slate-50/60 px-4 py-8 text-center text-sm text-slate-500">
      {children}
    </div>
  )
}
