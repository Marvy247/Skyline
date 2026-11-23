# 07 — Build Order

> **This is the execution plan.** Work top to bottom. Each phase has a gate: if the acceptance
> criteria are not met, do not start the next phase. Update `docs/15-PROGRESS.md` as you go.
>
> Deadline map: idea submission **16 Nov** · progress update 1 **23 Nov** · progress update 2
> **30 Nov** · final submission **3 Dec** · judging 4–10 Dec · Demo Day **11 Dec**.
> Build window: **16 Nov → 3 Dec = 17 days.**

---

## Phase 0 — Validate the primitives (½ day)

**Why this phase exists.** The entire design rests on v4 position-keying and salt semantics.
They have changed across releases. We have already been wrong once about which v4 version has
which API. Verify before building.

### Tasks

| # | Task | Output |
|---|---|---|
| 0.1 | Create the Foundry project. `forge init`, install `v4-core`, `v4-hooks-public`, `forge-std` at pinned tags. Record the pins in `foundry.toml` and in `docs/14-CONVENTIONS.md`. | `foundry.toml` with pinned deps |
| 0.2 | Read `v4-core/src/libraries/Position.sol` → confirm `calculatePositionKey(owner, tickLower, tickUpper, salt)` = `keccak256(abi.encodePacked(owner, tickLower, tickUpper, salt))`. | Assertion in `test/Primitives.t.sol` |
| 0.3 | Read `v4-core/src/PoolManager.sol` → confirm `modifyLiquidity` sets `owner: msg.sender` and passes `params.salt`. | Assertion in `test/Primitives.t.sol` |
| 0.4 | Read `v4-core/src/interfaces/IHooks.sol` → confirm `beforeRemoveLiquidity(address sender, PoolKey, ModifyLiquidityParams, bytes)` and that `ModifyLiquidityParams` carries `bytes32 salt`. | Note in `docs/15-PROGRESS.md` |
| 0.5 | Read `v4-core/src/libraries/StateLibrary.sol` → confirm `getPositionInfo(manager, poolId, owner, tickLower, tickUpper, salt)` exists and returns `(uint128 liquidity, uint256, uint256)`. | Note + helper in `test/Primitives.t.sol` |
| 0.6 | Read `v4-hooks-public/src/base/BaseHook.sol` → confirm `_beforeRemoveLiquidity` / `_afterRemoveLiquidity` exist and note the exact override signatures. | Note |
| 0.7 | Read `v4-core/src/libraries/Hooks.sol` → record the exact `Hooks.Permissions` field list for the pinned version. **Update `docs/03-ARCHITECTURE.md` §5 if it differs.** | Updated doc |
| 0.8 | Deploy a minimal `EchoHook` (BaseHook, `beforeRemoveLiquidity` logging `sender` and `params.salt`) on Base Sepolia. Add liquidity in two positions with **different salts** and remove from one. Observe the callback arguments. | Deployed address + tx hashes |
| 0.9 | Write `test/Primitives.t.sol::test_saltDistinguishesPositions` — two positions, same owner and ticks, different salt → distinct position keys, distinct liquidity. | Passing test |
| 0.10 | Write `test/Primitives.t.sol::test_onlyOwnerCanModifyPosition` — a third party cannot modify the vault's position. | Passing test |

### Acceptance criteria

- [ ] `forge test` passes with the primitives suite green
- [ ] A live testnet transaction demonstrates two same-range positions with different salts, and the hook observing distinct `salt` values
- [ ] Every assumption in `docs/03-ARCHITECTURE.md` §4 and §5 is confirmed against the pinned tag, and any divergence is documented and the docs updated
- [ ] The pinned tags are recorded in `docs/14-CONVENTIONS.md` §2

### If Phase 0 invalidates an assumption

Stop and re-read `docs/13-RISKS.md`. The fallback designs (salt-only attribution, or a
per-curator `owner` contract) are described there. Do **not** silently work around it — update
the architecture doc first.

---

## Phase 1 — Hook skeleton + shadow ledgers (1 day)

**Goal:** a hook that observes all liquidity and keeps exact counters. No economics yet.

### Files

```
src/
  interfaces/ISkylineHook.sol
  interfaces/ISkylineVault.sol
  SkylineHook.sol
  libraries/SkylineTypes.sol      # Mandate, Claim, PoolConfig, statuses, salts
  libraries/MandateErrors.sol
```

### Tasks

| # | Task | Notes |
|---|---|---|
| 1.1 | `SkylineTypes.sol`: `Mandate`, `Claim`, `PoolConfig`, `LP_SALT`, `CURATOR_SALT`, status constants, violation codes | Per `docs/06-API.md` §4, §6 |
| 1.2 | `SkylineHook` constructor + `getHookPermissions()` | Per `docs/03-ARCHITECTURE.md` §5 |
| 1.3 | `registerPool` — one-shot, `onlyOwner`, stores `PoolConfig` | Emit `PoolRegistered` |
| 1.4 | `_afterAddLiquidity` / `_afterRemoveLiquidity` → update `curatorLiquidity[poolId]` and `depositorLiquidity[poolId]` from `params.liquidityDelta` | **The shadow ledger** |
| 1.5 | `_beforeSwap` → compute a dynamic fee, cap it at `mandate.maxFeeBps` | Per `docs/04-ECONOMICS.md` §8 — no protocol fee collection in the MVP |
| 1.6 | `verifyCuratorBond` / `verifyPending` view helpers reading `StateLibrary` | Per `docs/06-API.md` §7 |
| 1.7 | `test/HookShadow.t.sol`: add/remove liquidity and assert the counters track exactly, including across multiple ticks and salts | |

### Acceptance criteria

- [ ] `curatorLiquidity` and `depositorLiquidity` match the pool's actual position liquidity, verified against `StateLibrary`, for every test case
- [ ] The dynamic fee never exceeds `maxFeeBps` — fuzz it
- [ ] `registerPool` cannot be called twice, nor by a non-owner

---

## Phase 2 — The claim ledger (1 day) — **THE THESIS**

**Goal:** the hook owns an authoritative, per-pool, liquidity-denominated obligation ledger,
and the curator's exit gate closes on it.

### Tasks

| # | Task | Notes |
|---|---|---|
| 2.1 | `registerClaim(poolId, claimId, liquidityAmount, depositor)` — `onlyVault`, monotonic id, expiry, `pendingLiquidity += amount`, revoke `curatorExitApproved` if `Q` transitions 0 → >0 | Emit `ClaimRegistered` |
| 2.2 | `settleClaim(poolId, claimId, liquidityRemoved)` — `onlyVault`, bounds, shadow-ledger corroboration, `pendingLiquidity -= amount`, update `settledAmount` | Emit `ClaimSettled` |
| 2.3 | `expireClaim(poolId, claimId)` — permissionless once `expiresAt` passed; `Q -= remainder`; emit `ClaimExpired` | Restores depositor shares in the vault (Phase 3) |
| 2.4 | `approveCuratorExit(poolId)` — `onlyVault`, requires `Q == 0` | Sets `curatorExitApproved` |
| 2.5 | `_beforeRemoveLiquidity` — the **exit gate**: curator-salt removal requires `Q == 0` **and** `curatorExitApproved`; the last-resort exception is `Q > depositorLiquidity` bounded by the shortfall | Emit `CuratorExitBlocked`; revert `CuratorExitBlocked` |
| 2.6 | `test/ClaimLedger.t.sol` — unit tests for every path | |
| 2.7 | `test/invariant/Cep.t.sol` — INV-2, INV-3, INV-8 with a stateful handler | Fuzz ≥ 10,000 runs |

### Acceptance criteria

- [ ] `pendingLiquidity` is always equal to the sum of unsettled claim remainders — **asserted in an invariant test**, not just unit-tested
- [ ] A curator removal reverts with `CuratorExitBlocked` while `Q > 0` and the protocol is solvent
- [ ] The last-resort removal never exceeds the shortfall — **asserted in the invariant test**
- [ ] `curatorExitApproved` is false whenever `Q > 0` — **asserted in the invariant test**

> **Gate.** Do not proceed until the CEP invariant test is green. This is the whole project.

---

## Phase 3 — The vault (2 days)

**Goal:** depositor shares, the claim queue, settlement, curator bond accounting.

### Files

```
src/
  SkylineVault.sol
  libraries/MandateMath.sol        # liquidity↔token conversion, rounding helpers
```

### Tasks

| # | Task | Notes |
|---|---|---|
| 3.1 | ERC-4626 core: `deposit`, `mint`, `withdraw`, `redeem`, `totalAssets`, `convertTo*` | With inflation-attack defence (`_decimalsOffset` or virtual shares) |
| 3.2 | `totalAssets()` — value of the depositor position **plus accrued fees**. **Never include curator bond value** | Critical: see `docs/04-ECONOMICS.md` §1 |
| 3.3 | `requestWithdraw(shares)` — burn/reserve shares, compute `liquidityAmount` (conservative pro-rata, per `docs/04-ECONOMICS.md` §4), call `hook.registerClaim` | Emit `WithdrawalRequested` |
| 3.4 | `settleClaims(maxClaims)` — permissionless, FIFO, `poolManager.unlock` → `modifyLiquidity(LP_SALT, −take)` → `hook.settleClaim` → pay depositor | Per `docs/03-ARCHITECTURE.md` §6.3 |
| 3.5 | `curatorDeposit` / `curatorTopUp` — add liquidity under `CURATOR_SALT` | `curatorBondValue()` derived from `StateLibrary`, not from vault books |
| 3.6 | `curatorDeposit` also enforces the min-skin projection, or the vault tops up | Per `docs/04-ECONOMICS.md` §6 |
| 3.7 | Claim expiry → restore depositor shares | Vault-side mirror of `hook.expireClaim` |
| 3.8 | `test/Vault.t.sol` — deposits, claims, settlement, NAV maths, share inflation attacks | Fuzz the NAV maths |

### Acceptance criteria

- [ ] A depositor can deposit, request, be settled, and end with zero position — **end-to-end in a test**
- [ ] `totalAssets()` never includes curator bond value — asserted
- [ ] `settleClaims` is permissionless and safe to call by anyone at any time
- [ ] NAV/share accounting survives fuzzing with no inflation extraction

---

## Phase 4 — Curator exit + loss absorption (1 day)

**Goal:** the full exit ladder, end to end.

### Tasks

| # | Task | Notes |
|---|---|---|
| 4.1 | `requestCuratorExit()` — curator-only, cooling-off, calls `hook.approveCuratorExit` | Emit `CuratorExitRequested` |
| 4.2 | `settleClaims` — extend to the three-stage ladder: depositor liquidity → curator bond → pro-rata last resort | `docs/04-ECONOMICS.md` §3 |
| 4.3 | Track `uncoveredShortfall` in token units; net it from curator exit proceeds | `docs/04-ECONOMICS.md` §5 |
| 4.4 | Curator exit payout = `bondValue − uncoveredShortfall` | |
| 4.5 | `test/ExitLadder.t.sol` — the full worked example from `docs/04-ECONOMICS.md` §5, asserted number by number | **This test is the demo's script** |
| 4.6 | `test/invariant/NoLockout.t.sol` — INV-6 | Fuzz ≥ 10,000 runs |

### Acceptance criteria

- [ ] The worked example reproduces exactly: 55,556 → blocked → settled → permitted
- [ ] The shortfall case reproduces exactly: 90,000 claim, 80,000 available, 10,000 absorbed by the bond
- [ ] **No reachable state leaves a depositor unable to exit** — invariant-tested
- [ ] The curator's exit proceeds are netted by any uncovered shortfall — invariant-tested

---

## Phase 5 — Mandate enforcement (1 day)

**Goal:** the hook enforces the curator's committed parameters.

### Tasks

| # | Task | Notes |
|---|---|---|
| 5.1 | Fee cap in `_beforeSwap` (done in 1.5; add the mandate parameter) | |
| 5.2 | Tick band check in `_beforeModifyLiquidity` for curator-salt modifications | Reverts `BelowBand` / `AboveBand` |
| 5.3 | Minimum-skin projection check in `_beforeModifyLiquidity` | Reverts `SkinTooLow`; round **against** the curator |
| 5.4 | ~~`performRebalance`~~ — **removed from the shipped surface.** The mandate fixes the pool and range; the curator can add bonded liquidity, not migrate the position. | Code and docs now say so explicitly |
| 5.5 | `setMandate` — curator may only tighten, never loosen, and only via a timelocked proposal | Not implemented; mandates are fixed at registration |
| 5.6 | `test/Mandate.t.sol` — every violation path | |

### Acceptance criteria

- [ ] Every mandate constraint has a test that shows the revert with the right custom error
- [ ] The curator cannot loosen the mandate unilaterally
- [ ] `currentSkinBps()` matches the ratio computed from `StateLibrary`

---

## Phase 6 — Performance fee, forfeiture, registry (1 day)

### Tasks

| # | Task | Notes |
|---|---|---|
| 6.1 | High-water-mark performance fee, dilution-only | `docs/04-ECONOMICS.md` §7 |
| 6.2 | `accruePerformanceFee()` — permissionless, call it before any withdrawal | |
| 6.3 | Forfeiture on detected drawdown breach | `docs/05-SECURITY.md` §6 |
| 6.4 | ~~`migrate(assets, targetVault)`~~ — **removed from the shipped surface.** Cross-vault migration is out of scope. | Avoids an untested asset path |
| 6.5 | `CuratorRegistry` — registration, `recordAbsorbed`, `recordFees` | Publishes, never punishes |
| 6.6 | `test/Fee.t.sol` | |

### Acceptance criteria

- [ ] The HWM never decreases; recovery from a drawdown pays no fee — invariant-tested
- [ ] Fee shares are dilution-only; the curator cannot withdraw principal

---

## Phase 7 — Chainlink (½ day)

**Goal:** a meaningful, non-blocking oracle integration.

### Tasks

| # | Task | Notes |
|---|---|---|
| 7.1 | Feed adapter with `try/catch`, staleness check, zero/negative handling | `docs/10-CHAINLINK.md` |
| 7.2 | `updateRiskState(poolId)` — computes drawdown vs. HWM, escalates to `Restricted` / `Breached` | Never gates a depositor exit |
| 7.3 | Hook reads the risk state and freezes **risk-increasing curator actions only** in `Restricted`/`Breached` | Reverts `RiskStateRestricted`; exits and depositor actions unaffected |
| 7.4 | Chainlink Automation task for periodic settlement + risk update | `SkylineKeeper`, `IAutomationCompatible`; both functions stay permissionless |
| 7.5 | `test/Oracle.t.sol` — fuzz the oracle returning 0, stale, extreme, reverting | Assert INV-5 |

### Acceptance criteria

- [ ] **Fuzzed** oracle failures never block a depositor exit — INV-5 green
- [ ] The hook never reverts because of an oracle read
- [ ] Degradation is always toward the more restrictive state

---

## Phase 8 — Dashboard (2 days)

See `docs/09-FRONTEND.md`. Minimum viable: one page, four panels, live reads.

### Acceptance criteria

- [ ] The CEP badge (`verifyCep`) renders live
- [ ] The claim queue and the curator's exit state are visible in real time
- [ ] The dashboard shows the curator's bond balance **derived from pool state**, with a link to the verification transaction

---

## Phase 9 — Deploy, demo, documentation (1 day)

### Tasks

| # | Task | Notes |
|---|---|---|
| 9.1 | Deploy to Base Sepolia (or Unichain Sepolia). Deploy the hook, vault, registry, pool. | Record addresses |
| 9.2 | Seed the demo scenario: curator bond, two depositors, degradation, an open claim | `docs/11-DEMO.md` §2 |
| 9.3 | Record a 90-second demo clip | Needed by 30 Nov |
| 9.4 | Rehearse the run-of-show twice, timed | `docs/11-DEMO.md` |
| 9.5 | Update `docs/02-SUBMISSION.md` with real addresses, repo links, and the shipped behaviour | |
| 9.6 | Write the repo README: what it is, how to run it, the invariant list, honest limitations | |
| 9.7 | Run `templates/READINESS_CHECKLIST.md` | |

---

## Critical path and cut order

```
Phase 0 ─► 1 ─► 2 ─► 3 ─► 4 ─► 5 ─► 6 ─► 7 ─► 8 ─► 9
   ▲                ▲        ▲
   └─ must work ────┘        └─ thesis gate
```

**If you are running out of time, cut in this order** (each cut is survivable; the reverse is not):

1. Phase 7 (Chainlink) — reduce to a single price-feed read, or drop and say so honestly
2. Phase 6 migration — already removed from the shipped surface
3. Phase 5 tick band — keep the fee cap only
4. Phase 8 dashboard — reduce to a static read-only view of pool state
5. Phase 4 loss absorption — **last resort**; the exit gate alone still tells the story

**Never cut:** Phase 2 (the claim ledger), the exit gate in Phase 4, Phase 9.1–9.3 (a live
deployment and a demo clip).

---

## Daily working protocol

1. Read `docs/15-PROGRESS.md` — where did the last session stop?
2. Pick the next unchecked task in the current phase.
3. Implement it.
4. Write the test **in the same commit** as the implementation.
5. Run `forge test && forge fmt --check`.
6. Update `docs/15-PROGRESS.md`: what was done, what is next, any blockers.
7. Commit with the message format in `docs/14-CONVENTIONS.md` §7.

**Never commit code that does not compile. Never commit a failing test.** A broken commit costs
more than an incomplete one, because the next agent will not know which state is real.

---

*Next: `docs/08-TESTING.md`.*
