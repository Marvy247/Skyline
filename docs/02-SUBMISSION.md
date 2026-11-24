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
- [x] Repo link added — https://github.com/Marvy247/Skyline
- [x] Deployed contract addresses on testnet added
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
> at the PoolManager level, so no execution path can route around it. If depositor liquidity
> cannot cover an obligation, the bond is a last-resort backstop, bounded by the shortfall.

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
the hook's last-resort branch allows the bond to be drawn down **only up to the shortfall**, and
the proceeds are delivered to the depositor. The bond is not a general escape hatch. A market
loss between claim registration and settlement is borne by the shares that bore the risk; the
curator is not slashed because the pool moved.

### 5.1 Mechanism components

| Component | Purpose |
|---|---|
| **Curator bond** | Ensures the curator has capital at risk, held in an identifiable position inside the same pool. |
| **Exit priority** | Depositors receive priority over curator withdrawals, enforced by the hook's own ledger. |
| **Last-resort bond drawdown** | If depositor liquidity cannot cover an obligation, the bond supplies the remainder, bounded by the shortfall and paid to the depositor. Market losses are not slashed from the curator. |
| **Mandate enforcement** | Prevents unauthorised strategy operations — fee cap, tick band, minimum skin, drawdown limits. |
| **Performance-fee forfeiture** | Aligns compensation with responsible management: fees forfeited on a confirmed drawdown breach. |
| **Chainlink risk regime** | An external mark selects `Normal`/`Restricted`/`Breached`; a stale or failed read degrades toward restriction, never toward permissiveness. |

---

### 5.2 What the counterfactual proves

`test/unit/Counterfactual.t.sol` runs the same vault, the same curator and the same withdrawal
twice — with the gate and without it.

| | Without CEP | With CEP |
|---|---|---|
| Curator exits first | allowed | **blocked** |
| Bond at the moment the claim is registered | **0** | **still in the pool** |
| Depositor's market payout | whatever remains | the same market payout — **ordering changed, not the price** |
| Curator accountability | none | locked behind the claim until it settles |

This is the honest claim. CEP does not insure the depositor against the market; it removes the
curator's head start. The depositor was always exposed to the strategy; they were never supposed
to be exposed to the curator's exit.

---

## 6. Core features

1. **Curator-Bonded Liquidity** — curators commit their own capital alongside the liquidity
   they manage, in a position the protocol can identify and the hook can gate.
2. **Hook-Enforced Exit Priority** — curator liquidity cannot be withdrawn ahead of outstanding
   depositor claims. The restriction is enforced by the hook's own ledger, not asserted by the
   vault.
3. **Economic Alignment** — the curator's own capital sits in the same pool and cannot leave
   ahead of depositors. In the last-resort case the bond is drawn down only up to the uncovered
   liquidity shortfall, and the proceeds go to the depositor. A market loss is borne by depositor
   shares, not slashed from the curator.
4. **Programmable Mandates** — strategy permissions, allocation limits and risk parameters are
   committed at pool creation and enforced by the hook at the point of action.
5. **Verifiable Accountability** — strategy operations, withdrawal requests, curator
   restrictions and performance records are recorded on-chain and independently readable.
6. **Depositor Exit Is Never Blocked** — Skyline reorders *who leaves first*. It never prevents
   a depositor from exiting; a pro-rata last-resort path guarantees liveness.

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
| **Curator Exit Parity (new)** | **Bonded curator capital, hook-enforced exit priority, last-resort bond drawdown** |

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

A live, seeded scenario on Base Sepolia (addresses in §13.1):

1. A curator posts a bond into a Uniswap v4 pool. Two depositors fund the same strategy.
2. The strategy degrades. A depositor requests a withdrawal → the hook records the obligation.
3. **The curator attempts to exit. The hook rejects it.** The depositor's claim has priority,
   and the restriction is enforced by the hook's own ledger, not by the vault's word.
4. Claims settle from depositor liquidity while the curator remains locked. In the last-resort
   case, the bond supplies the uncovered liquidity, bounded by the shortfall, and the proceeds go
   to the depositor. A market loss is not charged to the curator.
5. The curator may now request an exit and receive the remaining bond's proceeds.
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

### 13.1 Live deployment — Base Sepolia, chain 84532

| Contract | Address |
|---|---|
| v4 PoolManager (canonical) | `0x05E73354cFDd6745C338b50BcFDfA3Aa6fA03408` |
| SkylineHook | `0xBcf550c214Fe3Ea4e61813241Aab2B113E434F80` |
| SkylineVault | `0x51d200C87e05a4c3E13460E6F0D46977be2622C9` |
| SkylineKeeper | `0x708C227792F969d62206E4d76603Aa1d1b9C5796` |
| PoolId | `0x7f355bcf7712d42494a0e9f860370f40f328bddfa465cccb630ddcc03a174b5b` |
| USDC (currency0) | `0x036CbD53842c5426634e7929541eC2318f3dCF7e` |
| WETH (currency1) | `0x4200000000000000000000000000000000000006` |
| Chainlink ETH/USD | `0x4aDC67696bA383F43DD60A9e78F2C97Fbbfc7cb1` |

The pool uses fee `3000` and tick spacing `60`, with the strategy range at `196020..208080`.
The vault is seeded with a curator bond and two depositor positions. At the time of writing,
the stored `riskState` is `Normal`; `effectiveRiskState` is `Normal` while the keeper's
evaluation is fresh and degrades to `Restricted` once it is more than an hour old, by design.
The curator exit gate is closed only by the obligation ledger, and the keeper's
`performUpkeep` has been exercised on-chain. The machine-readable artifact is
`contracts/deployments/84532.json`.

| Field | Value |
|---|---|
| Project name | Skyline |
| Tagline | You manage the liquidity. You share the risk. You don't get to run first. |
| Track / theme | Active Management and Curation |
| Category | Liquidity management / risk alignment |
| Integrations | Uniswap v4 (PoolManager, Hooks, StateLibrary), Chainlink (Price Feeds + Automation), Foundry |
| Repo | **https://github.com/Marvy247/Skyline** |
| Demo video | `TODO` — 90-second clip, before 30 November |
| Deployed addresses | **Base Sepolia (84532)** — Hook `0xBcf550c214Fe3Ea4e61813241Aab2B113E434F80` · Vault `0x51d200C87e05a4c3E13460E6F0D46977be2622C9` · PoolId `0x7f355bcf7712d42494a0e9f860370f40f328bddfa465cccb630ddcc03a174b5b` |
| Team | **Marvy247** |
| Track priority | Uniswap Prize (title sponsor) + Chainlink Prize + General Prize |

---

## 14. Post-submission update checklist

Refresh this document whenever the implementation diverges from it.

- [x] Phase 0 confirmed the v4 position-keying model — attach the Foundry assertion output
- [ ] Confirm which Chainlink product the prize track actually wants; adjust §10
- [x] Replace "predefined loss-absorption rules" with the shipped lock plus bounded last-resort drawdown
- [x] Add the actual deployed pool address, hook address, vault address
- [ ] Add a short architecture diagram to the submission if the form allows
- [x] Confirm the demo scenario matches `docs/11-DEMO.md` exactly
- [ ] Before 30 Nov progress update: publish the repo and a 90-second demo clip

---

*Next: `docs/03-ARCHITECTURE.md`.*
