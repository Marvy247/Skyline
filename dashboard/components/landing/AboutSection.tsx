'use client'

import { motion } from "framer-motion"
import { TrendingDown, Users, LogOut, Scale } from "lucide-react"

export function AboutSection() {
  return (
    <section id="problem" className="relative py-24 px-5 sm:px-8 bg-slate-50/60 border-y border-slate-200">
      <div className="mx-auto max-w-6xl">
        <div className="grid gap-14 lg:grid-cols-2 lg:gap-20 items-center">
          <motion.div
            initial={{ opacity: 0, x: -20 }}
            whileInView={{ opacity: 1, x: 0 }}
            viewport={{ once: true, margin: "-100px" }}
            transition={{ duration: 0.6 }}
          >
            <p className="text-xs font-bold uppercase tracking-[0.2em] text-sky-600">The problem</p>
            <h2 className="mt-3 text-3xl sm:text-4xl font-black tracking-tight text-slate-900 leading-tight">
              This isn&apos;t a problem of bad faith. It&apos;s a problem of misaligned exit
              incentives.
            </h2>
            <p className="mt-5 text-slate-600 leading-relaxed">
              Alice deposits $100,000 into a curator&apos;s strategy vault. Bob, the curator, posts
              $10,000 of his own capital as skin in the game. Over the following weeks his strategy
              begins to degrade — his signal fired before the public one did.
            </p>
            <p className="mt-4 text-slate-600 leading-relaxed">
              Nothing requires Bob to be dishonest. His exit is contractually permitted, his
              withdrawal consumes pool liquidity, and the price impact of that removal is borne by
              everyone still inside.
            </p>

            <div className="mt-8 space-y-3">
              {[
                {
                  icon: TrendingDown,
                  title: "Bob recognises the degradation first",
                  body: "An information advantage, entirely legitimate.",
                },
                {
                  icon: LogOut,
                  title: "Bob withdraws",
                  body: "The vault is a plain ERC-4626. Redeem is symmetric. Nothing stops him.",
                },
                {
                  icon: Users,
                  title: "Alice is left holding a worse position",
                  body: "Bob's exit moved the price against the depositors who stayed.",
                },
              ].map((item) => (
                <div
                  key={item.title}
                  className="flex items-start gap-3 rounded-xl border border-slate-200 bg-white p-4"
                >
                  <div className="flex h-9 w-9 shrink-0 items-center justify-center rounded-xl bg-rose-500/10 text-rose-600">
                    <item.icon className="h-4 w-4" />
                  </div>
                  <div>
                    <p className="text-sm font-bold text-slate-900">{item.title}</p>
                    <p className="mt-0.5 text-sm text-slate-500">{item.body}</p>
                  </div>
                </div>
              ))}
            </div>
          </motion.div>

          <motion.div
            initial={{ opacity: 0, x: 20 }}
            whileInView={{ opacity: 1, x: 0 }}
            viewport={{ once: true, margin: "-100px" }}
            transition={{ duration: 0.6, delay: 0.1 }}
            className="rounded-3xl border border-slate-200 bg-white p-8 shadow-xl shadow-slate-900/5"
          >
            <div className="flex items-center gap-3">
              <div className="flex h-11 w-11 items-center justify-center rounded-2xl bg-sky-500/10 text-sky-600">
                <Scale className="h-5 w-5" />
              </div>
              <div>
                <p className="text-sm font-bold text-slate-900">The symmetry is the bug</p>
                <p className="text-xs text-slate-500">Every existing curated-liquidity vault</p>
              </div>
            </div>

            <div className="mt-7 space-y-4">
              <div className="rounded-xl border border-slate-200 bg-slate-50/70 p-4">
                <p className="text-xs font-semibold uppercase tracking-wider text-slate-500">
                  Today
                </p>
                <div className="mt-3 space-y-2">
                  <Row left="Depositor exit" right="symmetric redeem" />
                  <Row left="Curator exit" right="symmetric redeem" />
                  <Row left="Priority" right="none" muted />
                  <Row left="Who absorbs the loss" right="whoever is left" muted />
                </div>
              </div>

              <div className="rounded-xl border border-sky-200 bg-sky-50/70 p-4">
                <p className="text-xs font-semibold uppercase tracking-wider text-sky-700">
                  With Skyline
                </p>
                <div className="mt-3 space-y-2">
                  <Row left="Depositor exit" right="always permitted" good />
                  <Row left="Curator exit" right="junior to claims" good />
                  <Row left="Priority" right="enforced in the hook" good />
                  <Row left="Who absorbs the loss" right="the curator's bond" good />
                </div>
              </div>
            </div>

            <p className="mt-6 text-sm leading-relaxed text-slate-600">
              Withdrawal queues solve timing for depositors. They say nothing about the
              subordination of the manager&apos;s own capital. That is the gap Skyline closes.
            </p>
          </motion.div>
        </div>
      </div>
    </section>
  )
}

function Row({
  left,
  right,
  good,
  muted,
}: {
  left: string
  right: string
  good?: boolean
  muted?: boolean
}) {
  return (
    <div className="flex items-center justify-between gap-4">
      <span className={`text-sm ${muted ? "text-slate-400" : "text-slate-600"}`}>{left}</span>
      <span
        className={`text-sm font-semibold ${
          good ? "text-sky-700" : muted ? "text-slate-400" : "text-slate-800"
        }`}
      >
        {right}
      </span>
    </div>
  )
}
