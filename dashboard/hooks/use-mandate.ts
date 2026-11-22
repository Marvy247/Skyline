'use client'

/**
 * Skyline dashboard data hook.
 *
 * Reads everything the dashboard needs in a single batched multicall, and
 * exposes a single normalised state object. In DEMO MODE it returns the fixture
 * from `lib/demo-data.ts` instead, with the identical shape.
 *
 * Nothing here interprets the data beyond formatting. The contracts are the
 * source of truth.
 */

import { useCallback, useEffect, useMemo, useState } from "react"
import { useAccount, usePublicClient } from "wagmi"
import type { Address, MulticallReturnType } from "viem"

import {
  config as mandateConfig,
  isDemoMode,
  mandateHookAbi,
  mandateVaultAbi,
  poolId as configuredPoolId,
} from "@/lib/contracts"
import { demoScenarioBlocked, scenarioFromQuery } from "@/lib/demo-data"

export interface Claim {
  claimId: bigint
  depositor: Address
  liquidityAmount: bigint
  settledAmount: bigint
  registeredAt: bigint
  expiresAt: bigint
  status: number
}

export interface Mandate {
  maxFeeBps: number
  bandLower: number
  bandUpper: number
  minSkinBps: number
  maxDrawdownBps: number
  claimTtl: number
  riskState: number
}

export interface MandateState {
  demo: boolean
  chainId: number
  poolId?: `0x${string}`
  hookAddress?: Address
  vaultAddress?: Address
  curatorAddress?: Address
  depositorAddress?: Address

  pendingLiquidity: bigint
  curatorLiquidity: bigint
  depositorLiquidity: bigint
  curatorExitApproved: boolean
  curatorExitBlocked: boolean
  riskState: number
  /** Risk state after applying evaluation staleness. This is what the hook enforces. */
  effectiveRiskState: number
  /** Unix timestamp of the last `updateRiskState` evaluation. */
  riskStateUpdatedAt: bigint

  mandate: Mandate
  claims: Claim[]

  nextClaimId: bigint
  totalAssets: bigint
  totalSupply: bigint
  userShares: bigint
  navPerShare: bigint
  highWaterMark: bigint
  perfFeeBps: number
  outstandingClaims: bigint
  uncoveredShortfall: bigint
  curatorBondValue: bigint
  curatorExitProceeds: bigint
  currentSkinBps: number

  verifyCep: { cepHolds: boolean; pending: bigint; curatorLiquidity: bigint; curatorMayExit: boolean }
  verifyCuratorBond: { poolDerived: bigint; recorded: bigint }
  verifyPending: { derived: bigint; recorded: bigint }
}

const EMPTY_STATE: MandateState = {
  demo: false,
  chainId: mandateConfig.chainId,
  poolId: configuredPoolId,
  hookAddress: mandateConfig.hookAddress,
  vaultAddress: mandateConfig.vaultAddress,
  pendingLiquidity: 0n,
  curatorLiquidity: 0n,
  depositorLiquidity: 0n,
  curatorExitApproved: false,
  curatorExitBlocked: false,
  riskState: 0,
  effectiveRiskState: 0,
  riskStateUpdatedAt: 0n,
  mandate: {
    maxFeeBps: 0,
    bandLower: 0,
    bandUpper: 0,
    minSkinBps: 0,
    maxDrawdownBps: 0,
    claimTtl: 0,
    riskState: 0,
  },
  claims: [],
  nextClaimId: 0n,
  totalAssets: 0n,
  totalSupply: 0n,
  userShares: 0n,
  navPerShare: 0n,
  highWaterMark: 0n,
  perfFeeBps: 0,
  outstandingClaims: 0n,
  uncoveredShortfall: 0n,
  curatorBondValue: 0n,
  curatorExitProceeds: 0n,
  currentSkinBps: 0,
  verifyCep: { cepHolds: false, pending: 0n, curatorLiquidity: 0n, curatorMayExit: false },
  verifyCuratorBond: { poolDerived: 0n, recorded: 0n },
  verifyPending: { derived: 0n, recorded: 0n },
}

function ok<T>(entry: MulticallReturnType[number] | undefined, fallback: T): T {
  if (!entry) return fallback
  if (entry.status === "success") return entry.result as T
  return fallback
}

function num(v: unknown): number {
  if (typeof v === "number") return v
  if (typeof v === "bigint") return Number(v)
  return 0
}

function big(v: unknown): bigint {
  if (typeof v === "bigint") return v
  if (typeof v === "number") return BigInt(Math.trunc(v))
  if (typeof v === "string" && v.length > 0) {
    try {
      return BigInt(v)
    } catch {
      return 0n
    }
  }
  return 0n
}

export function useMandate(scenarioParam: string | null = null) {
  const client = usePublicClient()
  const { address } = useAccount()
  const demo = isDemoMode()

  const [state, setState] = useState<MandateState>(EMPTY_STATE)
  const [isLoading, setIsLoading] = useState(!demo)
  const [error, setError] = useState<Error | null>(null)
  const [tick, setTick] = useState(0)

  const poolId = configuredPoolId
  const hookAddress = mandateConfig.hookAddress
  const vaultAddress = mandateConfig.vaultAddress

  const refetch = useCallback(() => setTick((t) => t + 1), [])

  useEffect(() => {
    // DEMO MODE — render the fixture. Identical component tree.
    if (demo) {
      setState(scenarioFromQuery(scenarioParam))
      setIsLoading(false)
      setError(null)
      return
    }

    if (!client || !poolId || !hookAddress || !vaultAddress) {
      setIsLoading(false)
      setError(
        new Error(
          "Skyline contracts are not configured. Set NEXT_PUBLIC_HOOK_ADDRESS / NEXT_PUBLIC_VAULT_ADDRESS, or enable DEMO MODE.",
        ),
      )
      return
    }

    let cancelled = false
    setIsLoading(true)

    const run = async () => {
      try {
        // NOTE: the contract objects are written inline (not via a helper) so
        // TypeScript keeps each `functionName` as a literal union member and
        // can type-check the multicall result. A helper that widens
        // `functionName` to `string` breaks the inference.
        const H = mandateHookAbi
        const V = mandateVaultAbi

        const [poolConfig, mandate, nextClaimId, pending, curatorLiq, depositorLiq, exitApproved, exitBlocked, risk, effectiveRisk, riskUpdatedAt, verifyCep, verifyBond, verifyPendingRes, totalAssets, totalSupply, userShares, navPerShare, hwm, perfFee, outClaims, shortfall, bondValue, exitProceeds, skinBps] =
          await client.multicall({
            allowFailure: true,
            contracts: [
              { address: hookAddress, abi: H, functionName: "poolConfigs", args: [poolId] },
              { address: hookAddress, abi: H, functionName: "mandate", args: [poolId] },
              { address: hookAddress, abi: H, functionName: "nextClaimId", args: [poolId] },
              { address: hookAddress, abi: H, functionName: "pendingLiquidity", args: [poolId] },
              { address: hookAddress, abi: H, functionName: "curatorLiquidity", args: [poolId] },
              { address: hookAddress, abi: H, functionName: "depositorLiquidity", args: [poolId] },
              { address: hookAddress, abi: H, functionName: "curatorExitApproved", args: [poolId] },
              { address: hookAddress, abi: H, functionName: "isCuratorExitBlocked", args: [poolId] },
              { address: hookAddress, abi: H, functionName: "riskState", args: [poolId] },
              { address: hookAddress, abi: H, functionName: "effectiveRiskState", args: [poolId] },
              { address: hookAddress, abi: H, functionName: "riskStateUpdatedAt", args: [poolId] },
              { address: hookAddress, abi: H, functionName: "verifyCep", args: [poolId] },
              { address: hookAddress, abi: H, functionName: "verifyCuratorBond", args: [poolId] },
              { address: hookAddress, abi: H, functionName: "verifyPending", args: [poolId] },
              { address: vaultAddress, abi: V, functionName: "totalAssets" },
              { address: vaultAddress, abi: V, functionName: "totalSupply" },
              {
                address: vaultAddress,
                abi: V,
                functionName: "balanceOf",
                args: [address ?? "0x0000000000000000000000000000000000000000"],
              },
              { address: vaultAddress, abi: V, functionName: "convertToAssets", args: [10n ** 18n] },
              { address: vaultAddress, abi: V, functionName: "highWaterMark" },
              { address: vaultAddress, abi: V, functionName: "perfFeeBps" },
              { address: vaultAddress, abi: V, functionName: "outstandingClaims" },
              { address: vaultAddress, abi: V, functionName: "uncoveredShortfall" },
              { address: vaultAddress, abi: V, functionName: "curatorBondValue" },
              { address: vaultAddress, abi: V, functionName: "curatorExitProceeds" },
              { address: vaultAddress, abi: V, functionName: "currentSkinBps" },
            ],
          })

        if (cancelled) return

        const cfg = ok<{ vault: Address; curator: Address; oracle: Address; registered: boolean }>(
          poolConfig,
          {
            vault: "0x0000000000000000000000000000000000000000",
            curator: "0x0000000000000000000000000000000000000000",
            oracle: "0x0000000000000000000000000000000000000000",
            registered: false,
          },
        )

        const m = ok<{
          maxFeeBps: number
          bandLower: number
          bandUpper: number
          minSkinBps: number
          maxDrawdownBps: number
          claimTtl: number
          riskState: number
        }>(mandate, {
          maxFeeBps: 0,
          bandLower: 0,
          bandUpper: 0,
          minSkinBps: 0,
          maxDrawdownBps: 0,
          claimTtl: 0,
          riskState: 0,
        })

        const nextId = big(ok(nextClaimId, 0n))

        // Fetch the claim list individually — the count is dynamic.
        const claimContracts = Array.from({ length: Number(nextId) }, (_, i) => ({
          address: hookAddress,
          abi: H,
          functionName: "claim" as const,
          args: [poolId, BigInt(i)],
        }))
        const claimResults = claimContracts.length
          ? await client.multicall({ allowFailure: true, contracts: claimContracts })
          : []

        if (cancelled) return

        const claims: Claim[] = claimResults
          .map((entry, i) => {
            const c = ok<{
              liquidityAmount: bigint
              settledAmount: bigint
              totalLiquidityAtRegistration: bigint
              registeredAt: bigint
              expiresAt: bigint
              status: number
              depositor: Address
            }>(entry, {
              liquidityAmount: 0n,
              settledAmount: 0n,
              totalLiquidityAtRegistration: 0n,
              registeredAt: 0n,
              expiresAt: 0n,
              status: 0,
              depositor: "0x0000000000000000000000000000000000000000",
            })
            return {
              claimId: BigInt(i),
              depositor: c.depositor,
              liquidityAmount: c.liquidityAmount,
              settledAmount: c.settledAmount,
              registeredAt: c.registeredAt,
              expiresAt: c.expiresAt,
              status: num(c.status),
            }
          })
          .filter((c) => c.status !== 0)

        const cep = ok<readonly [boolean, bigint, bigint, boolean]>(verifyCep, [
          false,
          0n,
          0n,
          false,
        ])
        const bond = ok<readonly [bigint, bigint]>(verifyBond, [0n, 0n])
        const pend = ok<readonly [bigint, bigint]>(verifyPendingRes, [0n, 0n])

        setState({
          demo: false,
          chainId: mandateConfig.chainId,
          poolId,
          hookAddress,
          vaultAddress,
          curatorAddress: cfg.curator,
          depositorAddress: address,
          pendingLiquidity: big(ok(pending, 0n)),
          curatorLiquidity: big(ok(curatorLiq, 0n)),
          depositorLiquidity: big(ok(depositorLiq, 0n)),
          curatorExitApproved: ok(exitApproved, false),
          curatorExitBlocked: ok(exitBlocked, false),
          riskState: num(ok(risk, 0)),
          effectiveRiskState: num(ok(effectiveRisk, 0)),
          riskStateUpdatedAt: big(ok(riskUpdatedAt, 0n)),
          mandate: {
            maxFeeBps: num(m.maxFeeBps),
            bandLower: num(m.bandLower),
            bandUpper: num(m.bandUpper),
            minSkinBps: num(m.minSkinBps),
            maxDrawdownBps: num(m.maxDrawdownBps),
            claimTtl: num(m.claimTtl),
            riskState: num(m.riskState),
          },
          claims,
          nextClaimId: nextId,
          totalAssets: big(ok(totalAssets, 0n)),
          totalSupply: big(ok(totalSupply, 0n)),
          userShares: big(ok(userShares, 0n)),
          navPerShare: big(ok(navPerShare, 0n)),
          highWaterMark: big(ok(hwm, 0n)),
          perfFeeBps: num(ok(perfFee, 0)),
          outstandingClaims: big(ok(outClaims, 0n)),
          uncoveredShortfall: big(ok(shortfall, 0n)),
          curatorBondValue: big(ok(bondValue, 0n)),
          curatorExitProceeds: big(ok(exitProceeds, 0n)),
          currentSkinBps: num(ok(skinBps, 0)),
          verifyCep: {
            cepHolds: cep[0],
            pending: cep[1],
            curatorLiquidity: cep[2],
            curatorMayExit: cep[3],
          },
          verifyCuratorBond: { poolDerived: bond[0], recorded: bond[1] },
          verifyPending: { derived: pend[0], recorded: pend[1] },
        })
        setError(null)
      } catch (e) {
        if (!cancelled) setError(e instanceof Error ? e : new Error(String(e)))
      } finally {
        if (!cancelled) setIsLoading(false)
      }
    }

    void run()
    const timer = setInterval(() => void run(), 8_000)
    return () => {
      cancelled = true
      clearInterval(timer)
    }
  }, [client, poolId, hookAddress, vaultAddress, address, demo, scenarioParam, tick])

  /** Total vault-side liquidity and the skin ratio derived from it. */
  const derived = useMemo(() => {
    const total = state.curatorLiquidity + state.depositorLiquidity
    const skinBps = total > 0n ? Number((state.curatorLiquidity * 10_000n) / total) : 0
    const shortfall =
      state.pendingLiquidity > state.depositorLiquidity
        ? state.pendingLiquidity - state.depositorLiquidity
        : 0n
    return { total, skinBps, shortfall }
  }, [state.curatorLiquidity, state.depositorLiquidity, state.pendingLiquidity])

  return { state, derived, isLoading, error, refetch, demo }
}

export { demoScenarioBlocked }
