# 14 — Conventions

> Consistency matters more than preference. When two people (or two agents) work on this repo,
> these rules keep the code reviewable and the invariants auditable.

---

## 1. Repository layout

```
ATRIUM/
├── README.md                  # operating protocol for agents
├── docs/                      # the specification (01 → 15)
├── templates/                 # copy-paste starting points
├── contracts/                 # Foundry project
│   ├── src/
│   │   ├── interfaces/
│   │   ├── libraries/
│   │   ├── SkylineHook.sol
│   │   ├── SkylineVault.sol
│   │   ├── CuratorRegistry.sol
│   │   └── SkylineFactory.sol
│   ├── test/
│   │   ├── unit/
│   │   ├── invariant/
│   │   └── fork/
│   ├── script/
│   └── foundry.toml
└── dashboard/                 # Next.js app (see docs/09-FRONTEND.md)
```

**Rule:** `docs/` is the source of truth for design. If the code and the docs disagree, one of
them is a bug — fix it in the same commit.

---

## 2. Dependencies (pin these)

```toml
# foundry.toml — remappings
[profile.default]
src = "src"
out = "out"
libs = ["lib"]
test = "test"
solc_version = "0.8.26"
evm_version = "cancun"
optimizer = true
optimizer_runs = 1000000
via_ir = false
fs_permissions = [{ access = "read", path = "./out"}]

remappings = [
  "forge-std/=lib/forge-std/src/",
  "v4-core/=lib/v4-core/src/",
  "v4-periphery/=lib/v4-periphery/src/",
  "uniswap-hooks/=lib/v4-hooks-public/src/",
  "openzeppelin-contracts/=lib/openzeppelin-contracts/contracts/",
]
```

| Dependency | Pin | Note |
|---|---|---|
| `v4-core` | the **`v4.0.0` tag** | `main` has diverged (getters moved to `StateLibrary`, new `ProtocolFees`, ERC-6909 claims). Do not build against `main`. |
| `v4-hooks-public` | a commit from Oct 2026 or later | `BaseHook` at `src/base/BaseHook.sol` |
| `v4-periphery` | matching `v4-core` | |
| `forge-std` | latest | |
| `openzeppelin-contracts` | v5.x | |

**After every `forge install`, record the resolved commit in `docs/15-PROGRESS.md`.** A floating
dependency is how a project silently breaks two weeks later.

### 2.1 Solidity

- `pragma solidity ^0.8.26;`
- `evm_version = "cancun"`
- SPDX header on every file
- NatSpec on every public/external function: `@notice`, `@param`, `@return`
- Custom errors over `require` strings
- `unchecked` only where overflow is impossible by construction, with a comment saying why

### 2.2 Naming

| Thing | Convention | Example |
|---|---|---|
| Contracts | `PascalCase` | `SkylineHook`, `SkylineVault` |
| Functions / variables | `camelCase` | `registerClaim`, `pendingLiquidity` |
| Constants / immutables | `SCREAMING_SNAKE` | `LP_SALT`, `CURATOR_SALT` |
| Errors | `PascalCase` (no prefix) | `CuratorExitBlocked` |
| Events | `PascalCase` (past tense) | `ClaimRegistered`, `CuratorExitBlocked` |
| Private fields | `_camelCase` | `_pendingLiquidity` |
| Test files | `<Subject>.t.sol` | `ClaimLedger.t.sol` |
| Invariant suites | `test/invariant/<Name>.t.sol` | `test/invariant/Cep.t.sol` |

### 2.3 NatSpec template

```solidity
/// @notice Registers a depositor withdrawal claim against the pool.
/// @dev Called by the registered vault only. Increments the hook's authoritative
///      obligation ledger, which is the sole input to the curator exit gate.
/// @param poolId The Uniswap v4 pool id.
/// @param claimId Monotonic, per-pool, never reused.
/// @param liquidityAmount Pool liquidity units owed to the depositor.
/// @param depositor The depositor the claim belongs to.
/// @return ok True when the claim was recorded.
function registerClaim(
    PoolId poolId,
    uint256 claimId,
    uint128 liquidityAmount,
    address depositor
) external onlyVault(poolId) returns (bool ok);
```

---

## 3. Security conventions

- **`onlyVault(poolId)`** — the hook never trusts a caller that is not the pool's registered vault.
- **`onlyCurator`** — separate from `onlyOwner`.
- **The hook's ledger is authoritative.** Never read obligations from the vault.
- **The hook never reverts because of an external call.** Wrap oracle reads in `try/catch`.
- **Never add a global pause.** It could violate R7 (no depositor lockout).
- **Custom errors carry the context needed to explain the revert.** `CuratorExitBlocked(int128)`.
- **Round against the protocol and against the curator.** Never in their favour.

---

## 4. Testing conventions

- One test file per contract or per subsystem.
- Unit tests: `test/unit/<Subject>.t.sol`. Invariants: `test/invariant/<Name>.t.sol`.
  Fork: `test/fork/<Chain>.t.sol`.
- **Every invariant in `docs/05-SECURITY.md` has a matching test.** Add both in the same commit.
- Fuzz runs: `10000` locally, `100000` in CI.
- Name tests after the property, not the function: `test_curatorBlockedWhileObligationOutstanding`
  beats `test_beforeRemoveLiquidity_2`.
- **A test that cannot fail is a comment. Delete it.**
- Every revert path has a test that asserts the *specific custom error*, not just "reverts".

---

## 5. Git conventions

**Branch:** `feat/<scope>` · `fix/<scope>` · `docs/<scope>`

**Commit format** (conventional commits):

```
<type>(<scope>): <summary>

<body>

Refs: docs/07-BUILD-ORDER.md#<task>
```

Types: `feat` · `fix` · `test` · `docs` · `refactor` · `chore` · `perf`

Examples:

```
feat(hook): add authoritative claim ledger with per-pool scoping

Registers claims from the vault only, denominated in pool liquidity units so
partial settlement is natural. Decrement is corroborated against the shadow
liquidity ledger.

Refs: docs/07-BUILD-ORDER.md#2.1
```

**Rules:**
- One logical change per commit.
- The implementation and its test are in the **same** commit. Never "fix tests" in a later commit.
- Never commit code that does not compile.
- Never commit a failing test. A broken commit costs more than an incomplete one, because the
  next agent cannot tell which state is real.

---

## 6. Environment and secrets

- `.env` is gitignored. `.env.example` is committed and documents every variable.
- Deployment keys live in the Foundry keystore, never in the repo.
- Deploy to a testnet only. Never mainnet before an external audit.

---

## 7. Dashboard conventions

- TypeScript `strict` is on. `npm run typecheck` must be clean.
- `target` is **ES2020** (viem returns `bigint`).
- Components are client components (`"use client"`) unless they are purely server-side.
- The multicall contract objects in `hooks/use-mandate.ts` are written **inline** — a helper that
  widens `functionName` to `string` breaks result inference.
- New Solidity errors must be added to `mandateErrorsAbi` in `lib/contracts.ts`.
- Never hard-code an address. Never trust a value from `lib/contracts.ts` for a financial
  decision.
- Demo mode must always work with no `.env` at all.

---

## 8. Documentation conventions

- Docs are numbered and read in order.
- Every design decision states **why**.
- Every claim about a third party links to a source.
- When the implementation diverges from a doc, update the doc in the same commit.
- `docs/15-PROGRESS.md` is updated at the end of every working session.

---

*Next: `docs/15-PROGRESS.md`.*
