'use client'

/**
 * The exit gate panel — the demo centrepiece.
 *
 * One button, one outcome: the curator tries to leave while depositor
 * obligations are outstanding, and the hook rejects it. The revert is decoded
 * and shown in plain English, because a hex blob teaches a judge nothing.
 */

import { useState } from "react"
import { motion, AnimatePresence } from "framer-motion"
import { DoorOpen, Lock, Loader2, CheckCircle2, XCircle, Info } from "lucide-react"

import { cn } from "@/lib/utils"
import { formatLiquidity } from "@/lib/format"
import { explorerUrl } from "@/lib/contracts"
import { Panel, PanelHeader, KeyValue, Pill } from "@/components/dashboard/primitives"
import type { MandateState } from "@/hooks/use-mandate"
import { useMandateActions } from "@/hooks/use-mandate-actions"

export function ExitGatePanel({ state }: { state: MandateState }) {
  const actions = useMandateActions({
    // In demo mode, reproduce the exact revert the hook produces so the
    // presenter can rehearse the interaction end to end.
    demoCuratorExitBlocked: state.curatorExitBlocked,
  })
  const [showWhy, setShowWhy] = useState(false)

  const blocked = state.curatorExitBlocked
  const pending = state.pendingLiquidity

  return (
    <Panel className="overflow-hidden">
      <PanelHeader
        icon={blocked ? <Lock className="h-4 w-4" /> : <DoorOpen className="h-4 w-4" />}
        title="Curator exit gate"
        subtitle="The hook's own ledger decides — not the vault's word."
        accent={blocked ? "red" : "emerald"}
        right={
          blocked ? (
            <Pill tone="red">
              <Lock className="h-3 w-3" /> Blocked
            </Pill>
          ) : (
            <Pill tone="emerald">
              <CheckCircle2 className="h-3 w-3" /> Open
            </Pill>
          )
        }
      />

      <div className="space-y-5 px-6 py-5">
        <div className="rounded-xl border border-slate-200 bg-slate-50/60 p-4">
          <KeyValue
            label="Outstanding depositor obligation"
            value={`${formatLiquidity(pending)} liquidity units`}
            mono
          />
          <KeyValue
            label="Curator-bonded liquidity at risk"
            value={`${formatLiquidity(state.curatorLiquidity)} liquidity units`}
            mono
          />
          <KeyValue
            label="Curator exit approval (vault)"
            value={state.curatorExitApproved ? "granted" : "not granted"}
          />
          <KeyValue
            label="Hook ledger requirement"
            value="pendingLiquidity must be 0"
            mono
          />
        </div>

        <div className="rounded-xl border border-slate-200 bg-white p-4">
          <p className="text-xs font-semibold uppercase tracking-wider text-slate-500">
            Rule enforced in <code className="font-mono">beforeRemoveLiquidity</code>
          </p>
          <pre className="mt-2 overflow-x-auto rounded-lg bg-slate-950 p-4 font-mono text-[11px] leading-relaxed text-slate-200">
{`if (params.salt == CURATOR_SALT) {
    // last resort: only when depositor liquidity provably cannot cover claims
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
        </div>

        <div className="flex flex-wrap items-center gap-3">
          <button
            onClick={() => void actions.requestCuratorExit()}
            disabled={actions.state.status === "pending"}
            className={cn(
              "inline-flex items-center gap-2 rounded-xl px-5 py-3 text-sm font-bold shadow-lg transition-all",
              "disabled:cursor-not-allowed disabled:opacity-60",
              blocked
                ? "bg-gradient-to-r from-red-600 to-rose-500 text-white shadow-red-900/20 hover:from-red-500 hover:to-rose-400"
                : "bg-gradient-to-r from-sky-600 to-sky-500 text-white shadow-sky-900/20 hover:from-sky-500 hover:to-sky-400",
            )}
          >
            {actions.state.status === "pending" ? (
              <Loader2 className="h-4 w-4 animate-spin" />
            ) : blocked ? (
              <Lock className="h-4 w-4" />
            ) : (
              <DoorOpen className="h-4 w-4" />
            )}
            Attempt curator exit
          </button>

          <button
            onClick={() => setShowWhy((v) => !v)}
            className="inline-flex items-center gap-2 rounded-xl px-4 py-3 text-sm font-semibold text-slate-600 transition-colors hover:bg-slate-100 hover:text-slate-900"
          >
            <Info className="h-4 w-4" />
            Why is it blocked?
          </button>
        </div>

        <AnimatePresence>
          {showWhy ? (
            <motion.div
              initial={{ opacity: 0, height: 0 }}
              animate={{ opacity: 1, height: "auto" }}
              exit={{ opacity: 0, height: 0 }}
              className="overflow-hidden"
            >
              <div className="rounded-xl border border-amber-200 bg-amber-50/70 p-4 text-sm text-amber-900">
                <p className="font-semibold">The curator holds an information advantage.</p>
                <p className="mt-1.5 leading-relaxed">
                  Because a claim has been registered, the curator's exit must wait. This is not a
                  timelock and not a queue the curator chooses to honour — it is a condition
                  evaluated inside the Uniswap v4 hook, on every liquidity removal, at the
                  PoolManager. The curator&apos;s capital stays exposed to the strategy alongside
                  the depositors&apos; until their outstanding obligations are served.
                </p>
              </div>
            </motion.div>
          ) : null}
        </AnimatePresence>

        <AnimatePresence>
          {actions.state.status === "error" ? (
            <motion.div
              initial={{ opacity: 0, y: 8 }}
              animate={{ opacity: 1, y: 0 }}
              exit={{ opacity: 0, y: -8 }}
              className="rounded-xl border border-red-200 bg-red-50 p-4"
            >
              <div className="flex items-start gap-3">
                <XCircle className="mt-0.5 h-5 w-5 shrink-0 text-red-600" />
                <div className="min-w-0">
                  <p className="text-sm font-bold text-red-800">
                    {actions.state.errorName ?? "Reverted"}
                  </p>
                  <p className="mt-1 text-sm leading-relaxed text-red-700">{actions.state.message}</p>
                </div>
              </div>
            </motion.div>
          ) : null}

          {actions.state.status === "success" ? (
            <motion.div
              initial={{ opacity: 0, y: 8 }}
              animate={{ opacity: 1, y: 0 }}
              exit={{ opacity: 0, y: -8 }}
              className="rounded-xl border border-emerald-200 bg-emerald-50 p-4"
            >
              <div className="flex items-start gap-3">
                <CheckCircle2 className="mt-0.5 h-5 w-5 shrink-0 text-emerald-600" />
                <div>
                  <p className="text-sm font-bold text-emerald-800">{actions.state.label} succeeded</p>
                  {actions.state.hash ? (
                    <a
                      href={explorerUrl("tx", actions.state.hash)}
                      target="_blank"
                      rel="noreferrer"
                      className="mt-1 inline-block font-mono text-xs text-emerald-700 underline"
                    >
                      {actions.state.hash}
                    </a>
                  ) : null}
                </div>
              </div>
            </motion.div>
          ) : null}
        </AnimatePresence>
      </div>
    </Panel>
  )
}
