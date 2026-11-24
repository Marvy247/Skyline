'use client'

import { motion } from "framer-motion"
import Link from "next/link"
import { ArrowRight, Terminal } from "lucide-react"

const BEATS = [
  {
    n: "01",
    title: "A depositor registers a claim",
    body: "The hook records the obligation in its own ledger. The curator's position is immediately restricted.",
  },
  {
    n: "02",
    title: "The curator tries to exit",
    body: "The hook rejects the removal. The revert is decoded and shown in plain English — no hex, no jargon.",
  },
  {
    n: "03",
    title: "Claims settle from depositor liquidity",
    body: "The curator stays locked while claims are served. If depositor liquidity provably cannot cover an obligation, the bond supplies the remainder, bounded by the shortfall. A market loss is never charged to it.",
  },
]

export function DemoSection() {
  return (
    <section id="demo" className="relative py-24 px-5 sm:px-8">
      <div className="mx-auto max-w-5xl">
        <div className="text-center">
          <p className="text-xs font-bold uppercase tracking-[0.2em] text-sky-600">The demo</p>
          <h2 className="mt-3 text-3xl sm:text-4xl font-black tracking-tight text-slate-900 leading-tight">
            One sentence: the curator cannot run.
          </h2>
          <p className="mx-auto mt-5 max-w-2xl text-slate-600 leading-relaxed">
            A live testnet deployment, a seeded scenario, and three beats that fit in ninety
            seconds.
          </p>
        </div>

        <div className="mt-14 grid gap-5 md:grid-cols-3">
          {BEATS.map((beat, i) => (
            <motion.div
              key={beat.n}
              initial={{ opacity: 0, y: 18 }}
              whileInView={{ opacity: 1, y: 0 }}
              viewport={{ once: true, margin: "-80px" }}
              transition={{ duration: 0.5, delay: i * 0.1 }}
              className="relative overflow-hidden rounded-2xl border border-slate-200 bg-white p-6"
            >
              <span className="font-mono text-xs font-black tracking-widest text-sky-500">
                {beat.n}
              </span>
              <h3 className="mt-3 text-base font-bold text-slate-900">{beat.title}</h3>
              <p className="mt-2 text-sm leading-relaxed text-slate-600">{beat.body}</p>
            </motion.div>
          ))}
        </div>

        <motion.div
          initial={{ opacity: 0, y: 16 }}
          whileInView={{ opacity: 1, y: 0 }}
          viewport={{ once: true }}
          transition={{ duration: 0.6, delay: 0.3 }}
          className="mt-12 flex flex-col items-center gap-6"
        >
          <div className="w-full overflow-hidden rounded-2xl border border-slate-200 bg-slate-950 p-6 shadow-xl shadow-slate-900/20">
            <div className="flex items-center gap-2 text-slate-500">
              <Terminal className="h-4 w-4" />
              <span className="font-mono text-xs">demo run</span>
            </div>
            <pre className="mt-4 overflow-x-auto font-mono text-[11px] leading-relaxed sm:text-xs">
{`$ cast send --from $CURATOR "requestCuratorExit()"

⛽ reverted with custom error 'CuratorExitBlocked(55556)'
   "The hook blocked the curator's exit: 55,556 liquidity units
    of depositor obligation are still unsettled."`}
            </pre>
          </div>

          <Link
            href="/dashboard"
            className="inline-flex items-center gap-2 rounded-2xl bg-gradient-to-r from-sky-600 to-sky-500 px-7 py-3.5 text-base font-bold text-white shadow-xl shadow-sky-900/20 transition-all hover:from-sky-500 hover:to-sky-400"
          >
            Open the live dashboard
            <ArrowRight className="h-4 w-4" />
          </Link>
        </motion.div>
      </div>
    </section>
  )
}
