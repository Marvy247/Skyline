# 01 — Project Brief

> Canonical statement of what Skyline is, why it exists, and what it deliberately is not.
> If any other document conflicts with this one, this one wins.

---

## 1. The problem

Curated liquidity is the dominant institutional DeFi model. A manager (the **curator**) deploys
a strategy, individual investors (the **depositors**) supply capital, and the curator earns a
fee for allocating it well. The strategy is actively managed: ranges are moved, positions are
rebalanced, leverage may be taken, exposure shifts across pools.

This creates a structural asymmetry that the market has never solved:

**The curator has an informational advantage, and a different exit incentive.**

Consider Bob, a curator. Alice deposits $100,000 into Bob's strategy vault. Bob posts $10,000
of his own capital as skin in the game. Over the following weeks Bob's strategy begins to
degrade — his own signal fired before the public one did.

Nothing is required of Bob to be dishonest. All the following are individually defensible:

1. Bob recognises the degradation first.
2. Bob's exit is contractually permitted — the vault is a plain ERC-4626 and redeem is symmetric.
3. Bob removes his $10,000 from the pool.
4. That removal is $10,000 of liquidity leaving the pool, which moves the price.
5. Alice — who has not yet reacted, or who is slower, or who has a longer horizon — is left
   holding a worse position at a worse price.
6. The remaining depositors collectively absorb the exit cost.

The depositor funded the strategy, bore the strategy's risk, and paid the cost of the curator's
exit. The curator was paid a fee for managing the strategy and then exited first.

This is not a hypothetical. It is the reason on-chain curators are not trusted with
institutional capital today, and it is why the most sophisticated DeFi vaults have converged on
queue-based withdrawal (Morpho, Yearn, Goldfinch) — i.e. they solved the *timing* problem for
depositors, and solved **none** of it for the curator.

**Every existing curated-liquidity implementation treats withdrawal as a symmetric ERC-4626
redeem.** That symmetry is the bug.

---

## 2. The insight

> **A curator who has capital at risk should not be able to extract that capital before the
> people whose capital they manage have been served.**

Two things must be true for this to hold:

1. **The curator must have skin in the game.** Capital that is not at risk creates no alignment.
2. **The curator's exit must be structurally subordinate to depositor obligations.** Not
   discouraged — *subordinate*. Determined by the protocol, enforced by code, observable by
   anyone.

Point 1 is a design choice. Point 2 is the hard part, and it is where every existing solution
stops. A vault can *say* "the curator won't run." A vault cannot *make* it true, because the
vault is an ordinary contract and the curator's exit eventually passes through an ordinary
Uniswap v4 pool.

**Uniswap v4 hooks can make it true**, because the hook sits at the PoolManager — below the
vault, below the router, below every periphery contract — and sees every liquidity modification
that happens in the pool.

---

## 3. The mechanism: Curator Exit Parity (CEP)

**Curator Exit Parity** is the property that a curator's withdrawal capacity is *parity-limited
by* — and cannot exceed — outstanding depositor withdrawal obligations.

It has four components, each of which is independently implementable and independently demoable:

| Component | Statement | Enforced where |
|---|---|---|
| **Curator bond** | The curator must post their own capital into the pool, in a position the protocol can identify as theirs. | Vault + hook (via `salt`) |
| **Exit priority** | Depositors' recorded claims are served before the curator may remove any curator-bonded liquidity. | **Hook** — the authoritative ledger |
| **Last-resort bond drawdown** | If depositor liquidity provably cannot cover a claim, the bond supplies the remainder, bounded by the shortfall and paid to the depositor. Market losses are not charged to the bond. | Vault accounting, gated by hook |
| **Mandate enforcement** | Committed parameters (fee cap, tick band, minimum skin, drawdown limits) bound the curator's operating authority. | **Hook** |

### 3.1 Why the hook ledger is authoritative

The single most important architectural decision in this project.

A naive design asks the hook "does the vault have outstanding claims?" and the hook calls the
vault. That design is worthless: the vault is a contract the curator (or the protocol's own
operator) can influence, so the hook inherits the vault's trust assumptions.

Skyline inverts it:

- The **hook owns the ledger**. `pendingDepositorLiquidity[poolId]` is hook storage.
- The hook **decrements it only from observed pool activity** — actual `liquidityDelta` values
  seen in `beforeRemoveLiquidity` / `afterRemoveLiquidity`, correlated by `hookData` but never
  authorised by it.
- The vault *requests* claims through the hook; it cannot assert them into nothing.

The hook is therefore not "a hook attached to a vault". It is the enforcement point, and the
vault is a client of it. If you delete the hook, the protocol does not weaken — it stops
existing. That is the difference between a wrapper and a mechanism, and it is what the judges
will be asked to assess.

### 3.2 Why two positions

Depositor liquidity and curator liquidity are held in **two separate v4 positions**, separated
by `salt`, both owned by the vault:

- `LP_SALT` — depositor capital
- `CURATOR_SALT` — curator bond

Because v4 position keys are `keccak256(owner, tickLower, tickUpper, salt)`, two positions with
different salts are independent: independent liquidity balances, independent fee growth
accounting, independent removal paths.

This separation is what makes the exit ladder executable (see `04-ECONOMICS.md` §4) and what
makes the attribution provable. Without it, "whose liquidity is this?" has no on-chain answer.

---

## 4. Why Uniswap v4, and why a hook

The problem statement is a vault problem. The *solution* is only possible because of v4 hook
semantics. Four specific mechanics carry the design:

| v4 mechanic | How Skyline uses it |
|---|---|
| `ModifyLiquidityParams.salt` — *"a value to set if you want unique liquidity positions at the same range"* | Distinguishes depositor capital from curator bond without a bespoke registry. |
| Position key = `keccak256(owner, tickLower, tickUpper, salt)`, with `owner = msg.sender` to the PoolManager | Only the owner can modify its own position. A third party cannot touch the curator's position. |
| `IHooks.beforeRemoveLiquidity(address sender, PoolKey, ModifyLiquidityParams, bytes hookData)` — the hook receives the **owner** and the **salt** | The hook attributes any removal to curator or depositor natively, with no off-chain bookkeeping. |
| `PoolManager` is the **single** entry point for all liquidity modification | There is no periphery, router, or aggregator path that bypasses the hook. Every removal, whatever route it arrives by, passes through `beforeModifyLiquidity` → our hook. |

**The no-bypass property, stated precisely:**

> Because the position owner is part of the position key and is set to `msg.sender` at the
> PoolManager, only the owner of a position can modify it. Because the PoolManager is the only
> way to modify liquidity, and the hook is invoked by the PoolManager on every modification,
> **no execution path exists that removes curator-bonded liquidity without passing through the
> hook's gate.** A compromised vault cannot bypass it. A different router cannot bypass it. An
> aggregator cannot bypass it.

This is the sentence that makes the project a hook project rather than a vault project, and it
belongs in the submission and in the demo.

### 4.1 What the hook is NOT doing

Be precise in the submission and demo. The hook does **not**:

- decide whether a strategy is good,
- price anything,
- arbitrate between depositors,
- rely on an oracle to permit an exit.

It enforces **sequencing and limits**. That is a small, sharp, verifiable job — which is exactly
what a hook should do.

---

## 5. Differentiation

### 5.1 Versus the closest in-cohort project (VaultCurator)

Verified by source inspection, not by README:

| | VaultCurator | Skyline |
|---|---|---|
| `CuratedVault` functions | `deposit, mint, withdraw, redeem, harvest, _accrueFees, setFeeRecipient, setMgmtFee, setPerfFee, setDepositCap, setDepositsPaused, deployCapital` | — |
| Curator bond | **none** | bonded position, `CURATOR_SALT` |
| Withdrawal queue | **none** | hook ledger, FIFO claims |
| Exit priority / locking | **none** | enforced in hook |
| Last-resort bond drawdown | **none** | bond supplies `Q − D`, paid to the depositor |
| `salt` used | **no** | yes — two positions |
| Hook `beforeRemoveLiquidity` | **not implemented** | core of the protocol |
| Withdrawal path | symmetric ERC-4626 redeem | priority-gated, sequenced |

> *VaultCurator owns the vault side of the UHI11 theme. Skyline owns the removal path.*

### 5.2 Versus the nearest hook prior art (`nirholas/hookforge`)

| Prior art | What it does | How Skyline differs |
|---|---|---|
| `LiquidityFloor` | *"Holds each position to a fraction of its own additions until an unlock date, so commitments are fractional and race-free."* | Time-based fractional lock, single-party, no curator role, no obligation priority. |
| `AgentBudget` | *"Enforces a signed per-epoch spend budget in the pool itself, so a delegated agent key is bounded by the venue rather than by its own code."* | Bounds what the manager may *spend*. Skyline bounds when the manager may *leave*. |
| `EpochRebalance` | Index weight schedule fixed before any deposit | Commits to *weights*, not to *exit priority*. |
| `CircuitBreaker` | *"Withdrawals stay open"* | Adopted as a principle: Skyline never blocks a depositor. |

No hook in the catalogue implements curator-bonded liquidity with depositor-priority exits.

---

## 6. Scope

### In scope (this is the build)

- One strategy pool per vault (single-pool vaults). Multi-pool is a stretch goal.
- Depositor claim queue with FIFO ordering, partial settlement, and expiry.
- Curator bond in a separate position, minimum skin, exit lock, netting.
- Hook-owned obligation ledger, per `PoolId`, liquidity-denominated.
- Three-stage exit ladder (see `04-ECONOMICS.md` §4) with a pro-rata last resort.
- Mandate: fee cap, tick band, minimum skin, max drawdown → risk states.
- Performance fee with high-water mark, dilution-only, forfeitable on mandate violation.
- Dashboard with live on-chain state and the demo scenario.
- Chainlink price feed for risk regime; Chainlink Automation for settlement (optional).

### Explicitly out of scope (say so in the submission)

- Multi-pool / cross-pool portfolio risk budgets.
- Curators operating *other* people's vaults.
- Any form of leverage, borrowing against the bond, or rehypothecation.
- Governance tokens, staking of curator bonds, insurance markets.
- Cross-chain. ZK proofs. FHE.
- Order-flow auctions, JIT liquidity, sandwich mitigation — **this is not an MEV project.**
- Any kind of automatic rebalancing driven by off-chain signals (a keeper may *propose*, the
  mandate decides whether the proposal is permitted).

### Explicit non-goals

- **Not a better liquidity manager.** Skyline does not try to produce more fees. It governs who
  bears risk and who leaves first.
- **Not a reputation system.** Reputation is nice-to-have; enforcement is the product.
- **Not a governance product.** No token, no DAO, no voting on parameters.

---

## 7. Glossary

| Term | Meaning |
|---|---|
| **Curator** | The manager of a strategy. Posts a bond; earns a performance fee; operates under a mandate. |
| **Depositor** | An LP who supplies capital to the vault and holds vault shares. |
| **Bond** | Curator capital, held in the `CURATOR_SALT` position, subordinate to depositor claims. |
| **Claim** | A depositor's recorded request to withdraw. FIFO-ordered, liquidity-denominated. |
| **Pending liquidity** | Hook ledger: outstanding depositor obligations for a pool, denominated in pool liquidity units. |
| **Mandate** | The committed parameter set binding the curator: fee cap, tick band, minimum skin, drawdown limit, exit rule. |
| **Risk state** | `Normal` / `Restricted` / `Breached`, derived from the Chainlink mark against the mandate's drawdown limit. |
| **Pro-rata last resort** | Stage 3 of the exit ladder: when claims exceed all liquidity, release everything pro rata so depositors are never stuck. |
| **CEP** | Curator Exit Parity — the invariant that curator exit capacity never exceeds outstanding depositor obligations. |

---

## 8. The one-sentence version

> Skyline makes curator capital **junior** to depositor capital by construction: a Uniswap v4
> hook keeps its own ledger of outstanding depositor withdrawal obligations and rejects any
> removal of curator-bonded liquidity while those obligations are unsettled. If depositor
> liquidity provably cannot cover a claim, the bond supplies the remainder, bounded by the
> shortfall and paid to the depositor.

---

## 9. What would make this fail

Honest self-assessment, so nobody is surprised later.

| Failure mode | Likelihood | Mitigation |
|---|---|---|
| The exit ladder's economics are too subtle to explain in 5 minutes | Medium | `docs/11-DEMO.md` — one scenario, three beats, one repeated sentence |
| Scope creep into "curated LP network" territory | Medium | `docs/01-PROJECT-BRIEF.md` §6 non-goals; enforce in review |
| Last-resort accounting is buggy | Medium | Never let `totalAssets` include curator bond value; keep the bond out of depositor NAV entirely. Market losses stay with shares; the bond is only a last-resort liquidity backstop. |
| Chainlink feed unreliable on testnet | Medium | `docs/10-CHAINLINK.md` — risk state degrades in the safe direction and never touches the exit path |
| Judges read it as "a vault with a hook attached" | Medium | The submission leads with the no-bypass argument; the demo shows a revert that a vault could not have produced |
| We run out of time before the last-resort drawdown | Medium | The exit gate is the thesis; the last-resort drawdown is the safety net. Ship the gate first. |
| A genuine fund-loss bug in the exit ladder | Low | `docs/05-SECURITY.md` — six headline invariants, fuzzed, plus `docs/13-RISKS.md` R-01..R-04 |

---

*Next: `docs/02-SUBMISSION.md` (the text we submit) → `docs/03-ARCHITECTURE.md` (how it is built).*
