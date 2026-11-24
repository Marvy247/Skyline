'use client'

import { Suspense } from "react"
import { useSearchParams } from "next/navigation"
import {
  LayoutDashboard,
  DoorOpen,
  ClipboardList,
  ShieldCheck,
  Gavel,
  Fingerprint,
  AlertTriangle,
  RefreshCw,
} from "lucide-react"

import { DashboardLayout } from "@/components/dashboard-layout"
import { Logo } from "@/components/Logo"
import { WalletButton } from "@/components/wallet-button"
import { CepBadge } from "@/components/dashboard/cep-badge"
import { ExitGatePanel } from "@/components/dashboard/exit-gate-panel"
import { ExitLadder } from "@/components/dashboard/exit-ladder"
import { ClaimsPanel, VaultStatsPanel } from "@/components/dashboard/claims-panel"
import { CuratorBondPanel } from "@/components/dashboard/curator-bond-panel"
import { MandatePanel } from "@/components/dashboard/mandate-panel"
import { VerifierPanel } from "@/components/dashboard/verifier-panel"
import { Panel, PanelHeader } from "@/components/dashboard/primitives"
import { useMandate } from "@/hooks/use-mandate"
import { chainName } from "@/lib/web3"
import { explorerUrl } from "@/lib/contracts"
import { formatLiquidity, shortAddress } from "@/lib/format"

const NAV = [
  { id: "overview", name: "Overview", icon: LayoutDashboard },
  { id: "exit", name: "Exit gate", icon: DoorOpen },
  { id: "claims", name: "Claims", icon: ClipboardList },
  { id: "bond", name: "Curator bond", icon: ShieldCheck },
  { id: "mandate", name: "Mandate", icon: Gavel },
  { id: "verify", name: "Verification", icon: Fingerprint },
]

function DashboardInner() {
  const searchParams = useSearchParams()
  const scenario = searchParams.get("scenario")
  const tab = searchParams.get("tab") ?? "overview"

  const { state, derived, isLoading, error, refetch, demo } = useMandate(scenario)

  const show = (id: string) => tab === id

  return (
    <DashboardLayout
      sidebarItems={NAV}
      logo={<Logo size={36} />}
      brandName="Skyline"
      headerAction={
        <div className="flex items-center gap-2">
          <button
            onClick={refetch}
            className="inline-flex h-9 items-center gap-2 rounded-xl border border-slate-200 bg-white px-3 text-xs font-semibold text-slate-600 shadow-sm transition-colors hover:border-slate-300 hover:text-slate-900"
          >
            <RefreshCw className={isLoading ? "h-3.5 w-3.5 animate-spin" : "h-3.5 w-3.5"} />
            Refresh
          </button>
          <WalletButton />
        </div>
      }
    >
      <div className="space-y-6">
        {/* Context strip */}
        <div className="flex flex-wrap items-center gap-x-5 gap-y-2 rounded-2xl border border-slate-200 bg-white px-5 py-3 text-xs text-slate-500">
          <span className="font-semibold text-slate-800">Skyline</span>
          <span>
            chain <span className="font-mono">{chainName()}</span>
          </span>
          {state.hookAddress ? (
            <span>
              hook{" "}
              <a
                href={explorerUrl("address", state.hookAddress)}
                target="_blank"
                rel="noreferrer"
                className="font-mono text-sky-600 underline"
              >
                {shortAddress(state.hookAddress)}
              </a>
            </span>
          ) : null}
          {state.vaultAddress ? (
            <span>
              vault{" "}
              <a
                href={explorerUrl("address", state.vaultAddress)}
                target="_blank"
                rel="noreferrer"
                className="font-mono text-sky-600 underline"
              >
                {shortAddress(state.vaultAddress)}
              </a>
            </span>
          ) : null}
          {state.poolId ? (
            <span>
              pool{" "}
              <span className="font-mono">{shortAddress(state.poolId, 6)}</span>
            </span>
          ) : null}
          {demo ? (
            <span className="rounded-full bg-slate-900 px-2.5 py-0.5 text-[10px] font-bold uppercase tracking-wider text-white">
              demo fixture
            </span>
          ) : null}
        </div>

        {error ? (
          <div className="flex items-start gap-3 rounded-2xl border border-amber-200 bg-amber-50 p-5">
            <AlertTriangle className="mt-0.5 h-5 w-5 shrink-0 text-amber-600" />
            <div>
              <p className="text-sm font-bold text-amber-900">Could not read the chain</p>
              <p className="mt-1 text-sm text-amber-800">{error.message}</p>
              <p className="mt-2 text-xs text-amber-700">
                The dashboard also runs in demo mode from a published worked example — set{" "}
                <code className="font-mono">NEXT_PUBLIC_DEMO_MODE=true</code>.
              </p>
            </div>
          </div>
        ) : null}

        {show("overview") ? (
          <>
            <CepBadge state={state} />
            <div className="grid gap-6 xl:grid-cols-[minmax(0,1.35fr)_minmax(0,1fr)]">
              <Panel>
                <PanelHeader
                  icon={<ClipboardList className="h-4 w-4" />}
                  title="Where a withdrawal is served from"
                  subtitle="Depositor liquidity first, then the curator's bond, then pro rata."
                />
                <div className="px-6 py-5">
                  <ExitLadder
                    pending={state.pendingLiquidity}
                    depositorLiquidity={state.depositorLiquidity}
                    curatorLiquidity={state.curatorLiquidity}
                  />
                </div>
              </Panel>
              <VaultStatsPanel state={state} />
            </div>
            <ClaimsPanel state={state} />
          </>
        ) : null}

        {show("exit") ? (
          <>
            <CepBadge state={state} />
            <div className="grid gap-6 xl:grid-cols-[minmax(0,1.4fr)_minmax(0,1fr)]">
              <ExitGatePanel state={state} />
              <Panel>
                <PanelHeader
                  icon={<ClipboardList className="h-4 w-4" />}
                  title="Exit ladder"
                  subtitle="Who serves the claim, and who leaves last."
                />
                <div className="px-6 py-5">
                  <ExitLadder
                    pending={state.pendingLiquidity}
                    depositorLiquidity={state.depositorLiquidity}
                    curatorLiquidity={state.curatorLiquidity}
                  />
                </div>
              </Panel>
            </div>
          </>
        ) : null}

        {show("claims") ? (
          <>
            <VaultStatsPanel state={state} />
            <ClaimsPanel state={state} />
          </>
        ) : null}

        {show("bond") ? (
          <CuratorBondPanel state={state} derived={derived} />
        ) : null}

        {show("mandate") ? <MandatePanel state={state} /> : null}

        {show("verify") ? (
          <>
            <VerifierPanel state={state} />
            <Panel>
              <PanelHeader
                icon={<Fingerprint className="h-4 w-4" />}
                title="Raw hook state"
                subtitle="Exactly what the dashboard read."
              />
              <div className="grid grid-cols-2 gap-3 px-6 py-5 lg:grid-cols-4">
                <Raw label="pendingLiquidity" value={`${formatLiquidity(state.pendingLiquidity)} liq`} />
                <Raw label="curatorLiquidity" value={`${formatLiquidity(state.curatorLiquidity)} liq`} />
                <Raw label="depositorLiquidity" value={`${formatLiquidity(state.depositorLiquidity)} liq`} />
                <Raw label="curatorExitBlocked" value={state.curatorExitBlocked ? "true" : "false"} />
              </div>
            </Panel>
          </>
        ) : null}
      </div>
    </DashboardLayout>
  )
}

function Raw({ label, value }: { label: string; value: string }) {
  return (
    <div className="rounded-xl border border-slate-200 bg-slate-50/60 p-4">
      <p className="font-mono text-[10px] font-semibold text-slate-500">{label}</p>
      <p className="mt-1 font-mono text-sm font-bold text-slate-800">{value}</p>
    </div>
  )
}

export default function DashboardPage() {
  return (
    <Suspense
      fallback={
        <div className="flex min-h-screen items-center justify-center bg-dashboard">
          <div className="animate-pulse text-slate-500">Loading Skyline…</div>
        </div>
      }
    >
      <DashboardInner />
    </Suspense>
  )
}
