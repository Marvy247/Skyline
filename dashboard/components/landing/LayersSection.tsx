'use client'

import { motion } from "framer-motion"
import { ShieldCheck, ListChecks, Lock, TrendingDown } from "lucide-react"

const LAYERS = [
  {
    icon: ShieldCheck,
    step: "01",
    title: "Curator bond",
    body: "The curator posts their own capital into the same pool, in a separate Uniswap v4 position distinguished by its salt. Anyone can read it from pool state.",
    tag: "vault + hook",
  },
  {
    icon: ListChecks,
    step: "02",
    title: "Hook-owned obligation ledger",
    body: "Depositors withdraw by registering claims. The hook records outstanding obligations in its own storage — it never asks the vault whether any exist.",
    tag: "hook",
  },
  {
    icon: Lock,
    step: "03",
    title: "Enforced exit priority",
    body: "Any removal of curator-bonded liquidity is rejected while obligations are unsettled. The check runs inside the PoolManager, so no router, aggregator or buggy vault can route around it.",
    tag: "hook",
  },
  {
    icon: TrendingDown,
    step: "04",
    title: "Last-resort drawdown",
    body: "If depositor liquidity provably cannot cover an obligation, the bond supplies the remainder, bounded by the shortfall, and the proceeds go to the depositor. A market loss is never charged to the curator.",
    tag: "vault, gated by hook",
  },
]

export function LayersSection() {
  return (
    <section id="mechanism" className="relative py-24 px-5 sm:px-8">
      <div className="mx-auto max-w-6xl">
        <div className="max-w-2xl">
          <p className="text-xs font-bold uppercase tracking-[0.2em] text-sky-600">
            Curator Exit Parity
          </p>
          <h2 className="mt-3 text-3xl sm:text-4xl font-black tracking-tight text-slate-900 leading-tight">
            Four layers. The hook carries the two that matter.
          </h2>
          <p className="mt-5 text-slate-600 leading-relaxed">
            Skyline is not a vault with a hook attached. Delete the hook and the protocol does not
            weaken — it stops existing. The ledger and the gate live in the hook; the vault only
            accounts.
          </p>
        </div>

        <div className="mt-14 grid gap-5 sm:grid-cols-2">
          {LAYERS.map((layer, i) => (
            <motion.div
              key={layer.step}
              initial={{ opacity: 0, y: 18 }}
              whileInView={{ opacity: 1, y: 0 }}
              viewport={{ once: true, margin: "-80px" }}
              transition={{ duration: 0.5, delay: i * 0.08 }}
              className="group relative overflow-hidden rounded-2xl border border-slate-200 bg-white p-7 transition-all hover:border-sky-300 hover:shadow-xl hover:shadow-sky-900/5"
            >
              <div className="flex items-start justify-between">
                <div className="flex h-11 w-11 items-center justify-center rounded-2xl bg-sky-500/10 text-sky-600 transition-transform group-hover:scale-110">
                  <layer.icon className="h-5 w-5" />
                </div>
                <span className="font-mono text-3xl font-black text-slate-100 transition-colors group-hover:text-sky-100">
                  {layer.step}
                </span>
              </div>
              <h3 className="mt-5 text-lg font-bold text-slate-900">{layer.title}</h3>
              <p className="mt-2 text-sm leading-relaxed text-slate-600">{layer.body}</p>
              <p className="mt-4 inline-block rounded-full bg-slate-100 px-3 py-1 font-mono text-[11px] font-semibold text-slate-600">
                enforced in: {layer.tag}
              </p>
            </motion.div>
          ))}
        </div>
      </div>
    </section>
  )
}
