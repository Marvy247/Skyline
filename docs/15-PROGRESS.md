# 15 — Progress Log

> **Update this at the end of every working session.** It is the handover note.
>
> The next agent (human or AI) reads this file first. If it is not accurate, they will build on
> sand.
>
> **Read `docs/16-IMPLEMENTATION-NOTES.md` before changing the design.** It records every
> place the code diverged from the specification and why.

---

## 1. Status

| Field | Value |
|---|---|
| **Phase** | Phase 7 — Chainlink integration **DONE**; Phase 9 — deploy/demo/docs in progress |
| **Last updated** | 20 November 2026 |
| **Idea submission deadline** | 16 November 2026 — **passed; submission status unconfirmed** |
| **Final submission deadline** | 3 December 2026 |
| **Demo Day** | 11 December 2026 |
| **Contracts** | **implemented and tested** — 61 tests green, including 21 Chainlink/keeper tests and 7 invariants |
| **Dashboard** | **complete** — typechecks, builds warning-free, ABI aligned with the shipped contracts |
| **Deployment** | full stack **verified on local anvil** (deploy + claim + block + settle + exit); Base Sepolia config ready, public deploy pending RPC + funded key |
| **Blocking issues** | UHI11 sponsor list unverified; no live public deployment; demo clip not recorded |

---

## 2. What is built

### 2.1 Contracts (`contracts/`)

| File | Role |
|---|---|
| `src/SkylineHook.sol` | **The enforcement point.** Authoritative obligation ledger, shadow liquidity ledgers, the curator exit gate, the mandate (fee cap, tick band, minimum skin), the risk state. |
| `src/SkylineBaseHook.sol` | A hand-written `IHooks` base against `v4-core@v4.0.0` (see `docs/16` §7). |
| `src/SkylineVault.sol` | ERC-4626-style depositor accounting, the claim queue, the three-stage exit ladder, the curator bond, the performance fee, migration. |
| `src/SkylineKeeper.sol` | Chainlink Automation-compatible keeper (`IAutomationCompatible`) that refreshes the risk regime and serves claims. Optional by construction. |
| `src/libraries/SkylineTypes.sol` | Salts, the `Mandate`/`Claim`/`PoolConfig` structs, the settlement-tag encoding. |
| `src/libraries/LiquidityAmounts.sol` | The standard Uniswap amount↔liquidity conversions. |
| `src/interfaces/` | `ISkylineHook`, `ISkylineVault`, `IChainlinkFeed`, `IAutomationCompatible`. |
| `script/Deploy.s.sol` | Deploys the stack, **mines a CREATE2 salt** so the hook address carries the v4 permission bits, initialises the pool, registers it with the hook, wires the oracle and keeper. |
| `script/Inspect.s.sol` | Prints live pool, vault and risk-regime state for any deployment. |

### 2.2 Tests (`contracts/test/`)

| Suite | Count | Covers |
|---|---|---|
| `unit/Primitives.t.sol` | 8 | The v4 mechanics the design rests on: position keying, salt separation, owner-only modification, shadow-counter accuracy, deposit pricing |
| `unit/ClaimLedger.t.sol` | 17 | The ledger, the exit gate (both the approval refusal and the removal block), approval revocation, expiry, claim limits |
| `unit/ExitLadder.t.sol` | 8 | **The demo script.** Stage 1/2/3, the worked example, liveness |
| `Oracle.t.sol` | 21 | Chainlink risk regime: every feed failure mode, HWM ratchet, breach confirmation, keeper, fuzzed INV-5 |
| `invariant/Cep.t.sol` | 7 invariants | INV-1 … INV-6 plus shadow-counter and over-settlement checks. 2,000 runs × 100,000 calls, 0 reverts |
| `utils/SkylineFixture.sol` | — | Deploys PoolManager, tokens, hook (etched onto a permission-correct address), pool, vault; registers the pool; seeds the bootstrap position |

### 2.3 Dashboard (`dashboard/`)

Complete: six tabs, live pool reads through one batched multicall, custom-error decoding into
plain English, and a demo-fixture mode that needs no network. See `docs/09-FRONTEND.md`.

### 2.4 Deploy verification (20 November 2026)

The deploy script had never been executed. Running it found five defects, all now fixed and
recorded in `docs/16` §14. The full ladder was then exercised against a live anvil chain:

| Step | Result |
|---|---|
| Deploy + seed | 800,000 deposited, 200,000 bonded, NAV 0.9946 |
| `requestCuratorExit()` with no claims | approved |
| `requestWithdraw(50% of shares)` | 66,507,846,997,809,853,769,525,799 liquidity units recorded, approval revoked |
| `curatorExit(all)` | reverted `WrappedError(hook, beforeRemoveLiquidity, CuratorExitBlocked(pending), HookCallFailed)` |
| `settleClaims(10)` | paid the depositor, pending back to 0, claim `Settled` |
| re-request after cooldown, `curatorExit(all)` | succeeded, `curatorLiquidity` back to 0 |

The artifact is `contracts/deployments/31337.json`. `script/Inspect.s.sol` prints live pool and
vault state for any deployment.

### 2.5 Chainlink risk regime (20 November 2026)

| Component | Behaviour |
|---|---|
| `_readMark` | Rejects zero/negative answers, `updatedAt == 0`, stale data (> 1h), and incomplete rounds (`answeredInRound < roundId`); catches reverts. Never bubbles. |
| `updateRiskState` | Permissionless. High-water-mark reference price; failure-only escalation; `Breached` requires `BREACH_CONFIRMATIONS = 2` consecutive observations at ≥ 2× the drawdown limit. |
| `effectiveRiskState` | Applies staleness: an oracle-configured pool that has never been evaluated, or whose evaluation is older than 1 hour, is `Restricted` for curator actions. Never read on a depositor path. |
| Hook enforcement | `beforeAddLiquidity` rejects curator-salt additions when `effectiveRiskState >= Restricted`. Risk-reducing exits are unaffected. |
| Vault enforcement | `curatorDeposit` and `performRebalance` revert `RiskStateRestricted`; `accruePerformanceFee` forfeits the fee and emits `PerformanceFeeForfeited` when `Breached`. |
| `SkylineKeeper` | `IAutomationCompatible`. Reports work when the evaluation is stale or claims are outstanding; ignores `performData`; refreshes risk and settles claims best-effort. |

**Verified:** `forge test` → **61 passed, 0 failed**. `forge build` clean. All 21 Chainlink tests
pass, including a 10,000-run fuzz asserting that a depositor can register and settle a claim
under every oracle failure mode.

---

## 3. Phase checklist

### Phase 0 — validate the primitives — **DONE**
- [x] 0.1 Foundry project + pinned deps (`v4-core@v4.0.0`, `v4-hooks-public`, OZ v5.1)
- [x] 0.2 Position keying confirmed
- [x] 0.3 `owner = msg.sender` confirmed
- [x] 0.4 `beforeRemoveLiquidity` signature confirmed
- [x] 0.5 `StateLibrary.getPositionInfo` confirmed
- [x] 0.6 Hook base written directly against `v4.0.0` (the published package does not match)
- [x] 0.7 `Hooks.Permissions` field list recorded
- [x] 0.8 Hook deployed at a permission-correct address (etch, in tests)
- [x] 0.9 `test_saltDistinguishesPositions`
- [x] 0.10 `test_onlyOwnerCanModifyPosition`

### Phase 1 — hook skeleton + shadow ledgers — **DONE**
- [x] 1.1–1.6 types, constructor, permissions, `registerPool`, shadow ledgers, dynamic fee + cap, verifier views
- [x] 1.7 `test/HookShadow.t.sol` → folded into `Primitives.t.sol`

### Phase 2 — the claim ledger *(the thesis)* — **DONE**
- [x] 2.1 `registerClaim`
- [x] 2.2 Settlement applied **inside `afterRemoveLiquidity`** (see `docs/16` §2)
- [x] 2.3 `expireClaim`
- [x] 2.4 `approveCuratorExit`
- [x] 2.5 the exit gate
- [x] 2.6 `test/ClaimLedger.t.sol` (17 tests)
- [x] 2.7 `test/invariant/Cep.t.sol` — **gate**

### Phase 3 — the vault — **DONE**
- [x] 3.1 ERC-4626 core
- [x] 3.2 `totalAssets()` excludes the curator bond
- [x] 3.3 `requestWithdraw`
- [x] 3.4 `settleClaims`
- [x] 3.5 `curatorDeposit` (bond + top-up)
- [x] 3.6 min-skin handling
- [x] 3.7 claim expiry → share restore
- [x] 3.8 `test/Vault.t.sol` → folded into `ClaimLedger.t.sol` / `ExitLadder.t.sol`

### Phase 4 — curator exit + loss absorption — **DONE**
- [x] 4.1 `requestCuratorExit`
- [x] 4.2 the three-stage ladder
- [x] 4.3 `uncoveredShortfall` (denominated in the asset — see `docs/16` §3)
- [x] 4.4 netted exit proceeds
- [x] 4.5 `test/ExitLadder.t.sol` — **the demo's script**
- [x] 4.6 `test/invariant/Cep.t.sol` — INV-6

### Phase 5 — mandate enforcement — **DONE**
- [x] 5.1 fee cap
- [x] 5.2 tick band
- [x] 5.3 minimum skin
- [x] 5.4 `performRebalance` — band-checked, risk-gated; exercised by `Oracle.t.sol`
- [ ] 5.5 `setMandate` tightening rules (not implemented; `setMandate` is owner-only, pre-liquidity)
- [ ] 5.6 `test/Mandate.t.sol` (the constraints are enforced but not individually tested)

### Phase 6 — fee, forfeiture, migration, registry — **PARTIAL**
- [x] 6.1 HWM performance fee
- [x] 6.2 `accruePerformanceFee`
- [x] 6.3 forfeiture on a detected drawdown breach — `accruePerformanceFee` detects `Breached`, forfeits, emits `PerformanceFeeForfeited`
- [x] 6.4 `migrate` (implemented, **not tested**)
- [ ] 6.5 `CuratorRegistry`
- [ ] 6.6 `test/Fee.t.sol`

### Phase 7 — Chainlink — **DONE**
- [x] 7.1 `IChainlinkFeed` adapter with `try/catch`, staleness and round-completeness checks
- [x] 7.2 `updateRiskState` — HWM reference, failure-only escalation, two-observation breach confirmation
- [x] 7.3 the hook freezes **risk-increasing** curator operations in `Restricted`/`Breached`; exits and depositor actions unaffected
- [x] 7.4 `SkylineKeeper` — `IAutomationCompatible`, permissionless refresh + settlement, untrusted `performData`
- [x] 7.5 `test/Oracle.t.sol` — 21 tests, including a 10,000-run fuzz of INV-5

### Phase 8 — dashboard — **DONE**
- [x] 8.1–8.7 all done
- [x] 8.8 ABI aligned with the shipped contracts

### Phase 9 — deploy, demo, docs — **IN PROGRESS**
- [x] 9.1 deploy script rewritten for Base Sepolia: canonical PoolManager, decimals-aware seeding, oracle wiring, keeper
- [ ] 9.2 public testnet deployment (needs `BASE_SEPOLIA_RPC_URL` + funded `DEPLOYER_PRIVATE_KEY`)
- [ ] 9.3 seed the demo scenario on the public chain
- [ ] 9.4 record the 90-second clip
- [ ] 9.5 rehearse the run-of-show twice, timed
- [ ] 9.6 update `docs/02-SUBMISSION.md` with real addresses
- [x] 9.7 repo README
- [ ] 9.8 readiness checklist

---

## 4. Decisions log

| Date | Decision | Why |
|---|---|---|
| 11 Nov | Theme confirmed as **"UHI11: Active Management and Curation"** | `atrium.academy/sponsors` |
| 11 Nov | Original Skyline (vault + constraint layer) **abandoned** | `vault-curator` (same cohort) covers that frame and never implements `beforeRemoveLiquidity` |
| 11 Nov | New centre of gravity: **Curator Exit Parity** | The exit path is unclaimed across all 759 submissions and the hookforge catalogue |
| 11 Nov | The hook owns the ledger; the vault is never asked | Otherwise the hook inherits the vault's trust assumptions |
| 11 Nov | Claims are liquidity-denominated, per-`PoolId` | Partial settlement is natural; cross-pool lockout is impossible |
| 11 Nov | Curator and depositor capital are **two positions** (`salt`) | Without separation the exit ladder cannot be executed or audited |
| 11 Nov | The ledger is decremented **inside `afterRemoveLiquidity`** | Strictly stronger: no decrement without real liquidity leaving |
| 11 Nov | Loss absorption is denominated in the **asset**, not liquidity units | A liquidity-unit shortfall is impossible by construction; the real loss is a value loss |
| 11 Nov | The oracle is never on the depositor exit path | A stale feed must never trap depositor capital |
| 11 Nov | Pro-rata last resort guarantees liveness | A depositor must never be locked out |
| 11 Nov | Hook base written by hand against `v4-core@v4.0.0` | The published `uniswap-hooks` package targets a newer core and will not compile against the released one |
| 11 Nov | Deposits swap half their capital into the pool's other currency | A position straddling the price needs both currencies; a single-asset vault cannot fund it otherwise |
| 11 Nov | The pool must be bootstrapped with third-party liquidity | A fresh pool crashes on the first swap |
| 20 Nov | `Restricted`/`Breached` freeze **risk-increasing** curator actions only | Freezing the curator's exit would trap their own capital — a punishment, not a risk control. Exits remain subject to the CEP gate. |
| 20 Nov | Breach requires **two consecutive** extreme observations | A single manipulated or fat-fingered print must not forfeit fees |
| 20 Nov | The drawdown mark is the Chainlink price, against its own high-water mark | Keeps the risk input external; the vault's NAV must not be both the thing constrained and the input |
| 20 Nov | A stale or never-run evaluation is `Restricted` for the curator | A keeper outage must degrade toward restriction, never toward permissiveness |

---

## 5. Open issues

| # | Issue | Blocks | Action |
|---|---|---|---|
| 1 | UHI11's live sponsor list is unverified | Which sponsor prize we target | **Ask in the Discord today** |
| 2 | The Nov 16 idea-submission portal is not located | Submitting on time | Get the real form from the announcement |
| 3 | No public testnet deployment | The live demo | Run `script/Deploy.s.sol` on Base Sepolia (needs RPC + funded key) |
| 4 | No live Automation registration | The "wired to Chainlink" claim | Register `SkylineKeeper` with Chainlink Automation on Base Sepolia, or present it as an `IAutomationCompatible` keeper and demonstrate the permissionless fallback |
| 5 | The dashboard has never been opened in a browser | Visual QA | `npm run dev` and look at it |
| 6 | No fork test against a live PoolManager | The strongest remaining proof | Write `test/fork/BaseSepolia.t.sol` |
| 7 | `performRebalance`, `migrate`, `accruePerformanceFee` have no focused unit tests | Confidence in Phase 5/6 | Write focused unit tests; `performRebalance` and fee forfeiture are exercised indirectly in `Oracle.t.sol` |

---

## 6. Session template

```markdown
## Session — <date>

**Phase:** <n> — <name>
**Completed:** <task ids>
**In progress:** <task id>
**Next:** <task id>

**Decisions:**
- <decision> — <why>

**Problems hit:**
- <problem> → <resolution>

**Files touched:**
- <path> — <what changed>

**Test results:**
- forge test → <n> passed, <n> failed
- forge build → <warnings>

**Pinned deps:**
- v4-core @ v4.0.0
- v4-hooks-public @ e354058
```

---

## 7. Handover notes — session of 11 November 2026

Built the entire protocol from the specification and got it green.

**What was verified rather than assumed.** Every Uniswap v4 fact the design depends on was read
out of the `v4-core@v4.0.0` source rather than from memory, and several assumptions turned out
to be wrong — the delta sign convention, the settlement order, the absence of `PoolManager`
getters, and the exact-input sign. These are recorded in `docs/16-IMPLEMENTATION-NOTES.md` §10.

**The three bugs that cost the most time**, all in the vault's liquidity mechanics, all now
fixed and covered by tests:

1. The vault deposited only one side of a two-sided position and the pool charged it for the
   other. Fixed by swapping half of every deposit into the pool's other currency.
2. The settlement sign convention was inverted, so the vault paid the pool for a withdrawal
   instead of taking from it.
3. `curatorLiquidity` was decremented twice on the curator's exit — once inside
   `_removeLiquidity` and once in `curatorExit` — which surfaced as a bare arithmetic
   underflow.

**The next thing to do.** Phase 9. Deploy to Base Sepolia, seed the scenario, record the clip.
Everything the demo needs is already built and tested; what is missing is a live deployment and
a wallet.

---

## 8. Handover notes — session of 20 November 2026

**Completed:** the Chainlink risk regime, the Automation-compatible keeper, the Base Sepolia
deploy path, and 21 tests. Full suite: **61 passed, 0 failed**.

**What changed and why:**

- `Restricted` no longer freezes the curator's **exit**. Freezing an exit traps the curator's
  own capital and is a punishment, not a risk control. The regime now freezes only
  *risk-increasing* actions (`curatorDeposit`, adds, `performRebalance`). This also resolves the
  contradiction between `docs/05-SECURITY.md` §6 and `docs/10-CHAINLINK.md` §3.
- The drawdown mark is the **Chainlink price against its own high-water mark**, not the vault's
  NAV. The NAV is an accounting output; using it as the risk input would let the curator move
  the regime by depositing or rebalancing.
- `Breached` requires **two consecutive** observations at ≥ 2× the limit. A single print
  escalates to `Restricted` and freezes curator increases, but cannot forfeit a fee.
- A stale or never-run evaluation is `Restricted` via `effectiveRiskState`. The keeper is an
  optimisation; its absence restricts the curator, never the depositor.
- `SkylineKeeper` implements `IAutomationCompatible` and ignores `performData`.

**Deploy path:** `script/Deploy.s.sol` now defaults to the canonical Base Sepolia PoolManager
(`0x05E73354cFDd6745C338b50BcFDfA3Aa6fA03408`), sizes the demo in token decimals, aligns the
range to the tick spacing, wires the oracle after seeding, deploys the keeper, and writes
`deployments/<chainId>.json`. Verified end-to-end on a fresh anvil (chain 31337): deploy + seed,
then `Inspect.s.sol` reports NAV `0.994607…`, risk `Normal`, `riskUpdatedAt 0` (oracle unset
locally).

**What is left:** a public Base Sepolia deployment (needs `BASE_SEPOLIA_RPC_URL` and a funded
`DEPLOYER_PRIVATE_KEY`), the demo clip, the six `TODO`s in `docs/02-SUBMISSION.md`, and a visual
pass of the dashboard.

---

*Previous: `docs/14-CONVENTIONS.md` · Next: `docs/16-IMPLEMENTATION-NOTES.md` · Back to `README.md`*
