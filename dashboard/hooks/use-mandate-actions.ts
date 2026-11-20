'use client'

/**
 * Skyline dashboard write actions.
 *
 * Each action returns a discriminated result so the UI can show a *decoded*
 * revert reason rather than a wall of hex. The decoded `CuratorExitBlocked` is
 * the centrepiece of the demo — it is the proof that the hook, not the vault,
 * blocked the exit.
 */

import { useCallback, useState } from "react"
import { useAccount, usePublicClient, useWalletClient } from "wagmi"
import { decodeErrorResult, encodeFunctionData, parseUnits } from "viem"

import {
  config as mandateConfig,
  isDemoMode,
  mandateErrorsAbi,
  mandateVaultAbi,
  poolId as configuredPoolId,
} from "@/lib/contracts"

export type ActionState =
  | { status: "idle" }
  | { status: "pending"; label: string }
  | { status: "success"; label: string; hash?: `0x${string}` }
  | { status: "error"; label: string; message: string; errorName?: string }

export interface MandateActions {
  requestWithdraw: (shares: bigint) => Promise<void>
  settleClaims: (maxClaims?: bigint) => Promise<void>
  requestCuratorExit: () => Promise<void>
  curatorDeposit: (assets: bigint) => Promise<void>
  accruePerformanceFee: () => Promise<void>
  state: ActionState
  reset: () => void
}

/** A plain-English sentence for each custom error. */
export function describe(errorName: string, args?: readonly unknown[]): string {
  switch (errorName) {
    case "CuratorExitBlocked":
      return `The hook blocked the curator's exit: ${String(args?.[0] ?? "outstanding")} liquidity units of depositor obligation are still unsettled.`
    case "CuratorExitNotApproved":
      return "The curator's exit has not been approved. Vault approval AND an empty obligation ledger are both required."
    case "ExceedsShortfall":
      return "The removal exceeded the shortfall the curator's bond is permitted to absorb."
    case "FeeCapExceeded":
      return `Dynamic fee ${String(args?.[0] ?? "?")} bps exceeded the mandate cap of ${String(args?.[1] ?? "?")} bps.`
    case "BelowBand":
      return "The curator position moved below the committed tick band."
    case "AboveBand":
      return "The curator position moved above the committed tick band."
    case "SkinTooLow":
      return `Curator skin ${String(args?.[0] ?? "?")} bps is below the mandate minimum of ${String(args?.[1] ?? "?")} bps.`
    case "RiskStateRestricted":
      return "Curator operations are frozen: the strategy is in the Restricted risk state."
    case "RiskStateBreached":
      return "Curator operations are frozen: the drawdown limit has been breached."
    case "SettlementNotCorroborated":
      return "The hook could not corroborate a real liquidity removal for this settlement."
    case "OverClaim":
      return "The settlement amount exceeds the outstanding claim remainder."
    case "ClaimLimitExceeded":
      return "This depositor already has too many open claims."
    case "MinClaimSize":
      return "The claim is below the minimum size."
    case "CoolingOff":
      return "The curator is in the cooling-off window between exit requests."
    case "NothingToSettle":
      return "There are no claims due for settlement."
    case "InsufficientShares":
      return "Not enough shares for this request."
    case "ZeroAmount":
      return "Amount must be greater than zero."
    default:
      return errorName
  }
}

/**
 * Turn a viem error into a human sentence, preferring our custom errors.
 *
 * viem surfaces the raw revert data on `cause.data` (for
 * `ContractFunctionExecutionError`). We decode it against the Skyline error ABI.
 */
export function decodeFailure(err: unknown): { errorName?: string; message: string } {
  const fallbackMessage = err instanceof Error ? err.message : String(err)

  const data = findRevertData(err)
  if (data) {
    try {
      const decoded = decodeErrorResult({
        abi: mandateErrorsAbi,
        data,
      })
      if (decoded?.errorName) {
        return {
          errorName: decoded.errorName,
          message: describe(decoded.errorName, decoded.args as readonly unknown[]),
        }
      }
    } catch {
      // Not one of our errors — fall through to the generic handling.
    }
  }

  // Last resort: match the error name inside the revert message.
  const haystack = collectStrings(err).join(" ")
  for (const name of [
    "CuratorExitBlocked",
    "CuratorExitNotApproved",
    "ExceedsShortfall",
    "FeeCapExceeded",
    "BelowBand",
    "AboveBand",
    "SkinTooLow",
    "RiskStateRestricted",
    "RiskStateBreached",
    "SettlementNotCorroborated",
    "OverClaim",
    "ClaimLimitExceeded",
    "MinClaimSize",
    "CoolingOff",
    "NothingToSettle",
    "InsufficientShares",
    "ZeroAmount",
  ]) {
    if (haystack.includes(name)) {
      return { errorName: name, message: describe(name) }
    }
  }

  return { errorName: undefined, message: fallbackMessage }
}

/** Walk the error chain looking for 4-byte revert data. */
function findRevertData(err: unknown, depth = 0): `0x${string}` | undefined {
  if (!err || typeof err !== "object" || depth > 6) return undefined

  const candidate = err as {
    data?: unknown
    cause?: unknown
    error?: unknown
    details?: unknown
  }

  for (const key of ["data", "error", "details"] as const) {
    const value = candidate[key]
    if (typeof value === "string" && /^0x[0-9a-fA-F]{8,}$/.test(value)) {
      return value as `0x${string}`
    }
  }

  return findRevertData(candidate.cause, depth + 1)
}

/** Collect every string in the error chain, for name matching. */
function collectStrings(err: unknown, depth = 0): string[] {
  if (!err || typeof err !== "object" || depth > 6) return []
  const out: string[] = []
  const candidate = err as Record<string, unknown>

  for (const value of Object.values(candidate)) {
    if (typeof value === "string") out.push(value)
  }
  if (typeof candidate.message === "string") out.push(candidate.message)
  if (typeof candidate.shortMessage === "string") out.push(candidate.shortMessage)
  if (candidate.cause) out.push(...collectStrings(candidate.cause, depth + 1))

  return out
}

export interface MandateActionsOptions {
  /** Called after a successful write, so the caller can refetch. */
  onDone?: () => void
  /**
   * DEMO MODE only: emulate the blocked curator exit so the presenter can
   * rehearse the exact revert the hook produces.
   */
  demoCuratorExitBlocked?: boolean
}

export function useMandateActions(options?: MandateActionsOptions): MandateActions {
  const { address } = useAccount()
  const publicClient = usePublicClient()
  const { data: walletClient } = useWalletClient()
  const [state, setState] = useState<ActionState>({ status: "idle" })

  const vaultAddress = mandateConfig.vaultAddress
  const demo = isDemoMode()
  const onDone = options?.onDone
  const demoCuratorExitBlocked = options?.demoCuratorExitBlocked ?? false

  const run = useCallback(
    async (
      label: string,
      build: () => Promise<{ to: `0x${string}`; data: `0x${string}` }>,
      opts?: { demoError?: { errorName: string; args?: readonly unknown[] } },
    ) => {
      setState({ status: "pending", label })
      try {
        if (demo) {
          await new Promise((r) => setTimeout(r, 700))
          if (opts?.demoError) {
            setState({
              status: "error",
              label,
              errorName: opts.demoError.errorName,
              message: describe(opts.demoError.errorName, opts.demoError.args),
            })
            return
          }
          setState({ status: "success", label })
          onDone?.()
          return
        }

        if (!walletClient || !address) throw new Error("Connect a wallet first.")

        const { to, data } = await build()
        const hash = await walletClient.sendTransaction({ account: address, to, data })

        if (publicClient) {
          const receipt = await publicClient.waitForTransactionReceipt({ hash })
          if (receipt.status !== "success") {
            throw new Error("Transaction reverted on chain.")
          }
        }

        setState({ status: "success", label, hash })
        onDone?.()
      } catch (e) {
        const { errorName, message } = decodeFailure(e)
        setState({ status: "error", label, errorName, message })
      }
    },
    [address, walletClient, publicClient, demo, onDone],
  )

  const requestWithdraw = useCallback(
    async (shares: bigint) => {
      await run(
        "Request withdrawal",
        async () => ({
          to: vaultAddress as `0x${string}`,
          data: encodeFunctionData({
            abi: mandateVaultAbi,
            functionName: "requestWithdraw",
            args: [shares],
          }),
        }),
      )
    },
    [run, vaultAddress],
  )

  const settleClaims = useCallback(
    async (maxClaims: bigint = 10n) => {
      await run(
        "Settle claims",
        async () => ({
          to: vaultAddress as `0x${string}`,
          data: encodeFunctionData({
            abi: mandateVaultAbi,
            functionName: "settleClaims",
            args: [maxClaims],
          }),
        }),
      )
    },
    [run, vaultAddress],
  )

  const requestCuratorExit = useCallback(async () => {
    await run(
      "Request curator exit",
      async () => ({
        to: vaultAddress as `0x${string}`,
        data: encodeFunctionData({
          abi: mandateVaultAbi,
          functionName: "requestCuratorExit",
          args: [],
        }),
      }),
      demoCuratorExitBlocked
        ? { demoError: { errorName: "CuratorExitBlocked", args: ["55,556"] } }
        : undefined,
    )
  }, [run, vaultAddress, demoCuratorExitBlocked])

  const curatorDeposit = useCallback(
    async (assets: bigint) => {
      await run(
        "Top up curator bond",
        async () => ({
          to: vaultAddress as `0x${string}`,
          data: encodeFunctionData({
            abi: mandateVaultAbi,
            functionName: "curatorDeposit",
            args: [assets],
          }),
        }),
      )
    },
    [run, vaultAddress],
  )

  const accruePerformanceFee = useCallback(async () => {
    await run(
      "Accrue performance fee",
      async () => ({
        to: vaultAddress as `0x${string}`,
        data: encodeFunctionData({
          abi: mandateVaultAbi,
          functionName: "accruePerformanceFee",
          args: [],
        }),
      }),
    )
  }, [run, vaultAddress])

  const reset = useCallback(() => setState({ status: "idle" }), [])

  return {
    requestWithdraw,
    settleClaims,
    requestCuratorExit,
    curatorDeposit,
    accruePerformanceFee,
    state,
    reset,
  }
}

/** Parse a human amount of the vault asset into base units. */
export function parseAssetAmount(input: string, decimals = mandateConfig.assetDecimals): bigint {
  if (!input) return 0n
  try {
    return parseUnits(input, decimals)
  } catch {
    return 0n
  }
}
