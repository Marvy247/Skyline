# 02 — UHI11 Submission

> **Deadline: 16 November 2026 (project idea submission).**
> Demo Day: 11 December 2026. Judging: 4–10 December. Final submission: 3 December.
>
> This is the near-final text. Update it once the implementation ships — see the checklist at
> the end of this document. Fields marked `TODO` must be filled before submitting.

---

## 0. Submission checklist

- [ ] Every `TODO` filled
- [ ] Demo video link added (or placeholder committed to by 30 Nov)
- [ ] Repo link added (public or private-with-access)
- [ ] Deployed contract addresses on testnet added
- [ ] Theme-mapping table matches `01-PROJECT-BRIEF.md` §6
- [ ] The "why a hook" paragraph survives the "so what, it's just a vault" objection
- [ ] Spelling out that the curator cannot *block* depositor exits
- [ ] Read it aloud, timed, at 90 seconds

---

## 1. Project name

**Skyline**

*Curator Exit Parity: hook-enforced exit alignment for Uniswap v4 curated liquidity.*

---

## 2. One-line pitch

> **You manage the liquidity. You share the risk. You don't get to run first.**

---

## 3. Tagline and elevator (30 seconds)

> **Skyline is the exit-alignment protocol for curated liquidity on Uniswap v4.**
>
> When a curator's strategy degrades, informed depositors leave first — and the curator, who
> knew it was degrading, is perfectly positioned to leave ahead of them, worsening the price
> for everyone still inside.
>
> Every existing curated-liquidity vault treats withdrawal as a symmetric ERC-4626 redeem.
> That symmetry is the bug.
>
> Skyline makes curator capital **junior** to depositor capital by construction. A Uniswap v4
> hook keeps its own independent ledger of outstanding depositor withdrawal obligations and
> **rejects any removal of curator-bonded liquidity while those obligations are unsettled** —
> at the PoolManager level, so no execution path can route around it. When depositor liquidity
> cannot cover claims at fair value, the curator's bond absorbs the shortfall.

---

## 4. Problem statement

In conventional curated liquidity systems, managers can possess informational and operational
advantages over depositors, creating situations where curators may withdraw their capital
before liquidity providers during periods of deteriorating strategy performance.

This is not a problem of bad faith. It is a problem of **misaligned exit incentives**. A curator
who recognises degradation early faces no protocol-level obstacle to exiting first, and that
exit consumes pool liquidity, moving the price against the depositors who remain. The curator
has been paid to manage the strategy and then leaves ahead of the people who funded it.

There is no transferable, enforceable mechanism in the current curated-liquidity stack that
prevents this. Withdrawal queues solve deposit-side timing for *depositors*; they say nothing
about the subordination of the manager's own capital.

---

## 5. Core innovation: Curator Exit Parity (CEP)

**Curator Exit Parity** is the property that a curator's withdrawal capacity cannot exceed
outstanding depositor withdrawal obligations.

Curators must commit their own liquidity alongside depositor capital. Through a dedicated
Uniswap v4 hook, the protocol maintains an **independent ledger of outstanding depositor
withdrawal obligations** and prevents curator-bonded liquidity from being removed while those
obligations remain unsettled.

When depositor withdrawal obligations cannot be satisfied from available depositor liquidity,
predefined loss-absorption rules expose the curator's bonded capital to the shortfall, and the
curator's exit proceeds are netted against it.

### 5.1 Mechanism components

| Component | Purpose |
|---|---|
| **Curator bond** | Ensures the curator has capital at risk, held in an identifiable position inside the same pool. |
| **Exit priority** | Depositors receive priority over curator withdrawals, enforced by the hook's own ledger. |
| **Loss absorption** | The curator bond absorbs predefined shortfalls; the curator's exit proceeds are netted against uncovered claims. |
| **Mandate enforcement** | Prevents unauthorised strategy operations — fee cap, tick band, minimum skin, drawdown limits. |
| **Performance-fee forfeiture** | Aligns compensation with responsible management: fees forfeited on a confirmed drawdown breach. |
| **Chainlink risk regime** | An external mark selects `Normal`/`Restricted`/`Breached`; a stale or failed read degrades toward restriction, never toward permissiveness. |

---

## 6. Core features

1. **Curator-Bonded Liquidity** — curators commit their own capital alongside the liquidity
   they manage, in a position the protocol can identify and the hook can gate.
2. **Hook-Enforced Exit Priority** — curator liquidity cannot be withdrawn ahead of outstanding
   depositor claims. The restriction is enforced by the hook's own ledger, not asserted by the
   vault.
3. **Economic Loss Alignment** — predefined mechanisms expose curator-bonded capital to
   eligible liquidity shortfalls; uncovered claims are netted from curator exit proceeds.
4. **Programmable Mandates** — strategy permissions, allocation limits and risk parameters are
   committed at pool creation and enforced by the hook at the point of action.
5. **Verifiable Accountability** — strategy operations, withdrawal requests, curator
   restrictions and performance records are recorded on-chain and independently readable.
6. **Depositor Exit Is Never Blocked** — Skyline reorders *who leaves first* and *who absorbs
   the loss*. It never prevents a depositor from exiting; a pro-rata last-resort path guarantees
   liveness.

---

## 7. Uniswap v4 integration

Skyline uses Uniswap v4 hook callbacks to enforce liquidity-removal restrictions at the
PoolManager level, making curator exit restrictions an integral part of liquidity execution
rather than an external vault policy.

Concretely:

- v4 position keys are `keccak256(owner, tickLower, tickUpper, salt)`. Depositor capital and
  curator bond are held in **two separate positions**, distinguished by `salt`.
- `beforeRemoveLiquidity` receives the **position owner** and the **`salt`**, so the hook
  attributes any removal to curator or depositor natively — with no off-chain bookkeeping and
  no trust in the vault.
- Because the position owner is part of the position key and is set to `msg.sender` at the
  PoolManager, **only the owner of a position can modify it**. Because the PoolManager is the
  only way to modify liquidity, and hooks are invoked on every modification, **no execution
  path removes curator-bonded liquidity without passing through the hook's gate** — not a
  different router, not an aggregator, not a compromised vault.

Skyline reads pool state through v4's `StateLibrary` and modifies liquidity through
`PoolManager.unlock` / `modifyLiquidity` with explicit settlement.

---

## 8. Differentiation

**Against other curated-liquidity vaults.** The closest in-cohort implementation provides a
curated ERC-4626 vault with high-water-mark performance fees, a strategy registry and an
oracle-triggered rebalancing hook. At source level it contains no curator bond, no withdrawal
priority, no exit restriction, does not use position `salt`, and **does not implement
`beforeRemoveLiquidity` at all** — its withdrawal path is a symmetric ERC-4626 redeem.
Skyline operates precisely on that path.

**Against prior hook art.** The nearest mechanisms are a time-based fractional liquidity lock
(`LiquidityFloor`) and a per-epoch delegated-agent spend budget enforced in the pool
(`AgentBudget`). The first is single-party and time-based; the second bounds what a manager may
*spend*. Skyline bounds **when a manager may leave**. No existing mechanism subordinates a
curator's capital to depositor withdrawal obligations.

---

## 9. Alignment with the UHI11 theme — *Active Management and Curation*

| Theme opportunity | Skyline coverage |
|---|---|
| Vault-managed or token-gated hook modules | The hook **is** the vault's enforcement module; curator and depositor admission are allowlisted |
| Curated LP networks (depositors follow managers) | Depositors follow a curator whose capital is bonded and subordinated to them |
| Hooks that auto-rebalance via oracle triggers | Chainlink-sourced risk regime freezes risk-increasing curator operations in `Restricted`/`Breached`; a stale feed restricts rather than relaxes |
| Performance fees | High-water-mark performance fee, dilution-only, forfeited on a confirmed drawdown breach |
| Strategy migration between pools | Single-transaction migration with fee settlement |
| **Curator Exit Parity (new)** | **Bonded curator capital, hook-enforced exit priority, loss absorption** |

---

## 10. Chainlink integration

Chainlink provides **external information, never permission to withdraw**. The exit restriction
continues to work if the oracle or automation service becomes unavailable.

| Chainlink product | Role | Failure behaviour |
|---|---|---|
| **Price Feeds** | Supplies the reference mark used to compute the strategy's drawdown against a high-water mark and the mandate limit, which selects the risk state (`Normal` / `Restricted` / `Breached`) | The read never reverts the hook. Zero, negative, stale, incomplete and reverting reads all degrade to **`Restricted`**. A stale or never-run evaluation is also treated as `Restricted`. Depositor exits are unaffected in every case. |
| **Automation** | Executes periodic risk-state refresh and claim settlement through `SkylineKeeper`, an `IAutomationCompatible` contract | Both functions are also permissionless. Automation is an optimisation, never a dependency; `performData` is ignored. |

The oracle is deliberately **not** on the depositor exit path: a stale or frozen feed must never
be able to trap a depositor's capital. `Restricted` freezes **risk-increasing** curator actions
only — it never traps the curator's own exit.

The integration is tested: 21 tests cover healthy, zero, negative, stale, incomplete and
reverting feeds, the high-water-mark ratchet, two-observation breach confirmation, the keeper,
and a 10,000-run fuzz asserting that a depositor can still register and settle a claim under
every failure mode.

---

## 11. Demo

A live, seeded scenario on a public testnet:

1. A curator posts a bond into a Uniswap v4 pool. Two depositors fund the same strategy.
2. The strategy degrades. A depositor requests a withdrawal → the hook records the obligation.
3. **The curator attempts to exit. The hook rejects it.** The depositor's claim has priority,
   and the restriction is enforced by the hook's own ledger, not by the vault's word.
4. Claims settle. Depositor liquidity funds them; where it cannot, the curator's bond absorbs
   the shortfall and the dashboard shows exactly who absorbed what.
5. The curator may now exit — netted against any uncovered claim.
6. A second curator operation is attempted outside the committed mandate. The hook rejects that
   too.

The whole demo is one sentence: **the curator cannot run.**

---

## 12. Vision

To establish a new trust and economic-alignment primitive for professional liquidity management
— making curated liquidity transparent, accountable and sustainable, by subordinating the
manager's capital to the people whose capital they manage.

---

## 13. Submission fields

| Field | Value |
|---|---|
| Project name | Skyline |
| Tagline | You manage the liquidity. You share the risk. You don't get to run first. |
| Track / theme | Active Management and Curation |
| Category | Liquidity management / risk alignment |
| Integrations | Uniswap v4 (PoolManager, Hooks, StateLibrary), Chainlink (Price Feeds + Automation), Foundry |
| Repo | `TODO` — publish before 30 November |
| Demo video | `TODO` — 90-second clip, before 30 November |
| Deployed addresses | `TODO` — Base Sepolia (84532); deploy script and artifact schema are ready |
| Team | `TODO` |
| Track priority | Uniswap Prize (title sponsor) + Chainlink Prize + General Prize |

---

## 14. Post-submission update checklist

Refresh this document whenever the implementation diverges from it.

- [x] Phase 0 confirmed the v4 position-keying model — attach the Foundry assertion output
- [ ] Confirm which Chainlink product the prize track actually wants; adjust §10
- [x] Replace "predefined loss-absorption rules" with the shipped rule
- [ ] Add the actual deployed pool address, hook address, vault address
- [ ] Add a short architecture diagram to the submission if the form allows
- [x] Confirm the demo scenario matches `docs/11-DEMO.md` exactly
- [ ] Before 30 Nov progress update: publish the repo and a 90-second demo clip

---

*Next: `docs/03-ARCHITECTURE.md`.*
