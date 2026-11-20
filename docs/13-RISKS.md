# 13 — Risk Register

> Scored **L**ikelihood × **Impact** on a 1–5 scale. Anything scoring 9+ needs a named owner and a
> weekly check.

---

## 1. Technical risks

| ID | Risk | L | I | Score | Mitigation | Owner | Trigger |
|---|---|---|---|---|---|---|---|
| R-01 | A malicious or buggy vault removes curator liquidity outside the gate | 2 | 5 | 10 | The gate lives in the hook, keyed by `salt` and pool state. A compromised vault still hits `beforeRemoveLiquidity`. | — | — |
| R-02 | The vault custodies the curator's bond | 3 | 3 | 9 | The curator's balance is independently derivable from `StateLibrary`; the hook publishes it via `verifyCuratorBond`. The vault cannot touch it without the hook's consent. | — | — |
| R-03 | Liquidity↔token conversion is range-dependent in concentrated liquidity | 4 | 3 | 12 | MVP uses a conservative pro-rata conversion; claims round **up** in liquidity and **down** in tokens, so the protocol never over-promises. | — | — |
| R-04 | Approval + empty-ledger is not a strict FIFO queue for the curator | 2 | 2 | 4 | INV-8 closes the observable race (a claim revokes approval). Documented deviation. | — | — |
| R-05 | Shadow counters drift from actual pool state | 2 | 4 | 8 | Cross-check against `StateLibrary` in the invariant suite (INV-7, INV-13). | — | — |
| R-06 | Two positions in one tick range fragment price-impact reasoning | 3 | 2 | 6 | Single-range is the MVP choice. Multi-range is a documented extension. | — | — |
| R-07 | Single pool per vault | 4 | 2 | 8 | Explicit scope decision. Ledger is keyed by `PoolId`, so the architecture allows more. | — | — |
| R-08 | Exact liquidity↔token conversion not implemented | 4 | 2 | 8 | Conservative pro-rata. Ship it, don't over-claim it. | — | — |
| R-09 | The vault is not upgradeable | 1 | 3 | 3 | **Deliberate.** Immutability is a security feature. Deploy a new vault instead. | — | — |
| R-10 | A salt collision with another protocol using the same pool | 1 | 4 | 4 | The vault owns its positions, so no other protocol can create a position under the vault's owner. | — | — |
| R-11 | A depositor grief-locks the curator with unclaimed claims | 3 | 3 | 9 | Claims expire (`claimTtl`); shares are burned or reserved at registration so a fake claim costs real capital; per-depositor open-claim limit. | — | — |
| R-12 | A depositor is permanently locked out | 1 | 5 | 5 | Pro-rata last resort (INV-6). **Never add a global pause to the hook.** | — | — |

---

## 2. Schedule risks

| ID | Risk | L | I | Score | Mitigation |
|---|---|---|---|---|---|
| R-13 | Scope creep into "curated LP network" territory | 4 | 4 | 16 | `docs/01-PROJECT-BRIEF.md` §6 non-goals are binding. Any new feature needs an explicit scope change, not a quiet addition. |
| R-14 | Loss-absorption accounting is buggy | 3 | 4 | 12 | Keep curator bond value **out** of `totalAssets()` entirely. The bond is a carve-out; depositor NAV never includes it. |
| R-15 | Loss absorption is never finished | 3 | 3 | 9 | Ship the **gate** first (Phase 2). Absorption is the amplifier, not the thesis. |
| R-16 | Chainlink integration slips | 3 | 2 | 6 | One feed, one risk calculation. The exit path never depends on it. |
| R-17 | The demo depends on a live network | 4 | 5 | 20 | Demo fixture (`?scenario=blocked`) + a recorded 90-second clip. The demo must survive a failing network. |
| R-18 | An agent picks up the repo and breaks the architecture | 3 | 4 | 12 | The `README.md` §0 operating rules, `docs/05-SECURITY.md` invariants, `docs/15-PROGRESS.md` handover notes, and "never commit a failing test". |

---

## 3. Market and judging risks

| ID | Risk | L | I | Score | Mitigation |
|---|---|---|---|---|---|
| R-19 | Judges read it as "a vault with a hook attached" | 3 | 5 | 15 | Lead with the no-bypass argument; the demo shows a revert a vault could not have produced; the source of the gate is on screen. |
| R-20 | Another team submits the same mechanism | 2 | 5 | 10 | No keyword evidence of prior art, plus the mechanism is now specified in enough detail to be defensible. Ship fast; the demo and the code are the proof. |
| R-21 | The mechanism reads as too subtle for a 5-minute slot | 3 | 4 | 12 | One sentence ("the curator cannot run") + one button + one revert. See `docs/11-DEMO.md`. |
| R-22 | No sponsor prize matches Skyline's integrations | 3 | 3 | 9 | The RFH board has no curator ask. Mitigate by keeping the Chainlink integration real and by having the Uniswap Prize (title sponsor) as the primary target. **Confirm the sponsor list in the Discord.** |
| R-23 | "Why would a curator accept this?" goes unanswered | 2 | 4 | 8 | `docs/04-ECONOMICS.md` §10 has the answer. Say it on stage: the constraint is the product. |

---

## 4. Operational risks

| ID | Risk | L | I | Score | Mitigation |
|---|---|---|---|---|---|
| R-24 | The dashboard's derived PoolId does not match the deployed pool | 3 | 4 | 12 | Verify against the deployment output; sanity-check that `pendingLiquidity` is non-zero when a claim is open. |
| R-25 | The RPC provider rate-limits during the demo | 4 | 3 | 12 | Demo fixture + a private RPC as backup + the recorded clip. |
| R-26 | A new Solidity error is not added to the dashboard's decode ABI | 3 | 2 | 6 | `docs/06-API.md` §6 lists the full error set. Add to `lib/contracts.ts` → `mandateErrorsAbi` whenever you add one. |
| R-27 | The repo has a stale `tsconfig.tsbuildinfo` and type errors reappear | 2 | 1 | 2 | Delete `.next` and `tsconfig.tsbuildinfo` when a config change appears not to take effect. |

---

## 5. Risks we are deliberately accepting

| ID | Risk | Why we accept it |
|---|---|---|
| R-28 | The curator's capital is custodied by the vault | The alternative (a separate bond contract) means the vault cannot force absorption without the curator's cooperation, which makes loss absorption unenforceable. The curator's balance is independently verifiable, which is what actually matters. |
| R-29 | The drawdown limit requires an oracle | A limit that needs no external mark would be measuring the wrong thing. It is confined to curator-side restrictions. |
| R-30 | No upgrade path | A mutable curator-mandate contract is a mutable risk contract. Deploy a new vault. |
| R-31 | The dashboard does not chart historical performance | Performance charts are the curator's marketing. Skyline's product is ordering. Drawing a performance chart would blur the message. |

---

## 6. Watch list — check these weekly

- [ ] UHI11 sponsor list and prize categories (ask in the Discord)
- [ ] New UHI11 project submissions appearing in the hook directory
- [ ] Any new hook implementing curator priority or bond-locked exits
- [ ] Uniswap v4-core releases that change position keying or the hook interface
- [ ] Chainlink prize track scope

---

*Next: `docs/14-CONVENTIONS.md`.*
