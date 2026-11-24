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
| **Phase** | Phase 10 — final deployment live on Base Sepolia; demo clip and submission fields in progress |
| **Last updated** | 24 November 2026 |
| **Idea submission deadline** | 16 November 2026 — **passed; submission status unconfirmed** |
| **Final submission deadline** | 3 December 2026 |
| **Demo Day** | 11 December 2026 |
| **Contracts** | **implemented and tested** — 67 tests green (39 core unit + 21 Chainlink/keeper + 7 invariants); fresh-clone bootstrap verified |
| **Dashboard** | **complete** — typechecks, builds warning-free, ABI aligned; live Base Sepolia reads verified against the deployment |
| **Deployment** | **Base Sepolia (84532) runs the final build** — hook `0x2B26…0f80`, vault `0xDF5C…759F`; seeded and verified (§13) |
| **Blocking issues** | UHI11 sponsor list unverified; demo clip not recorded |

---

## 2. What is built

### 2.1 Contracts (`contracts/`)

| File | Role |
|---|---|
| `src/SkylineHook.sol` | **The enforcement point.** Authoritative obligation ledger, shadow liquidity ledgers, the curator exit gate, the mandate (fee cap, tick band, minimum skin), the risk state. |
| `src/SkylineBaseHook.sol` | A hand-written `IHooks` base against `v4-core@v4.0.0` (see `docs/16` §7). |
| `src/SkylineVault.sol` | ERC-4626-style depositor accounting, the claim queue, the three-stage exit ladder, the curator bond, the performance fee. |
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
| `unit/ExitLadder.t.sol` | 8 | **The demo script.** Depositor-first settlement, market-loss semantics, the worked example, liveness |
| `unit/ClaimAccounting.t.sol` | 4 | Share reservation, full settlement with burns, expiry, permissionless cancel |
| `unit/Counterfactual.t.sol` | 2 | With-CEP vs without-CEP ordering — the load-bearing proof |
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
| Vault enforcement | `curatorDeposit` reverts `RiskStateRestricted`; `accruePerformanceFee` forfeits the fee and emits `PerformanceFeeForfeited` when `Breached`. |
| `SkylineKeeper` | `IAutomationCompatible`. Reports work when the evaluation is stale or claims are outstanding; ignores `performData`; refreshes risk and settles claims best-effort. |

**Verified:** `forge test` → **67 passed, 0 failed**. `forge build` clean. All 21 Chainlink tests
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

### Phase 4 — curator exit + last-resort drawdown — **DONE**
- [x] 4.1 `requestCuratorExit`
- [x] 4.2 depositor liquidity first, then the defensive last-resort branch
- [x] 4.3 `uncoveredShortfall` (denominated in the asset — see `docs/16` §3)
- [x] 4.4 exit proceeds = the live value of the remaining bond (no double netting)
- [x] 4.5 `test/ExitLadder.t.sol` — **the demo's script**
- [x] 4.6 `test/invariant/Cep.t.sol` — INV-6

### Phase 5 — mandate enforcement — **DONE**
- [x] 5.1 fee cap
- [x] 5.2 tick band
- [x] 5.3 minimum skin
- [x] 5.4 ~~`performRebalance`~~ — **removed from the shipped surface**; the mandate fixes the pool and range
- [ ] 5.5 `setMandate` tightening rules (not implemented; mandates are fixed at registration)
- [ ] 5.6 `test/Mandate.t.sol` (the constraints are enforced but not individually tested)

### Phase 6 — fee, forfeiture, registry — **PARTIAL**
- [x] 6.1 HWM performance fee
- [x] 6.2 `accruePerformanceFee`
- [x] 6.3 forfeiture on a detected drawdown breach — `accruePerformanceFee` detects `Breached`, forfeits, emits `PerformanceFeeForfeited`
- [x] 6.4 ~~`migrate`~~ — **removed from the shipped surface**; cross-vault migration is out of scope
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
- [x] 9.2 public testnet deployment — Base Sepolia 84532, addresses in §10
- [ ] 9.3 seed the demo scenario on the public chain — live vault is seeded with a curator bond and two depositors; the blocking claim is created live during the demo
- [ ] 9.4 record the 90-second clip
- [ ] 9.5 rehearse the run-of-show twice, timed
- [x] 9.6 update `docs/02-SUBMISSION.md` with real addresses
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
| 11 Nov | Shortfalls are denominated in the **asset**, not liquidity units | A liquidity-unit shortfall is impossible by construction; the real difference is a value loss. *(Bond semantics revised 23 Nov — see §12: the bond is exit-priority collateral, not market-loss insurance.)* |
| 11 Nov | The oracle is never on the depositor exit path | A stale feed must never trap depositor capital |
| 11 Nov | Pro-rata last resort guarantees liveness | A depositor must never be locked out |
| 11 Nov | Hook base written by hand against `v4-core@v4.0.0` | The published `uniswap-hooks` package targets a newer core and will not compile against the released one |
| 11 Nov | Deposits swap half their capital into the pool's other currency | A position straddling the price needs both currencies; a single-asset vault cannot fund it otherwise |
| 11 Nov | The pool must be bootstrapped with third-party liquidity | A fresh pool crashes on the first swap |
| 20 Nov | `Restricted`/`Breached` freeze **risk-increasing** curator actions only | Freezing the curator's exit would trap their own capital — a punishment, not a risk control. Exits remain subject to the CEP gate. |
| 20 Nov | Breach requires **two consecutive** extreme observations | A single manipulated or fat-fingered print must not forfeit fees |
| 20 Nov | The drawdown mark is the Chainlink price, against its own high-water mark | Keeps the risk input external; the vault's NAV must not be both the thing constrained and the input |
| 20 Nov | A stale or never-run evaluation is `Restricted` for the curator | A keeper outage must degrade toward restriction, never toward permissiveness |
| 23 Nov | The bond is **exit-priority collateral, not market-loss insurance** | A market move between claim registration and settlement is borne by the shares that bore the risk. Slashing the curator for the pool moving is punishment, not risk control. |
| 23 Nov | `uncoveredShortfall` is a historical counter, not a live deduction | It records bond value already delivered in the last-resort branch. Netting it again at the curator's exit would charge the same value twice. |
| 23 Nov | `CuratorExited` emits only `(curator, proceeds)` | The `shortfallNetted` field could only ever be zero on the shipped paths; keeping it implied a mechanism the contract does not have. |

---

## 5. Open issues

| # | Issue | Blocks | Action |
|---|---|---|---|
| 1 | UHI11's live sponsor list is unverified | Which sponsor prize we target | **Ask in the Discord today** |
| 2 | The Nov 16 idea-submission portal is not located | Submitting on time | Get the real form from the announcement |
| 3 | Demo clip is not recorded | The final submission | Record the 90-second scenario in `docs/11-DEMO.md` |
| 4 | Keeper is deployed but not registered with Chainlink Automation | The "wired to Chainlink" claim | Register `SkylineKeeper` on Base Sepolia, or present it as an `IAutomationCompatible` keeper with a permissionless fallback |
| 5 | No automated fork test against a live PoolManager | The strongest remaining proof | A manual end-to-end rehearsal against a live fork of the canonical PoolManager passed (§13.1); optionally promote it to `test/fork/BaseSepolia.t.sol` |
| 6 | `accruePerformanceFee` has no focused unit test | Confidence in Phase 6 | Write a focused fee/forfeiture test |

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
  *risk-increasing* actions (`curatorDeposit`, adds). This also resolves the
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
`DEPLOYER_PRIVATE_KEY`), the demo clip, and the team/video/address fields in
`docs/02-SUBMISSION.md`. The dashboard has had a visual pass.

---

## 9. Handover notes — session of 21 November 2026

**Completed:** the rename from MANDATE to Skyline, a clean public history (30 narrative commits
plus the dependency-bootstrap follow-up), and end-to-end verification from a fresh clone.

**What changed and why:**

- Every contract, interface, test, script, dashboard component and documentation reference now
  uses the Skyline name. The noun *mandate* remains deliberately: it is the protocol's
  committed-parameter object (`SkylineTypes.Mandate`, `MandatePanel`, `use-mandate.ts`).
- The salt preimages are now `keccak256("SKYLINE.LP_SALT.v1")` and
  `keccak256("SKYLINE.CURATOR_SALT.v1")`. This changes position keys, so any pre-rename local
  deployment must be redeployed; `deployments/31337.json` is the post-rename artifact.
- `contracts/lib` remains uncommitted. `contracts/bootstrap.sh` installs the exact pinned set
  (`forge-std@v1.17.0`, `OpenZeppelin@v5.1.0`, `v4-core@v4.0.0`, the solmate commit v4-core
  pins). The `solmate/` remapping now points at the top-level install, not v4-core's nested copy.
- The public repo is **https://github.com/Marvy247/Skyline**. `main` carries the 30-commit
  narrative plus one follow-up bootstrap commit; the older `master` branch remains a local-only
  safety snapshot.
- `dashboard/public/og-image.svg`, `site.webmanifest` and the logo accessibility label were
  rebranded; the landing page, overview and mandate tab were checked in headless Chrome.

**Verified:** fresh `git clone` → `contracts/bootstrap.sh` → `forge build` → `forge test` gives
**61 passed, 0 failed**, and `forge fmt --check` is clean. A local post-rename deploy produced
hook `0x95A77536A5229112397780D980C59ce6962D4f80`, vault
`0x5FC8d32690cc91D4c39d9d3abcBD16989F875707`, NAV `0.994607926246102359`, risk `Normal`.

**What is left:** unchanged from §8 — public Base Sepolia deployment, demo clip, submission
fields. No Base Sepolia RPC URL or funded deployer key is available in the environment.

---

## 10. Handover notes — session of 22 November 2026

**Completed:** the live Base Sepolia deployment, the dashboard's live configuration (and two
client-side decoding bugs found by pointing it at the deployment), and two deploy-script fixes
found by running the real deployment. The full demo path was rehearsed on a Base Sepolia fork.

### 10.1 Live deployment — Base Sepolia (84532) — **historical, superseded by §13**

> This deployment runs the pre-fix bytecode and its assets were consumed. It is kept here as a
> record; do not use these addresses.

| Item | Value |
|---|---|
| PoolManager (canonical v4) | `0x05E73354cFDd6745C338b50BcFDfA3Aa6fA03408` |
| SkylineHook | `0xBcf550c214Fe3Ea4e61813241Aab2B113E434F80` |
| SkylineVault | `0x51d200C87e05a4c3E13460E6F0D46977be2622C9` |
| SkylineKeeper | `0x708C227792F969d62206E4d76603Aa1d1b9C5796` |
| PoolId | `0x7f355bcf7712d42494a0e9f860370f40f328bddfa465cccb630ddcc03a174b5b` |
| USDC (currency0) | `0x036CbD53842c5426634e7929541eC2318f3dCF7e` |
| WETH (currency1) | `0x4200000000000000000000000000000000000006` |
| Chainlink ETH/USD | `0x4aDC67696bA383F43DD60A9e78F2C97Fbbfc7cb1` |
| Deployer / curator / fee recipient | `0x27A2dD1823D883935c9824fbaC0a018cE8e891E5` |
| Fee / tick spacing / range | `3000` / `60` / `196020..208080` |

At the first live read: tick `201802`, pool liquidity `4,992,250,939,073`, depositor liquidity
`182,896,908,595`, curator liquidity `46,354,030,478`, `totalAssets` `3,951,074` (6-decimal
USDC), `totalSupply` `4,030,216`, NAV `0.980362839113337845`, `pendingLiquidity` `0`, risk
`Normal`. The sub-1.0 NAV is the cost of the bootstrap swap and price impact during seeding, not
a loss bug; the demo uses the real numbers.

The Chainlink ETH/USD feed answered `171297000000` (8 decimals) with a current `updatedAt`.
Before the keeper ran, `effectiveRiskState` was `Restricted` because the stored evaluation was
older than `RISK_STATE_MAX_STALENESS`; calling `SkylineKeeper.performUpkeep(0x)` refreshed it and
returned both states to `Normal`. That is the intended degrade-toward-restriction behaviour, not
an outage.

### 10.2 Deploy-script fixes

- `SEED_CURATOR_BOND`, `SEED_DEPOSIT_A` and `SEED_DEPOSIT_B` are now read in **whole asset
  units** and multiplied by the asset's `10^decimals` once. Earlier runs applied no decimal
  scaling to these environment overrides, so `SEED_CURATOR_BOND=2` seeded 2 raw units rather
  than 2 USDC.
- `SALT_START` selects the first CREATE2 salt candidate. A redeploy against the same
  PoolManager no longer collides with an existing Skyline hook. The final deployment used
  `SALT_START=1000000`.

### 10.3 Dashboard live-mode fixes

Two bugs kept the dashboard in demo mode even with `.env.local` configured:

- `lib/contracts.ts` read variables through `process.env[name]`. Next.js only inlines
  `process.env.NEXT_PUBLIC_*` when the property is referenced statically, so the browser bundle
  saw an empty object and fell back to the fixture. Every variable is now read once, by name, in
  a static `ENV` object.
- viem returns **named** tuple components as objects, not arrays. `mandate`, `poolConfigs` and
  `claim` were being indexed as `m[0]`/`cfg[1]`/`c[6]`, so every field decoded as zero. They now
  read the named fields.

The live-mode dashboard was then rebuilt and checked in headless Chrome against the Base Sepolia
deployment: the context strip shows the real hook/vault/pool, the CEP badge reads `verifyCep`,
NAV/share renders `0.9803`, the mandate tab shows the correct `0.300%` fee cap, 10% skin and 10%
drawdown limit, and all six tabs render without a wallet.

### 10.4 Live-path rehearsal on a Base Sepolia fork — historical

> This rehearsal ran against the pre-fix deployment. The final build's rehearsal is §13.1.

The whole demo path was executed against an anvil fork of Base Sepolia (chain id 84532,
`--auto-impersonate`), so the live deployment was not mutated:

| Step | Result |
|---|---|
| `requestWithdraw(500,000 shares)` | claim 0 registered; pending `22,690,688,424` liquidity units; `isCuratorExitBlocked` → `true` |
| `requestCuratorExit()` | reverted `CuratorExitBlocked(22690688424)` — the hook, not the vault, refused |
| `settleClaims(10)` | claim settled; pending → `0`; `isCuratorExitBlocked` → `false` |
| `requestCuratorExit()` | approved by the hook |
| `curatorExit(46,354,030,478)` | succeeded; curator liquidity → `0`; proceeds `998,040` (0.99804 USDC) |

This was the exact sequence for the 90-second clip on the pre-fix deployment. The final build's
sequence and values are in §13.1.

### 10.5 Deployment traps

- Two earlier attempts left abandoned vaults with idle USDC: `0xa1a89F00…82Ea2` and
  `0xF5650CE8…58a7b`. They are **not** part of the submission. Do not deposit into them or
  move funds from them; the share price is polluted and the vault has no idle-balance sweep.
- The final position range is deliberately wide. A narrow range was pushed out of range by the
  bootstrap swap, after which deposits added zero liquidity.
- `FOUNDRY_PROFILE=deploy` is required to keep the vendored PoolManager under EIP-170.
- `dashboard/.env.local` is gitignored. It points at the deployment above with
  `NEXT_PUBLIC_DEMO_MODE=false`; `dashboard/.env.example` documents every variable.

### 10.6 What is left

Record the 90-second clip (`docs/11-DEMO.md`) and fill the video link in
`docs/02-SUBMISSION.md`. The `Team` field is **Marvy247**. Optionally verify the contracts on
BaseScan (needs `BASESCAN_API_KEY`) or add a fork test. The UHI11 sponsor/prize breakdown is
still unconfirmed.

---

## 11. Accounting fix — session of 23 November 2026

A review of the claim queue found three defects in the share ledger. All are fixed in
`SkylineVault`, covered by `test/unit/ClaimAccounting.t.sol`, and green in the full suite.

| Defect | Consequence | Fix |
|---|---|---|
| `totalSupply` was never reduced when a claim settled | Phantom shares remained after every withdrawal, diluting the depositors who stayed | `_serve` burns the claim's shares proportionally as each settlement slice is paid |
| A partial pro-rata settlement restored **all** reserved shares on expiry | A depositor could be paid for part of a claim and then recover the shares behind the whole claim | Only the unburned residue is restored; paid-for shares stay burned |
| Only the depositor could cancel an expired claim | A depositor who walked away could pin the curator's bond indefinitely | `cancelClaim` is permissionless after the TTL; the shares still return to the depositor |

The bond-stage settlement now advances the claim ledger through `_serve` as well, rather than only
in the depositor stage. `ClaimAccounting.t.sol` reconciles `totalSupply` against liquid plus
reserved shares after every path.

`invariant_oracleNeverBlocksDepositors` was asserting `!blocked => pending == 0`. That is too
strong: the deliberate last-resort state has `pending > depositorLiquidity` and
`isCuratorExitBlocked == false`, because at that point the gate's remaining job is to bound the
vault's bond removal to the shortfall, not to pretend the claim can be served from depositor
liquidity. Curator approval still requires an empty ledger. The invariant now permits the state
only when the depositor's own position provably cannot serve the claim.

**Suite:** 65 tests, 0 failures; 7 invariants at 2,000 runs × 100,000 calls.

**Live deployment at that point:** Base Sepolia still ran the pre-fix bytecode. *(Superseded by
§13 — the final build was deployed on 24 November.)*

**Periphery removed:** `migrate` and `performRebalance` were removed from the shipped surface.
`migrate` burned shares against bond-inclusive assets while moving depositor-only assets, and its
target-vault transfer had no allowance path. `performRebalance` removed both positions but
re-added only the depositor position, required prior exit approval for the curator removal, and
left the curator's proceeds idle with a stale `curatorBondValue`. Neither was on the demo path.
The mandate now fixes the pool and range; the curator can add bonded liquidity, not migrate the
position. This is a smaller surface with a clearer security story, and the docs say so.

---

## 12. Bond semantics and redeploy prep — session of 23 November 2026

**The model is now honest, and the code matches it.** The bond is **exit-priority collateral**,
not market-loss insurance.

| Change | Why |
|---|---|
| Removed the close-time `uncoveredShortfall` charge | It reduced the bond but never paid the depositor. A counter is not a transfer. |
| Removed the exit-time netting in `curatorExit` | After the charge was removed, netting would charge the same value twice, and a market loss must not be charged at all. |
| `curatorExitProceeds()` returns `_assetsForLiquidity(curatorLiquidity)` | The live value of what remains, not "bond value − shortfall". |
| `CuratorExited(address,uint256)` — `shortfallNetted` removed | It could only ever be zero on the shipped paths. |
| `test_workedExample_marketLossStaysWithTheDepositor` | Replaces the old "bond absorbs the shortfall" test; asserts the bond is untouched and the loss stays with shares. |
| `Counterfactual.t.sol` rewritten | Proves the ordering difference: without CEP the bond is gone before the claim is registered; with CEP it is locked behind the claim while the depositor is paid. |

`uncoveredShortfall` remains as a **historical accountability counter** for bond value delivered
to depositors in the defensive last-resort branch (`pending > depositor liquidity`). Normal claim
maths keeps `Q <= D`, so that branch is not reachable by an ordinary withdraw; it is a bounded
safety net, not a promise that the bond pays market losses.

**Suite:** 67 tests, 0 failures; 7 invariants at 2,000 runs × 100,000 calls; `forge fmt --check`
clean; dashboard `tsc --noEmit` clean.

**Demo wallet:** `0xc96d811952e6f87EFd0ddEDa3b85fe30F768AB5A`, key in the gitignored
`contracts/.env` as `DEMO_DEPOSITOR_PRIVATE_KEY`, funded with 0.002 ETH for gas. Import it into
the recording browser; the deployer stays the curator.

**Redeploy funding:** the deployer holds ~0.94 USDC. Circle's faucet sends 20 USDC per request,
every 2 hours, per address/chain. Seed sizes for the arriving balance: 20 → 10/6/4, 40 →
20/12/8, 60+ → 30/18/12 (depositor A / depositor B / curator bond). The pool also needs WETH;
the deployer holds ~0.0078 WETH and the old deployment can return ~0.0022 more.

**Resolved 24 Nov:** the Circle faucet delivered 20 USDC; the final deployment is in §13. The old
deployment runs pre-fix bytecode and is drained; do not record against it.

---

## 13. Final deployment — session of 24 November 2026

**The repository's final build is live on Base Sepolia (84532).** The deploy used the real
deployer key and the exact seed geometry rehearsed on a fork; every predicted address matched.

| Item | Value |
|---|---|
| v4 PoolManager (canonical) | `0x05E73354cFDd6745C338b50BcFDfA3Aa6fA03408` |
| SkylineHook | `0x2B263944982CE27D9C90429C6ccf61B0c37c0f80` |
| SkylineVault | `0xDF5C0a4a4aC83D34EdB73DF3CF3Ca804a49B759F` |
| SkylineKeeper | `0x50932de3B04d26910D32ab10654acEecC0Ce5B07` |
| PoolId | `0x5ca84e8f59283a8d9dc4d23ead5f0528735d790f336a01df84bdc80262ceae38` |
| Deploy block | `62913856` |
| Curator / fee recipient | `0x27A2dD1823D883935c9824fbaC0a018cE8e891E5` |
| Demo depositor | `0xc96d811952e6f87EFd0ddEDa3b85fe30F768AB5A` |

Seed: bootstrap liquidity `8e12`, depositor A `5 USDC`, depositor B `3 USDC`, curator bond
`1 USDC`. The deploy left `1.762420` USDC and `0.001776259875219344` WETH with the deployer.

**Live state at deployment:** `totalAssets` `7,873,683`; `totalSupply` `8,066,599`; NAV
`0.976084592775716259`; demo depositor shares `5,000,000`; depositor liquidity
`364,160,580,020`; curator liquidity `46,536,901,550`; curator bond value `1,000,000`;
`pendingLiquidity` `0`; `isCuratorExitBlocked` `false`; `effectiveRiskState` `Normal`.

### 13.1 Full demo-path rehearsal on a Base Sepolia fork

Same deployer, same nonce (`109`), same salt and code, so the fork predicted the live addresses
exactly. The rehearsal ran the complete recording path and left the live seed untouched.

| Step | Result |
|---|---|
| Demo depositor `requestWithdraw(2,500,000)` | claim `#0`; pending `112,860,603,472`; blocked `true` |
| Curator `requestCuratorExit()` | revert `CuratorExitBlocked(112860603472)`, selector `0xb2f9ec04` |
| `settleClaims(10)` | paid `2,432,727` USDC; pending `0`; blocked `false` |
| Curator `requestCuratorExit()` | approved `true` |
| Fork-only `curatorExit(46,536,901,550)` | proceeds `1,002,902`; curator liquidity `0`; bond `0`; shortfall `0` |

The gap between `assetsOwed` `2,440,211` and `assetsPaid` `2,432,727` is market/execution loss
borne by the shares, not charged to the bond. That is the intended semantics.

**Verified:** `forge test` → **67 passed, 0 failed**; `forge fmt --check` clean; dashboard
`tsc --noEmit` clean; `npm run build` clean.

**Remaining:** record the 90-second clip, add the video link to `docs/02-SUBMISSION.md`, and
optionally verify on BaseScan (needs `BASESCAN_API_KEY`).

---

*Previous: `docs/14-CONVENTIONS.md` · Next: `docs/16-IMPLEMENTATION-NOTES.md` · Back to `README.md`*
