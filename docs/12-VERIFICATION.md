# 12 — Verification Dossier

> Every external fact this project relies on, with the source. Re-verify anything you intend to
> *state* on stage. Nothing here is a claim about Skyline's own code — that is proven by
> `docs/08-TESTING.md`.

---

## 1. The dataset

**Source:** `https://github.com/AtriumAcademy/UHI-Hook-Data`
> "this is a repository for all the hook data from previous UHI cohorts that devs can give to AI
> tools to evaluate prior hook submissions. All data is taken from hooks.atrium.academy and
> scrubbed of any PII before being uploaded here after every hookathon."

| Field | Value |
|---|---|
| `hook_directory.csv` | 294,862 bytes — **759 submissions**, UHI1–UHI10 |
| `hook_directory.md` | 2,646,729 bytes — same data, markdown |
| Last commit | "add UHI10 data to hook directory downloads" — 2 Nov 2026 |
| Branches | `main`, `add-uhi10-hook-data` |

**Submissions per cohort:** UHI1 36 · UHI2 62 · UHI3 64 · UHI4 54 · UHI5 64 · UHI6 85 ·
UHI7 94 · **UHI8 172** (peak) · UHI9 80 · UHI10 47

**Prizes:** 148 of 759 submissions carry a prize (**19.5%**). 10 records are marked `Active?`.

**Prize categories** (raw values from the `Prize` column): Uniswap Prize (60 + combos),
EigenLayer Prize (16 + combos), Brevis Prize (10 + combos), Reactive Network Prize (7 + combos),
Arbitrum Prize (4 + combos), Flaunch Prize (4 + combos), Fhenix Prize (5 + combos),
Chainlink Prize (2 + combos), Across Prize (3), Circle Prize (1 + combos), Unichain Prize (4),
Ink Prize (1), General Prize (10).

> **Implication:** prizes are **sponsor-scoped**, not a single 1st/2nd-place ranking. Aiming at a
> specific sponsor prize is a legitimate strategy. See `docs/02-SUBMISSION.md` §13.

### 1.1 Tag frequency (saturation map)

`lp fees` 264 · `custom hooks` 225 · `lp liquidity` 215 · `dynamic fee` 197 · `dex` 195 ·
`mev` 187 · `unichain` 173 · `cross-chain` 110 · `oracle` 93 · `security` 90 ·
`yield farming` 84 · `stablecoins` 81 · `lvr` 77 · `defi` 76 · `trading rewards` 76 ·
`trading volume rewards` 63 · `rwa` 50 · `compliance` 42 · `price discovery` 40 ·
`custom routers` 38 · `noop` 38 · `order type` 36 · `kyc` 36 · `auctions` 36 · `cow` 32 ·
`pool native incentivization` 32 · `cfmm` 31 · `liquidity mining` 31 · `zk-snark` 29 ·
`machine learning` 29 · `tokenized stocks` 28 · **`reputation` 27** · `governance` 26 ·
`eth staking` 25 · `cpmm` 24 · `dynamic tick adjustment` 24 · `regulation` 23 ·
`inter-connected pools` 20 · `options/futures` 19 · `illiquid assets` 18

### 1.2 White-space search (the origin of this project)

Searching all 759 names + descriptions + tags:

| Term | Hits |
|---|---|
| **`mandate`** | **0** |
| **`performance fee`** | **0** |
| **`advisor`** | **0** |
| `curat*` | 4 (SocialPool UHI3, PumpUp UHI4, Devia UHI9, POSTMARK UHI10) |
| `reputation` | 32 |
| `vault` | 48 |
| `rebalanc*` | 42 |
| `exit queue` | 0 |
| `waterfall` | 1 (STRATUM, UHI8 — a *credit tranche* waterfall) |
| `junior` / `senior` | all tranche projects (TrancheShield, TrancheGuard, DualTranche Vault, Fixed-Income Tranche Hook, Sochalant, Unistrata, STRATUM, RiskShield) |
| `bond` | mostly fixed-income (BondMeBro, Bond Marketplace AMM, CleanFlow Bonds, Depthbond, Theta-BG…) — **no curator performance bond** |
| `adverse selection` | Hindsight, Assay, POSTMARK, Exposure Ledger (all UHI10, all MEV-attribution, none about exit ordering) |
| `withdrawal queue` | 1 (FLUXA, UHI10 — RWA maturity queue, no curator role) |
| `exit fee` | 1 (`loyalty-lock-hook`, UHI9 — a time-decaying fee, no curator alignment) |

---

## 2. The theme

**Source:** `https://atrium.academy/sponsors` → section "2026 hookathon themes".

> **UHI8: Asset-Class Specific Liquidity**
> **UHI9: Impermanent Loss and Yield Systems**
> **UHI10: Sustainable Liquidity and MEV Protection**
> **UHI11: Active Management and Curation**

The UHI11 detail body is collapsed client-side and was not extractable. The theme's example list
was recovered from a cohort participant's README (§4 below), which reproduces it as a table.

**Dates** (`https://opengrants.com/uniswap-hook-incubator-atrium-academy/`):
> "UHI11 orientation Oct 1, 2026, hookathon Nov 16-Dec 3, demo day Dec 11, 2026"

**UHI11 Demo Day livestream** (`https://www.youtube.com/watch?v=hFjGluh88Sg`, published 3 Nov 2026,
`isLive: true, isUpcoming: true` — a scheduled premiere).

**Program page** (`https://atrium.academy/uniswap`): "$260k+ in prizes, 500+ graduates, 400+
hooks built"; "6-week immersive bootcamp followed by a 3-week Hookathon"; "Top hooks will win
prizes"; "Present at a demo day to a panel of investors & researchers".

**Sponsor tiers** (`https://atrium.academy/sponsors`): Hook builder $5k · Brand builder $10k ·
Ecosystem builder $15k. Benefits include "Judging slot for your tech integrations" and "Your hook
ideas on official RFH page".

---

## 3. The Requests-for-Hooks board

**Source:** `https://rfh.atrium.academy` (Notion; readable via `https://r.jina.ai/https://rfh.atrium.academy`)

**Updated February 2026:**
- Perp DEXs built with hooks (Unichain)
- JIT liquidity / issuance hooks for new assets
- Stable-focused hooks
- Smart borrow & leveraged liquidity hooks
- Liquid staking token (LST) optimized hooks
- Liquidity locking & token launch hooks
- NFT strategy token hooks (Tokenworks-inspired)
- **External revenue–driven liquidity incentives (Liquity v2 / BOLD-inspired)**

**Updated April 2025:** Dynamic Fee · Rehypothecation · Custom Curve · Asynchronous Swap ·
MEV-Mitigating · Reward Aggregator · Liquidations · Auto-Position Rebalancing · Oracle Hooks ·
Permissioned Pool Hook · Auto-Hedging · TWAMM · LRT Liquidity · Internalized MEV · Oracleless
Lending · Tornado Cash on Hooks · Hook Safety as a Service · Gasless Swaps · Keeper Activity

> **Note:** no "curator" or "mandate" ask on the board. Skyline is **theme-aligned, not
> sponsor-aligned**. This is a genuine gap in our positioning — see `docs/13-RISKS.md` R-11.

---

## 4. The closest in-cohort project — VaultCurator

**Source:** `https://github.com/syed-ghufran-hassan/vault-curator` (created 4 Oct 2026, pushed
12 Oct 2026). README badge: `UHI-Cohort 11`. README footer: "Built during Uniswap Hook Incubator
Cohort 11 (UHI11)".

Its README maps itself onto the UHI11 theme examples — which is where we recovered the theme's
example list:

| Theme example | VaultCurator feature (their words) |
|---|---|
| Vault-managed or token-gated hook modules | `CuratedVault.sol` + `AllowlistChecker.sol` |
| Curated LP networks (depositors follow managers) | `StrategyRegistry.sol` |
| Hooks that auto-rebalance via oracle triggers | `CuratedLiquidityHook.sol` |
| Performance fees | High-water mark fee module |
| Strategy migration between pools | `StrategyRegistry.migrate()` |

**Verified at source level** (not from the README):

`contracts/CuratedVault.sol` functions: `_decimalsOffset`, `maxDeposit`, `maxMint`, `deposit`,
`mint`, `withdraw`, `redeem`, `harvest`, `_accrueFees`, `setFeeRecipient`, `setMgmtFee`,
`setPerfFee`, `setDepositCap`, `setDepositsPaused`, `deployCapital`.

- `bond` → **not present**
- withdrawal queue → **not present**
- `slash` → **not present**
- `priority` → **not present**
- `salt` → **not used at all**

`contracts/CuratedLiquidityHook.sol` functions: `getHookPermissions`, `_beforeSwap`, `_afterSwap`,
`_beforeAddLiquidity`, `rebalance`, `_computeDynamicFee`, `_getOraclePrice`, `_absDeviation`,
`setAllowlistChecker`, `setGatingEnabled`, `setDynamicFee`, `setMaxDeviation`,
`setRebalanceCooldown`.

- **`_beforeRemoveLiquidity` is not implemented.**
- `salt` → **not used**

> **Conclusion: the removal path is untouched.** VaultCurator's withdrawal is a symmetric
> ERC-4626 redeem. Skyline operates precisely there.

---

## 5. Prior hook art

**Source:** `https://github.com/nirholas/hookforge` — "50 production Uniswap v4 hooks that do not
exist yet … Every hook here is checked against the ~140 published hooks and hackathon submissions
before it is written, each one ships with its prior art stated in the source."

35 named hooks were parsed. The nearest to Skyline:

| Hook | Description (their words) | How Skyline differs |
|---|---|---|
| `LiquidityFloor` | "Holds each position to a fraction of its own additions until an unlock date, so commitments are fractional and race-free." | Time-based, single-party, no curator role, no obligation priority |
| `AgentBudget` | "Enforces a signed per-epoch spend budget in the pool itself, so a delegated agent key is bounded by the venue rather than by its own code." | Bounds what a manager may **spend**; Skyline bounds when a manager may **leave** |
| `EpochRebalance` | "An index whose entire weight schedule is fixed before anybody deposits, gliding continuously so no single block is worth racing to." | Commits to *weights*, not to *exit priority* |
| `CircuitBreaker` | "Halts swaps after a move larger than a threshold and resumes automatically after a cooldown. Withdrawals stay open." | Adopted as a principle — Skyline never freezes withdrawals |
| `DrawdownCap` | "Caps how much price impact one address may cause per epoch." | Different axis entirely |
| `RetroRebate` | "Pays volume rebates from closed on-chain epochs…" | Incentive distribution, not ordering |
| `ILInsurance`, `DepegShield`, `OracleBand`, `LMSR`, `FungibleRange`, `RangeRent`, `TickHarberger`, `ReputationFee`, `X402Gate`, `VestedBuy`, `ExpirySettle`, `MarkoutFee`, `AntiSnipeRamp`, `CommitRevealDark`, `ReserveStable`, `FlowClassifier`, `TopOfBlockAuction`, `PriorityFeeTax`, `BlockBatchClearing`, `ArbTaxDecay`, `YieldSpace`, `PowerPerp`, `RatchetFloor`, `GridLadder`, `DutchClearingLaunch`, `StreamDCA`, `TradingCalendar`, `LiquidityFloor`, `TenureWeightedFees` | — | No curator-bonded liquidity with depositor-priority exits |

**GitHub repository searches** — all returned **zero results**:

- `"curator bond" uniswap v4 liquidity`
- `uniswap v4 hook bonded liquidity manager withdraw lock`
- `solidity vault withdrawal queue curator priority liquidity`

---

## 6. Uniswap v4 mechanics (the load-bearing facts)

Verified by reading source at the **`v4.0.0` tag** and on `main`.

### 6.1 Position keying

`v4-core/src/libraries/Position.sol`:

```solidity
function calculatePositionKey(address owner, int24 tickLower, int24 tickUpper, bytes32 salt)
    internal pure returns (bytes32 positionKey)
{
    // positionKey = keccak256(abi.encodePacked(owner, tickLower, tickUpper, salt))
    ...
    positionKey := keccak256(add(fmp, 0x0c), 0x3a) // len is 58 bytes
}
```

`Position.get(self, owner, tickLower, tickUpper, salt)` — the owner is part of the key.

### 6.2 The owner is `msg.sender`

`v4-core/src/PoolManager.sol` → `modifyLiquidity`:

```solidity
key.hooks.beforeModifyLiquidity(key, params, hookData);

(balanceDelta, feesAccrued) = pool.modifyLiquidity(
    Pool.ModifyLiquidityParams({
        owner: msg.sender,
        tickLower: params.tickLower,
        tickUpper: params.tickUpper,
        liquidityDelta: params.liquidityDelta.toInt128(),
        tickSpacing: key.tickSpacing,
        salt: params.salt
    })
);
```

### 6.3 `salt` exists for exactly this purpose

`v4-core/src/types/PoolOperation.sol`:

```solidity
struct ModifyLiquidityParams {
    int24 tickLower;
    int24 tickUpper;
    int256 liquidityDelta;
    // a value to set if you want unique liquidity positions at the same range
    bytes32 salt;
}
```

### 6.4 The hook receives the owner and the salt

`v4-core/src/interfaces/IHooks.sol`:

```solidity
function beforeRemoveLiquidity(
    address sender,              // "The initial msg.sender for the remove liquidity call"
    PoolKey calldata key,
    ModifyLiquidityParams calldata params,
    bytes calldata hookData
) external returns (bytes4);
```

`Hooks.beforeModifyLiquidity` dispatches on the sign of `liquidityDelta` and passes `msg.sender`
(the PoolManager's caller) as `sender`.

### 6.5 A hook failure reverts the operation

`v4-core/src/libraries/Hooks.sol`:

```solidity
if (!success) CustomRevert.bubbleUpAndRevertWith(address(self), bytes4(data), HookCallFailed.selector);
```

### 6.6 There are no public getters on `PoolManager`

All pool reads go through `v4-core/src/libraries/StateLibrary.sol` (`extsload`/`exttload`):

```solidity
function getPositionInfo(
    IPoolManager manager, PoolId poolId,
    address owner, int24 tickLower, int24 tickUpper, bytes32 salt
) internal view returns (uint128 liquidity, uint256 feeGrowthInside0LastX128, uint256 feeGrowthInside1LastX128)
```

Plus `getSlot0`, `getLiquidity`, `getTickInfo`, `getTickLiquidity`, `getFeeGrowthGlobals`,
`getPositionLiquidity`.

> **Consequence:** `poolManager.getSlot0(...)` does not compile. Use `StateLibrary`.

### 6.7 PoolId derivation

`PoolId = keccak256(abi.encode(poolKey))`. `PoolKey` is a struct of static types, so
`abi.encode` is the concatenation of 32-byte words — matching `encodeAbiParameters` on the client.

### 6.8 `BaseHook` location

`Uniswap/v4-hooks-public` → `src/base/BaseHook.sol`. **Not** in `Uniswap/v4-periphery` (removed)
and **not** at `Uniswap/hooks` (404). `Uniswap/v4-template` has not been pushed since Oct 2025.

### 6.9 The periphery PositionManager

`v4-periphery/src/PositionManager.sol` uses `salt: bytes32(tokenId)` — the position NFT's id is
the salt, and the owner is the PositionManager. Skyline writes its own vault and calls
`PoolManager.modifyLiquidity` directly, so it controls both the owner and the salt.

---

## 7. Commercial landscape (for the "is there a business" question)

| Project | Note |
|---|---|
| `https://lphub.xyz/` | Participants came through UHI5, joined the Hook Product Accelerator. Dynamic liquidity pricing, LP strategy building, embedded market making, improved liquidity allocation. |
| `https://arrakis.finance/` | Professional liquidity management for token issuers: automated provision, rebalancing, cross-pool management. |
| `Gauntlet`, `Brahmin`, `Steward` | The institutional-curator trend Skyline targets. |
| `Morpho`, `Yearn`, `Goldfinch` | Withdrawal queues / epochs — depositor-side timing only, no curator subordination. |

---

## 8. What we could NOT verify

| Item | Status | Action |
|---|---|---|
| **UHI11's live sponsor list and prize categories** | The atrium sponsors page ticker shows Uniswap, Arbitrum, Brevis, Fhenix, Ink; the historical prize set also includes Chainlink, EigenLayer, Circle, Flaunch, Across, Reactive, Unichain. **Not confirmed for UHI11.** | **Ask in the Discord before 16 Nov.** It determines which sponsor prize you target. |
| The UHI11 theme's full body text | The accordion is collapsed client-side. The example list was recovered from §4. | Re-check the Discord for the official brief. |
| The Nov 16 idea-submission portal | `https://atriumacademy.notion.site/p/1545f0444abe803997e0d26a51c60e25` → "This page couldn't be found". The atrium flow is Discord-gated. | Get the real form from the announcement. |
| Whether any *unpublished* project implements CEP | Impossible to rule out. Absence of a keyword across 759 submissions is evidence, not proof. | Mitigated by: (a) hookforge's claim to check every published hook, (b) VaultCurator's source, (c) the hookforge `LiquidityFloor`/`AgentBudget` prior art we cite. |

---

## 9. Re-verification commands

```bash
# The dataset
curl -s https://raw.githubusercontent.com/AtriumAcademy/UHI-Hook-Data/HEAD/hook_directory.csv -o hooks.csv

# v4 position keying
curl -s https://raw.githubusercontent.com/Uniswap/v4-core/v4.0.0/src/libraries/Position.sol

# PoolManager owner/salt handling
curl -s https://raw.githubusercontent.com/Uniswap/v4-core/v4.0.0/src/PoolManager.sol | grep -A25 "function modifyLiquidity"

# Hook callback signatures
curl -s https://raw.githubusercontent.com/Uniswap/v4-core/v4.0.0/src/interfaces/IHooks.sol | grep -A6 beforeRemoveLiquidity

# StateLibrary read path
curl -s https://raw.githubusercontent.com/Uniswap/v4-core/main/src/libraries/StateLibrary.sol | grep -A8 getPositionInfo

# BaseHook location
curl -s https://raw.githubusercontent.com/Uniswap/v4-hooks-public/main/src/base/BaseHook.sol | head -5

# Theme
curl -s https://atrium.academy/sponsors | grep -o "UHI1[01]:[^<]*"

# Requests for hooks
curl -s https://r.jina.ai/https://rfh.atrium.academy

# Closest competitor
curl -s https://raw.githubusercontent.com/syed-ghufran-hassan/vault-curator/HEAD/contracts/CuratedLiquidityHook.sol | grep "function _"
```

---

*Next: `docs/13-RISKS.md`.*
