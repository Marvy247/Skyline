# 11 — Demo Day Run of Show

> **Demo Day: 11 December 2026. Judging: 4–10 December.**
>
> Five minutes on stage. One sentence to remember: **the curator cannot run.**
>
> Rehearse this document end to end, twice, with a timer, before 3 December. Then once more
> with the Demo Day contingency path (see §7).

---

## 1. The scenario, in one paragraph

A curator has posted $20,000 of bonded capital into a Uniswap v4 pool alongside $80,000 of
depositor capital. The strategy has degraded 8%. Alice requests a withdrawal. The hook records
the obligation and immediately locks the curator's exit. The curator tries to leave. **The hook
rejects it.** Claims settle from depositor liquidity; where that is insufficient, the curator's
bond absorbs the shortfall. Only then may the curator exit — netted by whatever it still owes.

---

## 2. Pre-seeded state (set up before you walk on)

Deploy and seed **before** Demo Day. Nothing on stage should require a deploy.

| Step | Action | Result |
|---|---|---|
| 1 | Deploy hook, vault, pool | Base Sepolia (or Unichain Sepolia) |
| 2 | `curatorDeposit(20_000 USDC)` | `C = 20,000` liquidity units |
| 3 | Alice `deposit(50_000 USDC)` | `D = 50,000` |
| 4 | Bob `deposit(30_000 USDC)` | `D = 80,000` |
| 5 | Swap to move the price −8% | Strategy degraded; NAV falls |
| 6 | Alice `requestWithdraw(50_000 USDC)` | Claim #1 registered; `Q = 55,556` |
| 7 | *(Optional)* push a second claim so the queue shows two entries | |

These are the fixture's narrative numbers. The live Base Sepolia deployment is seeded with
smaller amounts; §9 gives the exact live replay and the values it produces.

**Verify before you walk on:**

- [ ] `pendingLiquidity(poolId)` == 55,556
- [ ] `isCuratorExitBlocked(poolId)` == true
- [ ] `verifyCep(poolId).cepHolds` == true
- [ ] The dashboard shows the **ENFORCED** badge with the right numbers
- [ ] The "Attempt curator exit" button produces the decoded revert

**Keep a second deployment ready** (the same scenario, unsettled) in case you need to reset.

---

## 3. The five minutes

### 0:00–0:30 — The hook

> "This is a Uniswap v4 pool with a curated liquidity vault in it. A curator manages the
> strategy; depositors supply the capital. That's the standard model.
>
> The problem is at the exit."

Open the dashboard, **Exit gate** tab. The CEP badge reads **ENFORCED**. Point at it.

### 0:30–1:30 — The problem, in three sentences

> "When a curator's strategy starts degrading, they find out before the depositors do. Their
> exit is contractually permitted — the vault is a plain ERC-4626 and redeem is symmetric. And
> their exit consumes pool liquidity, which moves the price against everyone still inside.
>
> The curator was paid to manage the strategy, and then left ahead of the people who funded it.
>
> Every existing curated-liquidity vault treats withdrawal as symmetric. That symmetry is the bug."

### 1:30–3:00 — The mechanism (the code is on screen)

Point at the source of the gate, already visible in the panel. Say:

> "Skyline keeps curator capital in a **separate Uniswap v4 position**, distinguished by its
> `salt`. And the hook keeps **its own ledger** of depositor withdrawal obligations.
>
> When a removal of curator-bonded liquidity comes through the PoolManager — any removal, from
> any router — the hook checks that ledger. Outstanding obligation? Reverted.
>
> And because the position owner is part of the v4 position key, and the PoolManager is the only
> way to modify liquidity, **there is no path around this.** Not a different router, not an
> aggregator, not a buggy vault."

### 3:00–4:00 — The demonstration

Click **Attempt curator exit**.

The revert appears, decoded:

> **CuratorExitBlocked**
> "The hook blocked the curator's exit: 55,556 liquidity units of depositor obligation are still
> unsettled."

Say, once, clearly:

> **"The curator cannot run."**

Pause. Let it land. Do not talk over it.

### 4:00–4:40 — Who absorbs the loss

Switch to **Overview**. Point at the exit ladder.

> "And when the claims settle, here's where the money comes from. Depositor liquidity first.
> Then the curator's bonded capital — because they can't extract what depositors are owed. Then
> pro rata, so a depositor is never locked out.
>
> The asymmetry is the product: the curator's downside is bigger than a depositor's, and that is
> priced into the curator's fee."

### 4:40–5:00 — Close

> "The curator's bond balance and the outstanding obligations are recomputed from the Uniswap v4
> pool itself. Anyone can check that. Open the **Verification** tab — those numbers come from
> the hook, not from the vault's books.
>
> Skyline. You manage the liquidity. You share the risk. You don't get to run first."

---

## 4. Backup beats (only if you have time or the demo breaks)

**Beat A — the bond absorbs the shortfall.** Open `?scenario=absorption`.

> "When depositor liquidity can't cover the claims, the curator's capital absorbs the difference.
> Ten thousand units of shortfall, taken out of the curator's bond, and their exit proceeds are
> netted by it."

**Beat B — the mandate.** Open **Mandate** tab.

> "The curator also operates inside a committed mandate — fee cap, tick band, minimum skin. The
> hook enforces those where liquidity actually changes. And notice the distinction: the things
> the hook *prevents* can't happen, so we don't punish them. The drawdown limit is different —
> that can only be detected after the fact, and there the performance fee is forfeited."

**Beat C — the withdrawal request itself.** Open **Claims** tab.

> "Depositors don't wait for a queue to clear. They register a claim, it's recorded on-chain
> immediately, and it's served FIFO. The queue is what makes the curator's exit subordinate —
> it's the record."

---

## 5. Anticipated questions

**"Isn't this just a vault with a hook attached?"**
> "No — and it's a fair challenge. The difference is who holds the ledger. If the hook asked the
> vault whether claims were outstanding, it would inherit the vault's trust assumptions and the
> hook would be decorative. The hook keeps its own ledger, decrements it only from liquidity
> removals it observes, and enforces the gate itself. Delete the hook and the protocol doesn't
> weaken — it stops existing."

**"Why can't the curator just exit through a different router?"**
> "Because of how v4 keys positions: `keccak256(owner, tickLower, tickUpper, salt)`, with the
> owner set to `msg.sender` at the PoolManager. Only the owner can modify its own position, the
> PoolManager is the only way to modify liquidity, and the hook is invoked by the PoolManager on
> every modification. There is no route that skips it. We assert this in the test suite."

**"What if the curator refuses to cooperate?"**
> "They don't have to. The bond position is held by the vault, so the vault can serve claims
> from it without the curator's permission — bounded by the shortfall, and only when depositor
> liquidity provably cannot cover the claims. The curator's exit proceeds are netted by whatever
> is still owed."

**"What stops the curator from manipulating the price to trigger a loss?"**
> "The tick band and minimum skin constrain their position changes, and the exit lock means they
> can't profitably leave. The mandate is committed at pool creation and enforced by the hook, so
> tightening it requires the protocol's consent."

**"How do we know the reported performance is real?"**
> "Performance isn't the point — ordering is. But the same principle applies: the numbers the
> protocol reports are derived from pool state, and the hook recomputes them. Nothing in the
> dashboard is taken on trust from the vault."

**"Is this audited?"**
> "No, it isn't audited. What we do have is a formal invariant suite with a stateful handler
> under fuzzing, plus a full rehearsal of this exact scenario against a fork of the live Base
> Sepolia deployment. The central claim — a curator cannot exit ahead of outstanding depositor
> obligations — is an asserted invariant, not a sentence in a whitepaper."

**"What's the business model?"**
> "Performance fees, collected by a curator who is willing to post capital and accept the
> constraint. The constraint is the product: a curator who can credibly promise 'I won't run' is
> worth more than one who can't. Right now the only way to make that promise enforceable is this."

**"How is this different from Morpho/Goldfinch-style withdrawal queues?"**
> "Queues solve timing for depositors. They say nothing about the subordination of the *manager's*
> capital. Skyline's entire mechanism is about the curator's exit, not the depositor's."

**"What if the claims can never be settled?"**
> "There's a pro-rata last resort: if depositor liquidity and the curator's bond together still
> can't cover the claims, everything is released pro rata and the uncovered amount becomes a
> receivable against the curator. A depositor is never locked out. That's an invariant we assert."

**"What about multi-pool strategies?"**
> "Out of scope for the MVP — one pool per vault. The ledger is keyed by `PoolId`, so the
> architecture doesn't preclude it, but we haven't built it and I won't claim it."

---

## 6. Setup checklist — the morning of Demo Day

- [ ] Laptop charged, second battery, charger packed
- [ ] Browser profile clean; MetaMask on the right network and account
- [ ] Dashboard open at `?tab=exit` on the **live** deployment
- [ ] `?tab=exit&scenario=blocked` open in a second tab (contingency)
- [ ] Explorer tab open on the pool address
- [ ] `cast` ready in a terminal with the deployer key loaded
- [ ] Screenshots of the key states saved locally (in case the network dies)
- [ ] Screen sharing tested at the actual resolution
- [ ] Presenter notes open on the second monitor
- [ ] **Do not** depend on the demo running live — have the recorded clip ready
  (`docs/07-BUILD-ORDER.md` task 9.3)

---

## 7. Contingency plan

| If this breaks | Do this |
|---|---|
| Public RPC is slow or down | Switch to `?scenario=blocked` (demo fixture). Same components, same story. |
| Wallet won't connect | Use the fixture. Say: *"let me show you the state directly"* and open the scenario tab. |
| The transaction doesn't land | The revert is the point, so a **failing** transaction is not a failure — narrate it. If the tx doesn't even broadcast, use the fixture. |
| The dashboard is broken entirely | Fall back to the 90-second clip + the source code in your editor. |
| The chain is congested | Switch to the second deployment on the other testnet. |
| Everything is broken | Use the slides. Then spend the remaining time on the mechanism diagram and the invariant list. |

**The demo must never depend on a successful transaction.** The whole point is a *failed* one.
Plan for the failure.

---

## 8. Recording a 90-second clip (needed by 30 Nov)

Shot list:

1. Dashboard, Overview tab, CEP badge (3 s)
2. Exit gate tab — the source code of the gate (4 s)
3. Click "Attempt curator exit" — the decoded revert (5 s)
4. Exit ladder — who absorbs what (4 s)
5. Verification tab — pool-derived vs recorded (4 s)
6. Landing page hero (3 s)

Record at 1920×1080, no audio needed, no cursor jitter. **This is the submission's demo link.**

---

## 9. Live replay — Base Sepolia (actual numbers)

The seeded live deployment is the proof; the fixture is the polished narrative. If you record
the replay on a fork, the live seed stays intact for Demo Day.

### 9.1 Addresses and starting state

| Item | Value |
|---|---|
| Hook | `0xBcf550c214Fe3Ea4e61813241Aab2B113E434F80` |
| Vault | `0x51d200C87e05a4c3E13460E6F0D46977be2622C9` |
| Keeper | `0x708C227792F969d62206E4d76603Aa1d1b9C5796` |
| PoolId | `0x7f355bcf7712d42494a0e9f860370f40f328bddfa465cccb630ddcc03a174b5b` |
| Curator / sole share holder | `0x27A2dD1823D883935c9824fbaC0a018cE8e891E5` |

Starting state: `totalAssets` `3,951,074` (3.951074 USDC), `totalSupply` `4,030,216`, NAV
`0.980362839113337845`, `pendingLiquidity` `0`, depositor liquidity `182,896,908,595`, curator
liquidity `46,354,030,478`. The testnet seed uses one key for both roles for funding convenience;
the contracts still hold the depositor and curator capital in separate v4 positions, and the
hook does not care who owns the shares.

### 9.2 Replay on a fork (leaves the live seed untouched)

```bash
# Terminal 1
anvil --fork-url "$BASE_SEPOLIA_RPC_URL" --chain-id 84532 --port 8546 --auto-impersonate

# Terminal 2 — use the same cast commands against http://127.0.0.1:8546
V=0x51d200C87e05a4c3E13460E6F0D46977be2622C9
H=0xBcf550c214Fe3Ea4e61813241Aab2B113E434F80
P=0x7f355bcf7712d42494a0e9f860370f40f328bddfa465cccb630ddcc03a174b5b
D=0x27A2dD1823D883935c9824fbaC0a018cE8e891E5
R=http://127.0.0.1:8546
```

| Step | Command | Expected |
|---|---|---|
| 1 | `cast send $V 'requestWithdraw(uint256)' 500000 --from $D --unlocked --rpc-url $R` | claim 0; `pendingLiquidity` `22,690,688,424`; `isCuratorExitBlocked` `true` |
| 2 | `cast send $V 'requestCuratorExit()' --from $D --unlocked --rpc-url $R` | revert `CuratorExitBlocked(22690688424)` |
| 3 | `cast send $V 'settleClaims(uint256)' 10 --from $D --unlocked --rpc-url $R` | claim settled; pending `0`; blocked `false` |
| 4 | `cast send $V 'requestCuratorExit()' --from $D --unlocked --rpc-url $R` | approved |
| 5 | `cast send $V 'curatorExit(uint128)' 46354030478 --from $D --unlocked --rpc-url $R` | curator liquidity `0`; proceeds `998,040` (0.99804 USDC) |

Step 2 is the shot. The error selector is `0xb2f9ec04` (`CuratorExitBlocked(int128)`) and the
argument is the outstanding obligation — the hook's own ledger, not the vault's opinion.

### 9.3 If you record against the live deployment

Do **not** run step 5 on the live deployment before Demo Day: it consumes the seeded curator
bond. For the 90-second clip, stop after step 3, or run the whole sequence on the fork and show
the live dashboard only for the current state. The decoded-revert interaction can also be shown
from `?scenario=blocked`, which is the same component tree with the fixture's numbers.

---

*Next: `docs/12-VERIFICATION.md`.*
