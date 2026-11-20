# 05 — Security

> The invariants are the contract. If an implementation change breaks one of these, the change
> is wrong — change the design, not the invariant. Every invariant here has a matching Foundry
> test in `docs/08-TESTING.md` §4.

---

## 1. Adversaries and their capabilities

| Adversary | Can | Cannot |
|---|---|---|
| **A1 — Malicious curator** | Call the vault's curator functions at will; choose when to request an exit; propose rebalances within whatever the vault allows; observe everything on-chain | Modify pool state directly; remove liquidity from a position it does not own; call the hook's privileged functions |
| **A2 — Malicious depositor** | Register claims; time them; spam them | Remove liquidity directly; forge claims; lock claims forever (TTL + share burn) |
| **A3 — Compromised / buggy vault** | Misreport balances; call hook functions incorrectly | Forge a pool-level liquidity removal |
| **A4 — Compromised oracle** | Return a stale, extreme, or zero price | Block a depositor exit; unlock the curator |
| **A5 — Arbitrary third party** | Call any public function | Modify pool state without the hook; move vault funds |

**Out of scope:** a compromise of the hook contract itself, of the PoolManager, or of the
EVM. If the hook is broken, the protocol is broken — that is a deployment-quality problem, not
a mechanism problem.

---

## 2. Threat model boundary

The protocol guarantees **ordering and mandate**, not **fund safety against a malicious vault**.

Concretely: if the vault is hostile, it could attempt to steal depositor principal directly.
Skyline does not prevent that, and does not claim to. What Skyline guarantees is narrower and
still valuable:

> **Even if the vault misbehaves, curator-bonded liquidity cannot be removed ahead of
> outstanding depositor obligations, and the curator cannot exceed the mandate.**

This is the property the hook enforces, and it is the property the submission claims. Keep the
claim and the implementation exactly aligned.

---

## 3. Attack surface

| Surface | Controls | Notes |
|---|---|---|
| `hook.registerClaim` | `onlyVault(poolId)`, `onlyRegisteredPool`, claim not already registered | Nonce/`claimId` is monotonic per pool |
| `hook.settleClaim` | `onlyVault(poolId)`, claim status, `liquidityRemoved` bounds, shadow-ledger corroboration | The corroboration check is what makes it unforgeable |
| `hook.approveCuratorExit` | `onlyVault(poolId)`, `Q == 0` | Vault approval alone is insufficient (R6) |
| `hook.registerPool` | `!registered`, non-zero addresses, `msg.sender == vault` | One-shot per pool |
| `hook.beforeRemoveLiquidity` | Curator-salt gate, band check, min-skin projection | The core enforcement point |
| `hook.beforeSwap` | Fee cap | `fee <= mandate.maxFeeBps` |
| `vault.requestWithdraw` | Share balance, claim TTL, per-depositor limits | |
| `vault.settleClaims` | Permissionless, FIFO, bounded per call | Anyone may trigger — good for liveness, bad for nothing |
| `vault.requestCuratorExit` | Cooling-off, netting of `F` | |
| `vault.performRebalance` | Band, cooldown, min-skin | Every rebalance passes through the hook's checks |
| Oracle read | Only affects `riskState` | Never on the exit path (R4) |

---

## 4. The six headline invariants

These are the properties that define Skyline. Each must hold under fuzzing, in every state
reachable by the invariant handler.

### INV-1 — Claim registration is exclusive and unique

> Only the registered vault may register a claim for a pool. A `claimId` may be registered at
> most once. A pool may be registered exactly once.

```solidity
// assertions
assert(vault == poolConfig.vault ⇒ only it can create claims);
assert(claimId is monotonically increasing and never reused);
assert(poolConfig.registered ⇒ it was false before this call);
```

**Test:** `testFuzz_claimIdNeverReused`, `testFuzz_onlyVaultCanRegister`.

### INV-2 — The obligation ledger is authoritative and non-negative

> `pendingLiquidity[poolId]` equals the sum over all non-settled, non-expired claims of their
> unsettled remainder, and is never negative.

```solidity
assert(pendingLiquidity[poolId] >= 0);
assert(pendingLiquidity[poolId] == sumOfUnsettledClaimRemainders(poolId));
```

**Test:** `test_invariant_pendingMatchesClaims`, fuzz over arbitrary
register/settle/expire sequences.

### INV-3 — Curator exit parity (the thesis)

> For any pool `p`, curator-bonded liquidity removed in a single settlement window never
> exceeds the outstanding obligation, except under the last-resort condition, in which case
> the removal never exceeds the shortfall.

```solidity
// In the hook, for every removal with salt == CURATOR_SALT:
//   if (Q > 0) {
//       assert(insolvency);                       // Q > D
//       assert(removedLiquidity <= Q - D);       // bounded by the shortfall
//   } else {
//       assert(curatorExitApproved[p]);           // approved and Q == 0
//   }
```

**Test:** `test_invariant_cepHolds`, `test_curatorBlockedWhileObligationOutstanding`,
`test_lastResortBoundedByShortfall`.

### INV-4 — Settlement is corroborated, not asserted

> A claim's `settledAmount` only increases by an amount that is corroborated by an observed
> decrease in vault-side liquidity since the claim was registered.

```solidity
assert(claim.settledAmount <= claim.liquidityAmount);
assert(totalLiquidityAtRegistration − currentVaultTotal >= claim.settledAmount);
```

**Test:** `testFuzz_settleCannotExceedRealRemoval`, `test_settleOverClaimReverts`.

### INV-5 — The oracle can never gate a depositor exit

> No depositor-side function's behaviour changes based on the oracle, its staleness, or its
> value. The risk state affects curator-side operations only.

```solidity
// Fuzz oracle returns 0, stale, extreme, reverting
assert(depositorCanAlwaysExit());
assert(riskState change ⇒ curatorOps blocked, depositorOps unaffected);
```

**Test:** `testFuzz_oracleNeverBlocksDepositorExit`, `test_oracleStaleDegradesToRestricted`.

### INV-6 — No depositor lockout

> For any state reachable by the invariant handler, there exists a sequence of at most N calls
> that lets a depositor reduce their position to zero.

```solidity
// Property-style check in the handler:
//   deposit ⇒ requestWithdraw ⇒ settleClaims ⇒ position shrinks to 0
assert(depositorExitAlwaysReachable());
```

**Test:** `test_invariant_depositorNeverStuck`, `test_lastResortReleasesEverythingProRata`.

---

## 5. Additional invariants

| ID | Statement |
|---|---|
| INV-7 | `curatorLiquidity` and `depositorLiquidity` shadow counters always equal the sum of the actual pool position liquidity for their salt classes, as computed independently from `StateLibrary`. |
| INV-8 | `curatorExitApproved[poolId]` is false whenever `pendingLiquidity[poolId] > 0`. |
| INV-9 | `curatorLiquidity / (curatorLiquidity + depositorLiquidity) >= minSkinBps` at every block boundary, except transiently inside a settlement transaction that is immediately followed by a compensating action. |
| INV-10 | Total shares outstanding × NAV per share never exceeds the vault's actual token balance plus accrued fees (no over-minting of fee shares). |
| INV-11 | No claim can be settled twice for the same liquidity; `settledAmount` is monotonically increasing and bounded by `liquidityAmount`. |
| INV-12 | The dynamic fee set by the hook never exceeds `mandate.maxFeeBps`. |
| INV-13 | A curator's bond balance derived from `StateLibrary` always equals the vault's recorded bond claim (within rounding dust). |
| INV-14 | `claimTtl` expiry restores the depositor's shares exactly once. |

---

## 6. What counts as a "provable mandate violation" (forfeiture)

Forfeiture must be limited to things that are **provable on-chain from state, not inference**.

| Event | Provable? | Treatment |
|---|---|---|
| Tick band exceeded | **Prevented** — the hook reverts | No forfeiture needed (the tx cannot happen) |
| Fee cap exceeded | **Prevented** — the hook reverts | No forfeiture needed |
| Minimum skin breached | **Prevented** — the hook reverts | No forfeiture needed |
| Curator removal while obligations outstanding | **Prevented** — the hook reverts | No forfeiture needed |
| Drawdown beyond `maxDrawdownBps` | **Detected**, not prevented (requires a mark) | Performance fee forfeited on a confirmed breach; risk-increasing curator operations frozen |
| Strategy operations while `riskState >= Restricted` | **Prevented** — the hook reverts `RiskStateRestricted` | No forfeiture needed |

**Rule: never forfeit for something the hook already prevents.** Doing so would mean
forfeiting for an event that cannot occur, which is incoherent.

**Say this in the submission.** Distinguishing *prevented* from *detected and penalised* is a
mark of a careful protocol designer, and judges notice it.

---

## 7. Griefing vectors and mitigations

| Vector | Mitigation |
|---|---|
| A1: depositor registers a claim and never settles, locking the curator | Claims expire (`claimTtl`); shares are burned or reserved at registration so a fake claim costs real capital |
| A2: depositor dust-spams claims to force constant settlement | Per-depositor open-claim limit (e.g. 3) and a minimum claim size |
| A3: curator requests exit repeatedly to flip `curatorExitApproved` and probe state | Approval is idempotent and gated on `Q == 0`; add a per-epoch cooldown |
| A4: curator triggers a rebalance to move price against the pool and then exits | The tick band + min-skin + exit lock make this unprofitable; also record a per-epoch rebalance count |
| A5: third party front-runs a claim | Claims are FIFO by `claimId`; front-running a *claim* does not jump the queue |
| A6: someone calls `settleClaims` at a bad moment to crystallise a loss for the curator | Settlement is pro-rata and bounded; the shortfall rule is symmetric |
| A7: oracle manipulation to trigger `Breached` and forfeit the curator's fees | Use a TWAP / multi-source mark; require the deviation to persist across N observations before escalating |

---

## 8. Oracle failure modes

| Failure | Required behaviour |
|---|---|
| Feed returns 0 or negative | Treat as unavailable → risk state = Restricted |
| Feed is stale (`updatedAt` too old) | Risk state = Restricted |
| Feed reverts | Risk state = Restricted; **the hook must not revert** |
| Feed returns an extreme but plausible value | Use a deviation band; escalate only after N consecutive observations |
| Feed is unavailable at deploy time | `oracle == address(0)` → risk state stays Normal but no drawdown protection; surface this in the UI |

**Never:** let the oracle revert the hook. Wrap every oracle read in a `try/catch` and default
to the restrictive state. A hook that reverts on a bad oracle read can brick the pool.

---

## 9. Known residual risks

| ID | Risk | Mitigation | Status |
|---|---|---|---|
| R-01 | A malicious vault could try to remove curator liquidity outside the gate | The gate is in the hook, keyed by `salt` and the pool's own state | Designed |
| R-02 | The vault custodies the curator's bond | The curator's balance is independently derivable from `StateLibrary`; the hook's shadow ledger publishes it | Accepted |
| R-03 | Liquidity↔token conversion in concentrated liquidity is range-dependent | MVP uses a conservative pro-rata conversion; claims round up | Accepted, documented |
| R-04 | Approval + ledger-empty is not a strict FIFO queue for the curator | The observable difference is limited to a race between approval and claim registration, which INV-8 closes | Accepted |
| R-05 | `afterModifyLiquidity` shadow updates rely on the hook observing its own callbacks | v4 guarantees hooks are called on every modification; the counters are additionally cross-checkable against `StateLibrary` in tests | Designed |
| R-06 | Two positions in one range fragment price-impact reasoning | Documented; single-range is the MVP choice | Accepted |
| R-07 | Single pool per vault | Explicit scope decision | Accepted |
| R-08 | Exact liquidity↔token conversion not implemented | Conservative pro-rata | Accepted |
| R-09 | The vault is not upgradeable | Deliberate — immutability is a security feature here. Deploy a new vault instead | Deliberate |
| R-10 | The hook's `salt` constants could collide with another protocol using the same pool | Salts are per-vault-position; the vault owns its positions so collision is impossible in practice | Designed |

---

## 10. Audit posture for Demo Day

Be precise and honest. Say exactly this:

- Contracts are **unaudited**.
- We have run a **formal invariant suite** covering the six headline invariants, under fuzzing
  and a stateful handler, plus a fork test against a live testnet PoolManager.
- The design's security argument rests on **a small number of checkable invariants**, listed in
  this document, not on prose.
- The mechanism is **not custodial in the sense that matters**: depositor and curator balances
  are both derivable from pool state by anyone.

That last point is a differentiator worth stating explicitly: *anyone can verify the curator's
bond and the outstanding obligations by reading the pool.* That is not true of most vault
architectures, and it is the strongest single answer to "isn't this just a vault?"

---

*Next: `docs/06-API.md`.*
