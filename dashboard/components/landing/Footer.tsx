'use client'

import Link from "next/link"
import { Logo } from "@/components/Logo"

export function Footer() {
  return (
    <footer className="border-t border-slate-200 bg-slate-50/60 px-5 sm:px-8 py-12">
      <div className="mx-auto max-w-6xl">
        <div className="flex flex-col items-start justify-between gap-8 sm:flex-row sm:items-center">
          <div className="flex items-center gap-3">
            <Logo size={34} />
            <div>
              <p className="text-base font-bold text-slate-900">Skyline</p>
              <p className="text-xs text-slate-500">
                Curator Exit Parity — the exit-alignment protocol for curated liquidity on Uniswap v4
              </p>
            </div>
          </div>

          <div className="flex flex-wrap items-center gap-6 text-sm text-slate-500">
            <Link href="/dashboard" className="transition-colors hover:text-slate-900">
              Dashboard
            </Link>
            <a href="#mechanism" className="transition-colors hover:text-slate-900">
              Mechanism
            </a>
            <a href="#demo" className="transition-colors hover:text-slate-900">
              Demo
            </a>
            <span className="rounded-full bg-slate-900 px-3 py-1 text-[11px] font-bold uppercase tracking-wider text-white">
              UHI11
            </span>
          </div>
        </div>

        <p className="mt-10 border-t border-slate-200 pt-6 text-xs leading-relaxed text-slate-400">
          Contracts are unaudited and deployed for demonstration only — do not use with real funds.
          Skyline is a submission for the 11th Uniswap Hook Incubator (Atrium Academy × Uniswap
          Foundation). Any figure shown here is either read from the chain or, in demo mode, taken
          from a published worked example.
        </p>
      </div>
    </footer>
  )
}
