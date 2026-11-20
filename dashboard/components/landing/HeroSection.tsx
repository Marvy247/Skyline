'use client'

import { motion } from "framer-motion"
import Link from "next/link"
import { ArrowRight, Lock } from "lucide-react"

export function HeroSection() {
  return (
    <section className="relative pt-36 pb-24 sm:pt-44 sm:pb-32 px-5 sm:px-8">
      <div className="mx-auto max-w-5xl text-center">
        <motion.div
          initial={{ opacity: 0, y: 10 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ duration: 0.5 }}
          className="inline-flex items-center gap-2 rounded-full border border-slate-200 bg-white/70 px-4 py-1.5 text-xs font-semibold text-slate-600 backdrop-blur"
        >
          <Lock className="h-3 w-3 text-sky-600" />
          UHI11 · Active Management &amp; Curation · Uniswap v4
        </motion.div>

        <motion.h1
          initial={{ opacity: 0, y: 16 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ duration: 0.6, delay: 0.08 }}
          className="mt-7 text-4xl sm:text-6xl lg:text-7xl font-black tracking-tight text-slate-900 leading-[1.05]"
        >
          You manage the liquidity.
          <br />
          <span className="bg-gradient-to-r from-slate-900 via-sky-700 to-cyan-600 bg-clip-text text-transparent">
            You share the risk.
          </span>
          <br />
          <span className="text-slate-400">You don&apos;t get to run first.</span>
        </motion.h1>

        <motion.p
          initial={{ opacity: 0, y: 16 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ duration: 0.6, delay: 0.16 }}
          className="mx-auto mt-7 max-w-2xl text-base sm:text-lg leading-relaxed text-slate-600"
        >
          Every curated-liquidity vault today treats withdrawal as a symmetric ERC-4626 redeem.
          That symmetry is the bug: a curator who sees the strategy degrading can leave before the
          depositors who funded it.{" "}
          <span className="font-semibold text-slate-800">
            Skyline makes curator capital junior to depositor capital by construction.
          </span>
        </motion.p>

        <motion.div
          initial={{ opacity: 0, y: 16 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ duration: 0.6, delay: 0.24 }}
          className="mt-10 flex flex-col sm:flex-row items-center justify-center gap-4"
        >
          <Link
            href="/dashboard"
            className="inline-flex items-center gap-2 rounded-2xl bg-gradient-to-r from-sky-600 to-sky-500 px-7 py-3.5 text-base font-bold text-white shadow-xl shadow-sky-900/20 transition-all hover:from-sky-500 hover:to-sky-400"
          >
            See the exit gate
            <ArrowRight className="h-4 w-4" />
          </Link>
          <a
            href="#mechanism"
            className="inline-flex items-center gap-2 rounded-2xl border border-slate-300 bg-white/70 px-7 py-3.5 text-base font-semibold text-slate-700 backdrop-blur transition-colors hover:border-slate-400 hover:text-slate-900"
          >
            How it works
          </a>
        </motion.div>

        <motion.div
          initial={{ opacity: 0, y: 20 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ duration: 0.7, delay: 0.34 }}
          className="mx-auto mt-16 max-w-3xl overflow-hidden rounded-2xl border border-slate-200 bg-white/80 shadow-xl shadow-slate-900/5 backdrop-blur"
        >
          <div className="flex items-center gap-2 border-b border-slate-200 bg-slate-50/80 px-5 py-3">
            <span className="h-2.5 w-2.5 rounded-full bg-red-400" />
            <span className="h-2.5 w-2.5 rounded-full bg-amber-400" />
            <span className="h-2.5 w-2.5 rounded-full bg-emerald-400" />
            <span className="ml-3 font-mono text-xs text-slate-500">
              SkylineHook.sol — beforeRemoveLiquidity
            </span>
          </div>
          <pre className="overflow-x-auto p-5 font-mono text-[11px] leading-relaxed text-slate-700 sm:text-xs">
{`if (params.salt == CURATOR_SALT) {
    bool insolvent = pendingLiquidity[poolId] > depositorLiquidity[poolId];
    if (!insolvent) {
        require(pendingLiquidity[poolId] == 0, "CuratorExitBlocked");
        require(curatorExitApproved[poolId], "CuratorExitNotApproved");
    } else {
        int128 shortfall = pendingLiquidity[poolId] - depositorLiquidity[poolId];
        require(-params.liquidityDelta <= shortfall, "ExceedsShortfall");
    }
}`}
          </pre>
        </motion.div>
      </div>
    </section>
  )
}
