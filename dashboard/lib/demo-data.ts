/**
 * DEMO MODE fixture.
 *
 * These numbers reproduce the worked example in `docs/04-ECONOMICS.md` §5, which
 * is the same scenario used in `docs/11-DEMO.md`. The component tree is
 * identical whether the data comes from here or from the chain — only the source
 * of the numbers changes.
 *
 * RULE: the fixture is presentation-only. It must never be used to decide what a
 * transaction does. If you are about to send a transaction, read the chain.
 */

import type { Claim, Mandate, MandateState } from "@/hooks/use-mandate"

/** Scenario A — "the curator cannot run". A claim is outstanding; the exit is blocked. */
export const demoScenarioBlocked: MandateState = {
  demo: true,
  chainId: 84532,
  poolId: "0x9f2c1b7d4e6a8f30c5b2d9e7a1c4f8b60d3e5a2c7f9b1d4e6a8c0f2b4d6e8a0c" as `0x${string}`,
  hookAddress: "0x1111111111111111111111111111111111111111",
  vaultAddress: "0x2222222222222222222222222222222222222222",
  curatorAddress: "0x3333333333333333333333333333333333333333",
  depositorAddress: "0x4444444444444444444444444444444444444444",

  pendingLiquidity: 55_556n,
  curatorLiquidity: 20_000n,
  depositorLiquidity: 80_000n,
  curatorExitApproved: false,
  curatorExitBlocked: true,
  riskState: 0,
  effectiveRiskState: 0,
  riskStateUpdatedAt: BigInt(Math.floor(Date.now() / 1000)),

  mandate: {
    maxFeeBps: 3000,
    bandLower: -60,
    bandUpper: 60,
    minSkinBps: 1000,
    maxDrawdownBps: 1000,
    claimTtl: 86_400,
    riskState: 0,
  } satisfies Mandate,

  claims: [
    {
      claimId: 1n,
      depositor: "0x4444444444444444444444444444444444444444",
      liquidityAmount: 55_556n,
      settledAmount: 0n,
      registeredAt: BigInt(Math.floor(Date.now() / 1000) - 600),
      expiresAt: BigInt(Math.floor(Date.now() / 1000) + 86_400 - 600),
      status: 1,
    },
  ],

  nextClaimId: 2n,
  totalAssets: 72_000_000_000n, // 72,000 USDC (6dp)
  totalSupply: 72_000_000_000n,
  userShares: 50_000_000_000n,
  navPerShare: 1_000_000n,
  highWaterMark: 1_388_888n,
  perfFeeBps: 1500,
  outstandingClaims: 1n,
  uncoveredShortfall: 0n,
  curatorBondValue: 20_000_000_000n,
  curatorExitProceeds: 20_000_000_000n,
  currentSkinBps: 2000,
  verifyCep: { cepHolds: true, pending: 55_556n, curatorLiquidity: 20_000n, curatorMayExit: false },
  verifyCuratorBond: { poolDerived: 20_000n, recorded: 20_000n },
  verifyPending: { derived: 55_556n, recorded: 55_556n },
}

/** Scenario B — "the bond absorbs the shortfall". The curator's capital covers the gap. */
export const demoScenarioAbsorption: MandateState = {
  ...demoScenarioBlocked,
  pendingLiquidity: 90_000n,
  curatorLiquidity: 10_000n,
  depositorLiquidity: 80_000n,
  claims: [
    {
      claimId: 1n,
      depositor: "0x4444444444444444444444444444444444444444",
      liquidityAmount: 90_000n,
      settledAmount: 0n,
      registeredAt: BigInt(Math.floor(Date.now() / 1000) - 600),
      expiresAt: BigInt(Math.floor(Date.now() / 1000) + 86_400 - 600),
      status: 1,
    },
  ],
  uncoveredShortfall: 10_000_000_000n,
  curatorBondValue: 10_000_000_000n,
  curatorExitProceeds: 0n,
  currentSkinBps: 1111,
  verifyCep: { cepHolds: true, pending: 90_000n, curatorLiquidity: 10_000n, curatorMayExit: false },
  verifyCuratorBond: { poolDerived: 10_000n, recorded: 10_000n },
  verifyPending: { derived: 90_000n, recorded: 90_000n },
}

/** Scenario C — "the exit opens once obligations are settled". */
export const demoScenarioSettled: MandateState = {
  ...demoScenarioBlocked,
  pendingLiquidity: 0n,
  curatorExitApproved: true,
  curatorExitBlocked: false,
  claims: [
    {
      claimId: 1n,
      depositor: "0x4444444444444444444444444444444444444444",
      liquidityAmount: 55_556n,
      settledAmount: 55_556n,
      registeredAt: BigInt(Math.floor(Date.now() / 1000) - 900),
      expiresAt: BigInt(Math.floor(Date.now() / 1000) + 86_400 - 900),
      status: 2,
    },
  ],
  outstandingClaims: 0n,
  verifyCep: { cepHolds: true, pending: 0n, curatorLiquidity: 20_000n, curatorMayExit: true },
  verifyPending: { derived: 0n, recorded: 0n },
}

/**
 * DEMO MODE lets the presenter switch scenario with a query parameter:
 *   /dashboard?scenario=blocked | absorption | settled
 * This is the Demo Day contingency: if the RPC or the chain misbehaves, the
 * dashboard still tells the story.
 */
export function scenarioFromQuery(value: string | null): MandateState {
  switch (value) {
    case "absorption":
      return demoScenarioAbsorption
    case "settled":
      return demoScenarioSettled
    case "blocked":
    default:
      return demoScenarioBlocked
  }
}

/** Type re-export so the fixture file stays in sync with the hook's types. */
export type { Claim }
