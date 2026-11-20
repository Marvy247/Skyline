# Skyline — Curator Exit Parity for Uniswap v4

**UHI11 (11th Uniswap Hook Incubator) — primary submission**
*The Exit-Alignment Protocol for Curated Liquidity*

> **You manage the liquidity. You share the risk. You don't get to run first.**

---

## 0. Read this first (operating protocol for an AI agent)

This repository is a **specification, not an implementation**. It exists so that you — or any
AI agent picking this up cold — can build Skyline correctly, in order, without re-deriving
the research and without making the architectural mistakes this project is designed to avoid.

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
- [ ] Deployed on a public testnet (Base Sepolia or Unichain Sepolia) with a live pool
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
| **Contracts** | Implemented and tested — **61 tests, all green** (40 core + 21 Chainlink/keeper), plus 7 invariants (`contracts/`) |
| **Dashboard** | Complete — typechecks, builds warning-free, ABI aligned (`dashboard/`) |
| **Deployment** | Full stack deployed and exercised on local anvil; Base Sepolia config ready, public deploy pending RPC + funded key |
| **Chainlink** | Price-feed risk regime, Automation-compatible keeper, and 21 tests — implemented and tested; live Base Sepolia feed wiring is configured but not yet exercised |

**Read `docs/16-IMPLEMENTATION-NOTES.md` before changing the design.** It records the eight
places the implementation diverged from this specification and why — including three Uniswap v4
mechanics the spec got wrong.

## 2. Quick start (implementer)

```bash
# 1. The dashboard (already built)
cd dashboard && npm install && npm run dev

# 2. The contracts — already built and tested
cd ../contracts
forge build
forge test                                              # 61 tests, all green
FOUNDRY_PROFILE=ci forge test --match-path "test/invariant/Cep.t.sol"   # 10,000 runs
```

The deploy path is proven locally:

```bash
anvil --port 8545 &
FOUNDRY_PROFILE=deploy forge script script/Deploy.s.sol:DeploySkyline \
  --rpc-url http://127.0.0.1:8545 --broadcast \
  --private-key <anvil key>          # writes deployments/<chainid>.json
```

`FOUNDRY_PROFILE=deploy` is required: at the 1,000,000-run default the vendored `PoolManager`
compiles to 26,947 bytes and exceeds the EIP-170 limit (see `docs/16` §14.3).

The remaining work is **Phase 9**: deploy to a public testnet, seed the scenario, record the
90-second clip. See `docs/15-PROGRESS.md` §3 for the per-phase checklist and §5 for the open
issues.

A fresh clone needs the vendored dependencies restored (they are not committed):

```bash
cd contracts
forge install foundry-rs/forge-std@v1.17.0
forge install OpenZeppelin/openzeppelin-contracts@v5.1.0
forge install Uniswap/v4-core@v4.0.0
forge install Uniswap/v4-hooks-public@e354058
```

The pinned dependencies are `v4-core@v4.0.0` and `v4-hooks-public@e354058`; the hook base is
hand-written against the released core because the published `uniswap-hooks` package targets a
newer one and will not compile against it (`docs/16-IMPLEMENTATION-NOTES.md` §7).
