/**
 * Skyline contract addresses, ABIs and pool configuration.
 *
 * Addresses come from environment variables so the same build can point at any
 * deployment. When a variable is missing the dashboard falls back to DEMO MODE,
 * which renders the identical component tree from a local fixture. See
 * `lib/demo-data.ts`.
 *
 * NEVER hard-code an address here. Never trust a value from this file for a
 * financial decision — the chain is the source of truth.
 */

import { encodeAbiParameters, keccak256 } from "viem"
import type { Abi } from "viem"

/* -------------------------------------------------------------------------- */
/*  Environment                                                               */
/* -------------------------------------------------------------------------- */

function env(name: string): string | undefined {
  const v = process.env[name]
  return v && v.length > 0 ? v : undefined
}

export const config = {
  /** Chain id the dashboard targets. 84532 = Base Sepolia, 1301 = Unichain Sepolia. */
  chainId: Number(env("NEXT_PUBLIC_CHAIN_ID") ?? 84532),

  rpcUrl:
    env("NEXT_PUBLIC_RPC_URL") ??
    (Number(env("NEXT_PUBLIC_CHAIN_ID") ?? 84532) === 1301
      ? "https://sepolia.unichain.org"
      : "https://sepolia.base.org"),

  /** SkylineHook — the enforcement point. */
  hookAddress: env("NEXT_PUBLIC_HOOK_ADDRESS") as `0x${string}` | undefined,

  /** SkylineVault — depositor accounting, claims, settlement. */
  vaultAddress: env("NEXT_PUBLIC_VAULT_ADDRESS") as `0x${string}` | undefined,

  /** CuratorRegistry. */
  registryAddress: env("NEXT_PUBLIC_REGISTRY_ADDRESS") as `0x${string}` | undefined,

  /** Pool parameters, used to derive the PoolId on the client. */
  currency0: (env("NEXT_PUBLIC_CURRENCY0") ?? "0x0000000000000000000000000000000000000000") as `0x${string}`,
  currency1: (env("NEXT_PUBLIC_CURRENCY1") ?? "0x0000000000000000000000000000000000000000") as `0x${string}`,
  fee: Number(env("NEXT_PUBLIC_POOL_FEE") ?? 3000),
  tickSpacing: Number(env("NEXT_PUBLIC_TICK_SPACING") ?? 60),

  /** USDC decimals (6 on Base). Overridable for other assets. */
  assetDecimals: Number(env("NEXT_PUBLIC_ASSET_DECIMALS") ?? 6),
  assetSymbol: env("NEXT_PUBLIC_ASSET_SYMBOL") ?? "USDC",

  /**
   * DEMO MODE.
   * Renders the dashboard from a local fixture instead of the chain. Used when
   * the contracts are not yet deployed, when a public RPC is flaky, and as the
   * contingency plan for Demo Day.
   */
} as const

/** True when the dashboard should render from a local fixture instead of the chain. */
export function isDemoMode(): boolean {
  const explicit = env("NEXT_PUBLIC_DEMO_MODE")
  if (explicit === "true") return true
  if (explicit === "false") return false
  return !config.hookAddress || !config.vaultAddress
}

/* -------------------------------------------------------------------------- */
/*  ABIs — minimal, matching docs/06-API.md                                    */
/* -------------------------------------------------------------------------- */

export const mandateHookAbi = [
  // --- registration ---
  {
    type: "function",
    name: "registerPool",
    stateMutability: "nonpayable",
    inputs: [
      { name: "poolId", type: "bytes32" },
      { name: "vault", type: "address" },
      { name: "curator", type: "address" },
      { name: "oracle", type: "address" },
      {
        name: "mandate",
        type: "tuple",
        components: [
          { name: "maxFeeBps", type: "uint24" },
          { name: "bandLower", type: "int24" },
          { name: "bandUpper", type: "int24" },
          { name: "minSkinBps", type: "uint32" },
          { name: "maxDrawdownBps", type: "uint32" },
          { name: "claimTtl", type: "uint32" },
          { name: "riskState", type: "uint8" },
        ],
      },
    ],
    outputs: [],
  },
  {
    type: "function",
    name: "setMandate",
    stateMutability: "nonpayable",
    inputs: [
      { name: "poolId", type: "bytes32" },
      {
        name: "m",
        type: "tuple",
        components: [
          { name: "maxFeeBps", type: "uint24" },
          { name: "bandLower", type: "int24" },
          { name: "bandUpper", type: "int24" },
          { name: "minSkinBps", type: "uint32" },
          { name: "maxDrawdownBps", type: "uint32" },
          { name: "claimTtl", type: "uint32" },
          { name: "riskState", type: "uint8" },
        ],
      },
    ],
    outputs: [],
  },

  // --- claims ---
  {
    type: "function",
    name: "registerClaim",
    stateMutability: "nonpayable",
    inputs: [
      { name: "poolId", type: "bytes32" },
      { name: "claimId", type: "uint256" },
      { name: "liquidityAmount", type: "uint128" },
      { name: "depositor", type: "address" },
    ],
    outputs: [{ name: "", type: "bool" }],
  },
  {
    type: "function",
    name: "expireClaim",
    stateMutability: "nonpayable",
    inputs: [{ name: "poolId", type: "bytes32" }, { name: "claimId", type: "uint256" }],
    outputs: [{ name: "", type: "bool" }],
  },
  {
    type: "function",
    name: "approveCuratorExit",
    stateMutability: "nonpayable",
    inputs: [{ name: "poolId", type: "bytes32" }],
    outputs: [{ name: "", type: "bool" }],
  },

  // --- views ---
  {
    type: "function",
    name: "pendingLiquidity",
    stateMutability: "view",
    inputs: [{ name: "poolId", type: "bytes32" }],
    outputs: [{ name: "", type: "int128" }],
  },
  {
    type: "function",
    name: "curatorLiquidity",
    stateMutability: "view",
    inputs: [{ name: "poolId", type: "bytes32" }],
    outputs: [{ name: "", type: "int128" }],
  },
  {
    type: "function",
    name: "depositorLiquidity",
    stateMutability: "view",
    inputs: [{ name: "poolId", type: "bytes32" }],
    outputs: [{ name: "", type: "int128" }],
  },
  {
    type: "function",
    name: "nextClaimId",
    stateMutability: "view",
    inputs: [{ name: "poolId", type: "bytes32" }],
    outputs: [{ name: "", type: "uint256" }],
  },
  {
    type: "function",
    name: "riskState",
    stateMutability: "view",
    inputs: [{ name: "poolId", type: "bytes32" }],
    outputs: [{ name: "", type: "uint8" }],
  },
  {
    type: "function",
    name: "effectiveRiskState",
    stateMutability: "view",
    inputs: [{ name: "poolId", type: "bytes32" }],
    outputs: [{ name: "", type: "uint8" }],
  },
  {
    type: "function",
    name: "riskStateUpdatedAt",
    stateMutability: "view",
    inputs: [{ name: "poolId", type: "bytes32" }],
    outputs: [{ name: "", type: "uint64" }],
  },
  {
    type: "function",
    name: "isCuratorExitBlocked",
    stateMutability: "view",
    inputs: [{ name: "poolId", type: "bytes32" }],
    outputs: [{ name: "", type: "bool" }],
  },
  {
    type: "function",
    name: "curatorExitApproved",
    stateMutability: "view",
    inputs: [{ name: "poolId", type: "bytes32" }],
    outputs: [{ name: "", type: "bool" }],
  },
  {
    type: "function",
    name: "claim",
    stateMutability: "view",
    inputs: [{ name: "poolId", type: "bytes32" }, { name: "claimId", type: "uint256" }],
    outputs: [
      {
        name: "",
        type: "tuple",
        components: [
          { name: "liquidityAmount", type: "uint128" },
          { name: "settledAmount", type: "uint128" },
          { name: "totalLiquidityAtRegistration", type: "uint128" },
          { name: "registeredAt", type: "uint64" },
          { name: "expiresAt", type: "uint64" },
          { name: "status", type: "uint8" },
          { name: "depositor", type: "address" },
        ],
      },
    ],
  },
  {
    type: "function",
    name: "mandate",
    stateMutability: "view",
    inputs: [{ name: "poolId", type: "bytes32" }],
    outputs: [
      {
        name: "",
        type: "tuple",
        components: [
          { name: "maxFeeBps", type: "uint24" },
          { name: "bandLower", type: "int24" },
          { name: "bandUpper", type: "int24" },
          { name: "minSkinBps", type: "uint32" },
          { name: "maxDrawdownBps", type: "uint32" },
          { name: "claimTtl", type: "uint32" },
          { name: "riskState", type: "uint8" },
        ],
      },
    ],
  },
  {
    type: "function",
    name: "poolConfigs",
    stateMutability: "view",
    inputs: [{ name: "poolId", type: "bytes32" }],
    outputs: [
      {
        name: "",
        type: "tuple",
        components: [
          { name: "vault", type: "address" },
          { name: "curator", type: "address" },
          { name: "oracle", type: "address" },
          { name: "registered", type: "bool" },
        ],
      },
    ],
  },
  {
    type: "function",
    name: "verifyCep",
    stateMutability: "view",
    inputs: [{ name: "poolId", type: "bytes32" }],
    outputs: [
      { name: "cepHolds", type: "bool" },
      { name: "pending", type: "int128" },
      { name: "curatorLiquidity", type: "int128" },
      { name: "curatorMayExit", type: "bool" },
    ],
  },
  {
    type: "function",
    name: "verifyCuratorBond",
    stateMutability: "view",
    inputs: [{ name: "poolId", type: "bytes32" }],
    outputs: [
      { name: "poolDerived", type: "int128" },
      { name: "recorded", type: "int128" },
    ],
  },
  {
    type: "function",
    name: "verifyPending",
    stateMutability: "view",
    inputs: [{ name: "poolId", type: "bytes32" }],
    outputs: [
      { name: "derived", type: "int128" },
      { name: "recorded", type: "int128" },
    ],
  },

  // --- events ---
  {
    type: "event",
    name: "ClaimRegistered",
    inputs: [
      { name: "poolId", type: "bytes32", indexed: true },
      { name: "claimId", type: "uint256", indexed: true },
      { name: "liquidityAmount", type: "uint128", indexed: false },
      { name: "depositor", type: "address", indexed: false },
    ],
  },
  {
    type: "event",
    name: "ClaimSettled",
    inputs: [
      { name: "poolId", type: "bytes32", indexed: true },
      { name: "claimId", type: "uint256", indexed: true },
      { name: "liquidityRemoved", type: "int128", indexed: false },
      { name: "remaining", type: "uint128", indexed: false },
    ],
  },
  {
    type: "event",
    name: "CuratorExitBlocked",
    inputs: [
      { name: "poolId", type: "bytes32", indexed: true },
      { name: "pendingLiquidity", type: "int128", indexed: false },
    ],
  },
  {
    type: "event",
    name: "RiskStateChanged",
    inputs: [
      { name: "poolId", type: "bytes32", indexed: true },
      { name: "oldState", type: "uint8", indexed: false },
      { name: "newState", type: "uint8", indexed: false },
      { name: "drawdownBps", type: "uint256", indexed: false },
    ],
  },
] as const satisfies Abi

export const mandateVaultAbi = [
  // --- views ---
  {
    type: "function",
    name: "totalAssets",
    stateMutability: "view",
    inputs: [],
    outputs: [{ name: "", type: "uint256" }],
  },
  {
    type: "function",
    name: "totalSupply",
    stateMutability: "view",
    inputs: [],
    outputs: [{ name: "", type: "uint256" }],
  },
  {
    type: "function",
    name: "balanceOf",
    stateMutability: "view",
    inputs: [{ name: "account", type: "address" }],
    outputs: [{ name: "", type: "uint256" }],
  },
  {
    type: "function",
    name: "convertToAssets",
    stateMutability: "view",
    inputs: [{ name: "shares", type: "uint256" }],
    outputs: [{ name: "", type: "uint256" }],
  },
  {
    type: "function",
    name: "convertToShares",
    stateMutability: "view",
    inputs: [{ name: "assets", type: "uint256" }],
    outputs: [{ name: "", type: "uint256" }],
  },
  {
    type: "function",
    name: "navPerShare",
    stateMutability: "view",
    inputs: [],
    outputs: [{ name: "", type: "uint256" }],
  },
  {
    type: "function",
    name: "highWaterMark",
    stateMutability: "view",
    inputs: [],
    outputs: [{ name: "", type: "uint256" }],
  },
  {
    type: "function",
    name: "perfFeeBps",
    stateMutability: "view",
    inputs: [],
    outputs: [{ name: "", type: "uint16" }],
  },
  {
    type: "function",
    name: "outstandingClaims",
    stateMutability: "view",
    inputs: [],
    outputs: [{ name: "", type: "uint256" }],
  },
  {
    type: "function",
    name: "outstandingClaimLiquidity",
    stateMutability: "view",
    inputs: [],
    outputs: [{ name: "", type: "int128" }],
  },
  {
    type: "function",
    name: "uncoveredShortfall",
    stateMutability: "view",
    inputs: [],
    outputs: [{ name: "", type: "uint256" }],
  },
  {
    type: "function",
    name: "currentSkinBps",
    stateMutability: "view",
    inputs: [],
    outputs: [{ name: "", type: "uint32" }],
  },
  {
    type: "function",
    name: "curatorBondValue",
    stateMutability: "view",
    inputs: [],
    outputs: [{ name: "", type: "uint256" }],
  },
  {
    type: "function",
    name: "curatorExitProceeds",
    stateMutability: "view",
    inputs: [],
    outputs: [{ name: "", type: "uint256" }],
  },
  {
    type: "function",
    name: "curator",
    stateMutability: "view",
    inputs: [],
    outputs: [{ name: "", type: "address" }],
  },
  {
    type: "function",
    name: "asset",
    stateMutability: "view",
    inputs: [],
    outputs: [{ name: "", type: "address" }],
  },

  // --- actions ---
  {
    type: "function",
    name: "deposit",
    stateMutability: "nonpayable",
    inputs: [
      { name: "assets", type: "uint256" },
      { name: "receiver", type: "address" },
    ],
    outputs: [{ name: "shares", type: "uint256" }],
  },
  {
    type: "function",
    name: "requestWithdraw",
    stateMutability: "nonpayable",
    inputs: [{ name: "shares", type: "uint256" }],
    outputs: [{ name: "claimId", type: "uint256" }],
  },
  {
    type: "function",
    name: "settleClaims",
    stateMutability: "nonpayable",
    inputs: [{ name: "maxClaims", type: "uint256" }],
    outputs: [{ name: "settled", type: "uint256" }],
  },
  {
    type: "function",
    name: "requestCuratorExit",
    stateMutability: "nonpayable",
    inputs: [],
    outputs: [{ name: "", type: "bool" }],
  },
  {
    type: "function",
    name: "curatorDeposit",
    stateMutability: "nonpayable",
    inputs: [{ name: "assets", type: "uint256" }],
    outputs: [{ name: "liquidityAdded", type: "uint128" }],
  },
  {
    type: "function",
    name: "accruePerformanceFee",
    stateMutability: "nonpayable",
    inputs: [],
    outputs: [{ name: "feeShares", type: "uint256" }],
  },

  // --- events ---
  {
    type: "event",
    name: "WithdrawalRequested",
    inputs: [
      { name: "depositor", type: "address", indexed: true },
      { name: "claimId", type: "uint256", indexed: true },
      { name: "shares", type: "uint256", indexed: false },
      { name: "liquidityAmount", type: "uint128", indexed: false },
    ],
  },
  {
    type: "event",
    name: "ShortfallAbsorbed",
    inputs: [
      { name: "curator", type: "address", indexed: true },
      { name: "amount", type: "uint256", indexed: false },
      { name: "remainingShortfall", type: "uint256", indexed: false },
    ],
  },
  {
    type: "event",
    name: "CuratorExited",
    inputs: [
      { name: "curator", type: "address", indexed: true },
      { name: "proceeds", type: "uint256", indexed: false },
      { name: "shortfallNetted", type: "uint256", indexed: false },
    ],
  },
] as const satisfies Abi

/* -------------------------------------------------------------------------- */
/*  Errors — decoded for the demo                                              */
/* -------------------------------------------------------------------------- */

export const mandateHookErrors = [
  { name: "CuratorExitBlocked", args: [{ name: "pendingLiquidity", type: "int128" }] },
  { name: "CuratorExitNotApproved", args: [] },
  { name: "ExceedsShortfall", args: [] },
  { name: "FeeCapExceeded", args: [{ name: "fee", type: "uint24" }, { name: "cap", type: "uint24" }] },
  { name: "BelowBand", args: [{ name: "tickLower", type: "int24" }, { name: "bandLower", type: "int24" }] },
  { name: "AboveBand", args: [{ name: "tickUpper", type: "int24" }, { name: "bandUpper", type: "int24" }] },
  { name: "SkinTooLow", args: [{ name: "actualBps", type: "uint32" }, { name: "requiredBps", type: "uint32" }] },
  { name: "RiskStateRestricted", args: [] },
  { name: "RiskStateBreached", args: [] },
  { name: "SettlementNotCorroborated", args: [] },
  { name: "OverClaim", args: [] },
  { name: "PoolAlreadyRegistered", args: [] },
  { name: "PoolNotRegistered", args: [] },
] as const

export const mandateVaultErrors = [
  { name: "ClaimLimitExceeded", args: [] },
  { name: "MinClaimSize", args: [] },
  { name: "CoolingOff", args: [] },
  { name: "NothingToSettle", args: [] },
  { name: "InsufficientShares", args: [] },
  { name: "ZeroAmount", args: [] },
] as const

/**
 * A decode-only ABI carrying the custom errors from both contracts, so a revert
 * can be turned into a plain-English sentence instead of a hex blob.
 *
 * Written out explicitly rather than mapped, so the ABI stays a literal type and
 * TypeScript can decode against it.
 */
export const mandateErrorsAbi = [
  { type: "error", name: "CuratorExitBlocked", inputs: [{ name: "pendingLiquidity", type: "int128" }] },
  { type: "error", name: "CuratorExitNotApproved", inputs: [] },
  { type: "error", name: "ExceedsShortfall", inputs: [] },
  { type: "error", name: "FeeCapExceeded", inputs: [{ name: "fee", type: "uint24" }, { name: "cap", type: "uint24" }] },
  { type: "error", name: "BelowBand", inputs: [{ name: "tickLower", type: "int24" }, { name: "bandLower", type: "int24" }] },
  { type: "error", name: "AboveBand", inputs: [{ name: "tickUpper", type: "int24" }, { name: "bandUpper", type: "int24" }] },
  { type: "error", name: "SkinTooLow", inputs: [{ name: "actualBps", type: "uint32" }, { name: "requiredBps", type: "uint32" }] },
  { type: "error", name: "RiskStateRestricted", inputs: [] },
  { type: "error", name: "RiskStateBreached", inputs: [] },
  { type: "error", name: "SettlementNotCorroborated", inputs: [] },
  { type: "error", name: "OverClaim", inputs: [] },
  { type: "error", name: "PoolAlreadyRegistered", inputs: [] },
  { type: "error", name: "PoolNotRegistered", inputs: [] },
  { type: "error", name: "ClaimLimitExceeded", inputs: [] },
  { type: "error", name: "MinClaimSize", inputs: [] },
  { type: "error", name: "CoolingOff", inputs: [] },
  { type: "error", name: "NothingToSettle", inputs: [] },
  { type: "error", name: "InsufficientShares", inputs: [] },
  { type: "error", name: "ZeroAmount", inputs: [] },
] as const satisfies Abi

/* -------------------------------------------------------------------------- */
/*  Derived pool identifiers                                                   */
/* -------------------------------------------------------------------------- */

/**
 * The two v4 position salts. They MUST match `src/libraries/SkylineTypes.sol`.
 * See docs/03-ARCHITECTURE.md §3.2.
 */
export const SALTS = {
  LP: "0x0000000000000000000000000000000000000000000000000000000000000001",
  CURATOR: "0x0000000000000000000000000000000000000000000000000000000000000002",
} as const

/**
 * Derive the v4 `PoolId` from the pool key.
 *
 * v4 computes `PoolId = keccak256(abi.encode(poolKey))`. PoolKey is a struct of
 * static types, so `abi.encode` is the concatenation of 32-byte words — which is
 * exactly what `encodeAbiParameters` produces.
 */
export function derivePoolId(params?: {
  currency0?: `0x${string}`
  currency1?: `0x${string}`
  fee?: number
  tickSpacing?: number
  hooks?: `0x${string}`
}): `0x${string}` | undefined {
  const currency0 = params?.currency0 ?? config.currency0
  const currency1 = params?.currency1 ?? config.currency1
  const fee = params?.fee ?? config.fee
  const tickSpacing = params?.tickSpacing ?? config.tickSpacing
  const hooks = params?.hooks ?? config.hookAddress

  if (!currency0 || !currency1 || !hooks) return undefined
  if (currency0 === "0x0000000000000000000000000000000000000000") return undefined
  if (currency1 === "0x0000000000000000000000000000000000000000") return undefined
  if (!hooks || hooks === "0x0000000000000000000000000000000000000000") return undefined

  return keccak256(
    encodeAbiParameters(
      [
        { type: "address" },
        { type: "address" },
        { type: "uint24" },
        { type: "int24" },
        { type: "address" },
      ],
      [currency0, currency1, fee, tickSpacing, hooks],
    ),
  )
}

/** The PoolId for the configured deployment, or undefined if not configured. */
export const poolId = derivePoolId()

/** Explorer link helper. */
export function explorerUrl(kind: "address" | "tx", value: string): string {
  const base =
    config.chainId === 84532
      ? "https://sepolia.basescan.org"
      : config.chainId === 1301
        ? "https://sepolia.unichainscan.xyz"
        : "https://sepolia.basescan.org"
  return `${base}/${kind}/${value}`
}
