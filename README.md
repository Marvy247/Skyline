# Skyline — Curator Exit Parity for Uniswap v4

**UHI11 (11th Uniswap Hook Incubator) — primary submission**
*The Exit-Alignment Protocol for Curated Liquidity*

> **You manage the liquidity. You share the risk. You don't get to run first.**

---

## 0. Read this first (operating protocol for an AI agent)

This repository contains **both the specification and a working implementation**. The docs exist
so that you — or any AI agent picking it up cold — can understand Skyline correctly, in order,
without re-deriving the research and without repeating the architectural mistakes this project is
designed to avoid.

### 0.1 Order of operations

1. Read `docs/01-PROJECT-BRIEF.md` — what we are building and why.
2. Read `docs/03-ARCHITECTURE.md` — how it is put together.
3. Read `docs/05-SECURITY.md` — the invariants you may **never** break.
4. Read `docs/07-BUILD-ORDER.md` — the task list, in dependency order.
5. Work it. Update `docs/15-PROGRESS.md` as you go.
6. Before Demo Day, run `templates/READINESS_CHECKLIST.md` top to bottom.

### 0.2 Non-negotiable rules

These are hard constraints derived from verified Uniswap v4 mechanics. Violating any of them
breaks the core thesis or opens a fund-loss bug.

| # | Rule | Why |
|---|---|---|
| R1 | **Curator liquidity and depositor liquidity live in two separate v4 positions**, distinguished by `salt`. Never merge them. | The exit waterfall is impossible to execute or audit if the two are one position. |
| R2 | **The hook's obligation ledger is authoritative.** The vault is *never* asked "are there outstanding claims?" — the hook answers from its own state. | If the hook trusts the vault, the hook is decorative and the project has no thesis. |
| R3 | **The obligation ledger is keyed by `PoolId` and denominated in liquidity, not claim count.** | Cross-pool lockout (claims in pool A blocking exits in pool B) and partial settlement both become bugs otherwise. |
| R4 | **The oracle is never on the depositor exit path.** Chainlink may inform *risk parameters only*. | A stale/frozen feed must never be able to block a depositor from exiting. |
| R5 | **`hookData` is untrusted input.** It may correlate a call; it may never authorise one. | The curator controls the `hookData` it passes. |
| R6 | **Curator exit requires BOTH vault approval AND an empty hook ledger.** Approval alone is not sufficient. | The hook ledger is the binding constraint. |
| R7 | **Depositor withdrawals can never be blocked or deadlocked.** A pro-rata last-resort path must always exist. | Deadlock is a total-loss-of-access bug and the fastest way to lose the demo. |
| R8 | **No `PoolManager.get*` calls.** All pool reads go through `StateLibrary` (`extsload`). | `PoolManager` exposes no public getters in current v4-core; `poolManager.getSlot0()` does not compile. |
| R9 | **Pin `v4-core` and assert the position-keying model in a Foundry test** before building anything on top of it. | The whole attribution model depends on `positionKey = keccak256(owner, tickLower, tickUpper, salt)`. |
| R10 | **Claims expire.** Registered-but-unsettled claims time out and restore depositor shares. | Otherwise a depositor can grief-lock the curator indefinitely (symmetric attack). |

### 0.3 Definition of done

- [ ] All Phase 0–9 tasks in `docs/07-BUILD-ORDER.md` marked complete in `docs/15-PROGRESS.md`
- [ ] All six headline invariants in `docs/05-SECURITY.md` §4 green, including under fuzz
- [ ] `forge test` passes; `forge fmt --check` clean; no compiler warnings
- [x] Deployed on a public testnet (Base Sepolia) with a live pool
- [ ] Dashboard renders real on-chain state and the demo scenario is reproducible end-to-end
- [ ] `docs/11-DEMO.md` run-of-show rehearsed twice, timed
- [ ] Submission text in `docs/02-SUBMISSION.md` reflects the *shipped* implementation

### 0.4 Repository map

| File | Purpose |
|---|---|
| `docs/01-PROJECT-BRIEF.md` | Problem, insight, mechanism, differentiation, scope, non-goals |
| `docs/02-SUBMISSION.md` | The UHI11 submission text (Nov 16) — keep in sync with the build |
| `docs/03-ARCHITECTURE.md` | Contract inventory, state layout, flows, state machines, trust model |
| `docs/04-ECONOMICS.md` | CEP formalisation, exit ladder, loss absorption, fees, worked example |
| `docs/05-SECURITY.md` | Threat model, the six invariants, full attack-surface analysis |
| `docs/06-API.md` | Exact interface specs, storage layouts, errors, events |
| `docs/07-BUILD-ORDER.md` | **Phase-by-phase task list with acceptance criteria** |
| `docs/08-TESTING.md` | Test matrix, invariant handler sketch, fuzz targets, fork tests |
| `docs/09-FRONTEND.md` | **Dashboard specification — what the template became** |
| `docs/10-CHAINLINK.md` | Oracle/Automation integration spec and degradation behaviour |
| `docs/11-DEMO.md` | Demo Day run-of-show, scenario, Q&A prep, contingency plan |
| `docs/12-VERIFICATION.md` | Research dossier — every citation, competitor comparison, originality evidence |
| `docs/13-RISKS.md` | Risk register with triggers and mitigations |
| `docs/14-CONVENTIONS.md` | Solidity/Foundry/deploy conventions, dependency pinning |
| `docs/15-PROGRESS.md` | Living status log + handover notes |
| `docs/16-IMPLEMENTATION-NOTES.md` | **Every place the code diverged from the spec, and why** |
| `templates/` | Contract, hook, test, invariant, spec and readiness templates |
| `contracts/` | Foundry implementation — `bootstrap.sh` installs the pinned dependencies |
| `dashboard/` | **The Next.js dashboard** — see `docs/09-FRONTEND.md` |

---

## 1b. The dashboard (already built)

The frontend lives in `dashboard/` and is **complete**: Next.js 15 + wagmi v2 + viem v2 +
TanStack Query, six tabs, live pool reads, decoded reverts, and a demo-fixture mode.

```bash
cd dashboard
npm install
cp .env.example .env.local     # optional — without it the dashboard runs in demo mode
npm run dev                     # http://localhost:3000  ·  /dashboard
```

**Demo mode** needs no configuration and no network: `?scenario=blocked` reproduces the
worked example from `docs/04-ECONOMICS.md` §5. That is the Demo Day contingency.

Key files: `dashboard/lib/contracts.ts` (addresses, ABIs, PoolId derivation) ·
`dashboard/hooks/use-mandate.ts` (one batched multicall) ·
`dashboard/components/dashboard/exit-gate-panel.tsx` (the demo centrepiece).

Verified: `tsc --noEmit` clean · `next build` clean with no warnings · both routes return 200.

---

## 1. Thirty-second summary

Curated liquidity vaults let a manager run a strategy with other people's money. The manager
holds an informational advantage. When the strategy degrades, informed depositors leave
first, and the manager — who knew it was degrading — is perfectly positioned to leave ahead
of them, degrading the price for everyone still inside.

Every existing curated-liquidity implementation treats withdrawal as a **symmetric ERC-4626
redeem**. That symmetry is the bug.

**Skyline** makes curator capital **junior** to depositor capital by construction:

- Curator capital is bonded into the pool as a **separate v4 position** (`CURATOR_SALT`).
- Depositors exit via **recorded claims**, queued FIFO.
- A **Uniswap v4 hook maintains its own independent ledger** of outstanding obligations and
  **rejects any removal of curator-bonded liquidity while those obligations are unsettled** —
  at the PoolManager level, so no code path can route around it.
- When depositor liquidity cannot cover claims at fair value, the **curator's bond absorbs the
  shortfall**, and the curator's exit proceeds are netted against it.
- A **mandate** of committed parameters (fee cap, tick band, minimum skin, drawdown limits) is
  enforced by the same hook.

The curator cannot extract their aligned capital ahead of outstanding depositor obligations.
Not by policy. Not by reputation. By construction.

---

## 1c. Status

| Component | State |
|---|---|
| **Contracts** | Implemented and tested — **61 tests, all green** (33 core unit + 21 Chainlink/keeper + 7 invariants) (`contracts/`) |
| **Dashboard** | Complete — typechecks, builds warning-free, ABI aligned (`dashboard/`) |
| **Deployment** | **Live on Base Sepolia (84532)** — canonical v4 PoolManager, real USDC/WETH, live Chainlink ETH/USD feed; addresses below |
| **Chainlink** | Price-feed risk regime and Automation-compatible keeper deployed on Base Sepolia; feed wiring and `performUpkeep` exercised on-chain |

### 1d. Live deployment — Base Sepolia (84532)

| Contract | Address |
|---|---|
| PoolManager (canonical v4) | `0x05E73354cFDd6745C338b50BcFDfA3Aa6fA03408` |
| SkylineHook | `0xBcf550c214Fe3Ea4e61813241Aab2B113E434F80` |
| SkylineVault | `0x51d200C87e05a4c3E13460E6F0D46977be2622C9` |
| SkylineKeeper | `0x708C227792F969d62206E4d76603Aa1d1b9C5796` |
| PoolId | `0x7f355bcf7712d42494a0e9f860370f40f328bddfa465cccb630ddcc03a174b5b` |
| USDC (currency0) | `0x036CbD53842c5426634e7929541eC2318f3dCF7e` |
| WETH (currency1) | `0x4200000000000000000000000000000000000006` |
| Chainlink ETH/USD | `0x4aDC67696bA383F43DD60A9e78F2C97Fbbfc7cb1` |

The pool is a real USDC/WETH v4 pool (fee `3000`, tick spacing `60`) with the position range
`196020..208080`. The vault is seeded with a curator bond and two depositors, and
`riskState`/`effectiveRiskState` are `Normal`. The full artifact, including deployer, curator and
seed flag, is `contracts/deployments/84532.json`.

**Read `docs/16-IMPLEMENTATION-NOTES.md` before changing the design.** It records the eight
places the implementation diverged from this specification and why — including three Uniswap v4
mechanics the spec got wrong.

## 2. Quick start (implementer)

```bash
# 1. The dashboard (already built)
cd dashboard && npm install && npm run dev

# 2. The contracts
cd ../contracts
./bootstrap.sh                                        # installs the pinned dependencies
forge build
forge test                                              # 61 tests, all green
FOUNDRY_PROFILE=ci forge test --match-path "test/invariant/Cep.t.sol"   # 10,000 runs
```

The deploy path is proven locally and live on Base Sepolia:

```bash
anvil --port 8545 &
FOUNDRY_PROFILE=deploy forge script script/Deploy.s.sol:DeploySkyline \
  --rpc-url http://127.0.0.1:8545 --broadcast \
  --private-key <anvil key>          # writes deployments/<chainid>.json
```

`FOUNDRY_PROFILE=deploy` is required: at the 1,000,000-run default the vendored `PoolManager`
compiles to 26,947 bytes and exceeds the EIP-170 limit (see `docs/16` §14.3).

Read any deployment back with:

```bash
VAULT=0x51d200C87e05a4c3E13460E6F0D46977be2622C9 \
HOOK=0xBcf550c214Fe3Ea4e61813241Aab2B113E434F80 \
MANAGER=0x05E73354cFDd6745C338b50BcFDfA3Aa6fA03408 \
POOL_ID=0x7f355bcf7712d42494a0e9f860370f40f328bddfa465cccb630ddcc03a174b5b \
FOUNDRY_PROFILE=deploy forge script script/Inspect.s.sol:Inspect --rpc-url "$BASE_SEPOLIA_RPC_URL"
```

The remaining work is **Phase 9**: record the 90-second clip and fill the team field. See
`docs/15-PROGRESS.md` §3 for the per-phase checklist and §5 for the open issues.

`contracts/lib` is not committed. A fresh clone installs the exact dependency set with:

```bash
cd contracts
./bootstrap.sh          # pinned forge-std, OpenZeppelin, v4-core and solmate
```

The script pins `forge-std@v1.17.0`, `OpenZeppelin@v5.1.0`, `v4-core@v4.0.0` and the solmate
commit that v4-core pins. The hook base is hand-written against the released core; the published
`uniswap-hooks` package targets a newer core and is not used (`docs/16-IMPLEMENTATION-NOTES.md`
§7). This has been verified end to end from a fresh `git clone`: bootstrap, build, and all 61
tests pass.
