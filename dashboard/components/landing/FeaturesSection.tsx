'use client'

import { motion } from "framer-motion"
import { Fingerprint, Ban, ArrowRight, Gauge } from "lucide-react"

const FEATURES = [
  {
    icon: Fingerprint,
    title: "Anyone can verify",
    body: "The curator's bond balance and the outstanding obligations are recomputed from the Uniswap v4 pool itself. No trust in the vault's books — or in our dashboard.",
  },
  {
    icon: Ban,
    title: "Depositors are never locked out",
    body: "Skyline reorders who leaves first. It never prevents a depositor from exiting; a pro-rata/expiry last resort guarantees liveness.",
  },
  {
    icon: Gauge,
    title: "Mandates are enforced where liquidity changes",
    body: "Fee cap, tick band and minimum skin are checked in the hook at the point of action — not in a policy layer above it, where a curator could route around them.",
  },
]

export function FeaturesSection() {
  return (
    <section id="features" className="relative py-24 px-5 sm:px-8 bg-slate-50/60 border-y border-slate-200">
      <div className="mx-auto max-w-6xl">
        <div className="grid gap-12 lg:grid-cols-[minmax(0,1fr)_minmax(0,1.15fr)] lg:gap-20">
          <motion.div
            initial={{ opacity: 0, x: -18 }}
            whileInView={{ opacity: 1, x: 0 }}
            viewport={{ once: true, margin: "-100px" }}
            transition={{ duration: 0.6 }}
          >
            <p className="text-xs font-bold uppercase tracking-[0.2em] text-sky-600">Core features</p>
            <h2 className="mt-3 text-3xl sm:text-4xl font-black tracking-tight text-slate-900 leading-tight">
              Built to be checked, not believed.
            </h2>
            <p className="mt-5 text-slate-600 leading-relaxed">
              A curated-liquidity protocol asks depositors for trust before it has earned any. Skyline
              tries to replace that trust with arithmetic that anyone can re-run.
            </p>
            <p className="mt-4 text-slate-600 leading-relaxed">
              The central claim — a curator cannot exit ahead of outstanding depositor obligations —
              is an invariant in our test suite, not a sentence in a whitepaper.
            </p>
          </motion.div>

          <div className="space-y-4">
            {FEATURES.map((feature, i) => (
              <motion.div
                key={feature.title}
                initial={{ opacity: 0, y: 16 }}
                whileInView={{ opacity: 1, y: 0 }}
                viewport={{ once: true, margin: "-80px" }}
                transition={{ duration: 0.5, delay: i * 0.1 }}
                className="flex items-start gap-4 rounded-2xl border border-slate-200 bg-white p-6"
              >
                <div className="flex h-11 w-11 shrink-0 items-center justify-center rounded-2xl bg-sky-500/10 text-sky-600">
                  <feature.icon className="h-5 w-5" />
                </div>
                <div>
                  <h3 className="text-base font-bold text-slate-900">{feature.title}</h3>
                  <p className="mt-1.5 text-sm leading-relaxed text-slate-600">{feature.body}</p>
                </div>
              </motion.div>
            ))}
          </div>
        </div>
      </div>
    </section>
  )
}
