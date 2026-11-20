'use client'

/**
 * Wallet connect button.
 *
 * Minimal on purpose: the dashboard is a read-mostly view. Writing requires a
 * connected wallet; reading never does.
 */

import { useState } from "react"
import { useAccount, useConnect, useDisconnect } from "wagmi"
import { injected } from "wagmi/connectors"
import { Wallet, LogOut, Loader2, ChevronDown } from "lucide-react"

import { cn } from "@/lib/utils"
import { shortAddress } from "@/lib/format"

export function WalletButton({ compact = false }: { compact?: boolean }) {
  const { address, isConnected } = useAccount()
  const { connect, connectors, isPending } = useConnect()
  const { disconnect } = useDisconnect()
  const [open, setOpen] = useState(false)

  if (isConnected) {
    return (
      <div className="relative">
        <button
          onClick={() => setOpen((v) => !v)}
          className={cn(
            "inline-flex items-center gap-2 rounded-xl border border-slate-200 bg-white px-3 py-2 text-sm font-semibold text-slate-700 shadow-sm transition-colors hover:border-slate-300",
            compact && "px-2.5",
          )}
        >
          <span className="h-2 w-2 rounded-full bg-emerald-500" />
          <span className="font-mono">{shortAddress(address)}</span>
          <ChevronDown className="h-3.5 w-3.5 text-slate-400" />
        </button>

        {open ? (
          <>
            <div className="fixed inset-0 z-30" onClick={() => setOpen(false)} />
            <div className="absolute right-0 z-40 mt-2 w-56 overflow-hidden rounded-xl border border-slate-200 bg-white shadow-xl">
              <div className="border-b border-slate-100 px-4 py-3">
                <p className="text-[10px] font-semibold uppercase tracking-wider text-slate-400">
                  Connected
                </p>
                <p className="mt-0.5 truncate font-mono text-xs text-slate-700">{address}</p>
              </div>
              <button
                onClick={() => {
                  disconnect()
                  setOpen(false)
                }}
                className="flex w-full items-center gap-2 px-4 py-3 text-left text-sm font-semibold text-slate-700 transition-colors hover:bg-slate-50"
              >
                <LogOut className="h-3.5 w-3.5" />
                Disconnect
              </button>
            </div>
          </>
        ) : null}
      </div>
    )
  }

  const injectedConnector = connectors.find((c) => c.id === "injected") ?? connectors[0]

  return (
    <button
      onClick={() => {
        if (injectedConnector) connect({ connector: injectedConnector })
      }}
      disabled={isPending}
      className="inline-flex items-center gap-2 rounded-xl bg-slate-900 px-4 py-2 text-sm font-semibold text-white shadow-sm transition-colors hover:bg-slate-800 disabled:opacity-60"
    >
      {isPending ? (
        <Loader2 className="h-4 w-4 animate-spin" />
      ) : (
        <Wallet className="h-4 w-4" />
      )}
      Connect wallet
    </button>
  )
}
