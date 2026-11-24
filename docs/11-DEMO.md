# 11 — Demo Day Run of Show

> **Demo Day: 11 December 2026. Judging: 4–10 December.**
>
> Five minutes on stage. One sentence to remember: **the curator cannot run.**
>
> Rehearse this document end to end, twice, with a timer, before 3 December. Then once more
> with the Demo Day contingency path (see §7).

---

## 1. The scenario, in one paragraph

A curator has posted bonded capital into a Uniswap v4 pool alongside depositor capital. The
strategy has degraded 8%. Alice requests a withdrawal. The hook records the obligation and
immediately locks the curator's exit. The curator tries to leave. **The hook rejects it.**
Claims settle from depositor liquidity while the curator remains locked. If depositor liquidity
cannot cover an obligation, the bond supplies the remainder, bounded by the shortfall. A market
loss between registration and settlement is borne by depositor shares — the curator is not
slashed because the pool moved. Only after the queue clears may the curator exit with the
remaining bond.

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

### 4:00–4:40 — Who bears the loss

Switch to **Overview**. Point at the exit ladder.

> "And when the claims settle, here's where the money comes from. Depositor liquidity first.
> The curator's bond stays locked behind the claim — they can't extract what depositors are owed.
> Only if depositor liquidity provably cannot cover an obligation does the bond supply the
> remainder, bounded by the shortfall.
>
> A market loss is different. That is borne by the shares that bore the risk. The curator is not
> slashed because the pool moved — locking is not slashing.
>
> The asymmetry is the product: the curator cannot leave first, and that is priced into the
> curator's fee."

### 4:40–5:00 — Close

> "The curator's bond balance and the outstanding obligations are recomputed from the Uniswap v4
> pool itself. Anyone can check that. Open the **Verification** tab — those numbers come from
> the hook, not from the vault's books.
>
> Skyline. You manage the liquidity. You share the risk. You don't get to run first."

---

## 4. Backup beats (only if you have time or the demo breaks)

**Beat A — the last-resort bond drawdown.** Open `?scenario=lastresort` if the fixture is
available.

> "If depositor liquidity provably cannot cover an obligation, the hook allows the bond to be
> drawn down by exactly the shortfall — no more. The proceeds go to the depositor, and the
> position is reduced by what it paid. It is a backstop, not a general escape hatch, and it is
> not triggered by a market loss."

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
> "They don't have to. The bond position is held by the vault, so the vault can serve an
> obligation from it without the curator's permission — bounded by the shortfall, and only when
> depositor liquidity provably cannot cover the claim. A market loss is not charged to the bond;
> that would be slashing, and locking is not slashing."

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
> "The settlement loop serves claims FIFO and falls back to pro-rata if total claims ever exceed
> available liquidity. After the claim's TTL, anyone can expire it; the unserved shares return to
> the depositor, so nothing is permanently stuck. The worst case is a partial payout, not a
> lockout."

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

Record against the **live Base Sepolia dashboard**, connected to the demo wallet that holds the
seeded shares. The live deployment is at its initial state: `pendingLiquidity` `0`, claim queue
empty, `curatorExitApproved` false. The keeper's evaluation is fresh for one hour from deployment.
Before recording, call `SkylineKeeper.performUpkeep(0x)` — permissionless, costs a few cents of
testnet ETH — so the mandate panel shows `Normal` rather than the deliberate `Restricted` stale
state. Depositor exits and the exit gate are unaffected either way.

The recording needs **two wallet accounts**: the demo depositor
`0xc96d811952e6f87EFd0ddEDa3b85fe30F768AB5A` (holds `5.000000` shares) and the curator
`0x27A2dD1823D883935c9824fbaC0a018cE8e891E5`. `requestCuratorExit` is `onlyCurator`, so switch
MetaMask to the curator for the blocked-exit shot.

**Do not call `curatorExit`.** The last step only requests the vault's exit approval. Calling
`curatorExit` on the live deployment consumes the seeded curator bond before Demo Day.

| Time | Tab / action | What the viewer sees |
|---|---|---|
| 0:00–0:06 | Overview | Title card or the CEP badge: **Curator Exit Parity: ENFORCED** |
| 0:06–0:12 | Connect demo wallet | The seeded address and its `5.000000` shares |
| 0:12–0:24 | Claims → `2.5` → Request | Claim `#0` appears; `pendingLiquidity` becomes `112,860,603,472` |
| 0:24–0:36 | Switch to curator → Exit gate → Attempt curator exit | **`CuratorExitBlocked(112860603472)`**, decoded in plain English |
| 0:36–0:44 | "Why is it blocked?" | The hook's ledger, not the vault's opinion; not a timelock |
| 0:44–0:56 | Claims → Settle claims | Claim settles FIFO; `pendingLiquidity` returns to `0`; `2.432727` USDC paid |
| 0:56–1:08 | Exit gate → Attempt curator exit | This time it succeeds: the vault grants exit approval |
| 1:08–1:20 | Verification | Raw hook state: pending `0`, `curatorExitBlocked` false |
| 1:20–1:30 | Overview / close | One line: **the curator cannot run** |

Record at 1920×1080, no audio needed, no cursor jitter. **This is the submission's demo link.**
The exact cast commands, selectors and expected values are in §9.2; the rehearsal transcript is
in `docs/15-PROGRESS.md` §13.

---

## 9. Live replay — Base Sepolia (actual numbers)

The seeded live deployment is the proof; the fixture is the polished narrative. If you record
the replay on a fork, the live seed stays intact for Demo Day.

### 9.1 Addresses and starting state

| Item | Value |
|---|---|
| Hook | `0x2B263944982CE27D9C90429C6ccf61B0c37c0f80` |
| Vault | `0xDF5C0a4a4aC83D34EdB73DF3CF3Ca804a49B759F` |
| Keeper | `0x50932de3B04d26910D32ab10654acEecC0Ce5B07` |
| PoolId | `0x5ca84e8f59283a8d9dc4d23ead5f0528735d790f336a01df84bdc80262ceae38` |
| Demo depositor | `0xc96d811952e6f87EFd0ddEDa3b85fe30F768AB5A` |
| Curator / deployer | `0x27A2dD1823D883935c9824fbaC0a018cE8e891E5` |

Starting state: `totalAssets` `7,873,683` (7.873683 USDC), `totalSupply` `8,066,599`, NAV
`0.976084592775716259`, `pendingLiquidity` `0`, depositor liquidity `364,160,580,020`, curator
liquidity `46,536,901,550`, curator bond value `1,000,000`, risk `Normal`. The demo depositor
holds `5.000000` depositor shares; the deployer holds the other `3.066599`. The curator bond is a
**separate** v4 position, not vault shares. The gate does not care who owns the depositor shares.

### 9.2 Replay on a fork (leaves the live seed untouched)

```bash
# Terminal 1
anvil --fork-url "$BASE_SEPOLIA_RPC_URL" --chain-id 84532 --port 8546 --auto-impersonate

# Terminal 2 — use the same cast commands against http://127.0.0.1:8546
V=0xDF5C0a4a4aC83D34EdB73DF3CF3Ca804a49B759F
H=0x2B263944982CE27D9C90429C6ccf61B0c37c0f80
P=0x5ca84e8f59283a8d9dc4d23ead5f0528735d790f336a01df84bdc80262ceae38
D=0xc96d811952e6f87EFd0ddEDa3b85fe30F768AB5A   # demo depositor
C=0x27A2dD1823D883935c9824fbaC0a018cE8e891E5   # curator
R=http://127.0.0.1:8546
```

| Step | Command | Expected |
|---|---|---|
| 1 | `cast send $V 'requestWithdraw(uint256)' 2500000 --from $D --unlocked --rpc-url $R` | claim 0; `pendingLiquidity` `112,860,603,472`; `isCuratorExitBlocked` `true` |
| 2 | `cast send $V 'requestCuratorExit()' --from $C --unlocked --rpc-url $R` | revert `CuratorExitBlocked(112860603472)` |
| 3 | `cast send $V 'settleClaims(uint256)' 10 --from $D --unlocked --rpc-url $R` | claim settled; `2.432727` USDC paid; pending `0`; blocked `false` |
| 4 | `cast send $V 'requestCuratorExit()' --from $C --unlocked --rpc-url $R` | approved |
| 5 | `cast send $V 'curatorExit(uint128)' 46536901550 --from $C --unlocked --rpc-url $R` | curator liquidity `0`; proceeds `1,002,902` (1.002902 USDC) |

Step 2 is the shot. The error selector is `0xb2f9ec04` (`CuratorExitBlocked(int128)`) and the
argument is the outstanding obligation — the hook's own ledger, not the vault's opinion. In the
dashboard, connect the demo wallet for steps 1 and 3, and the curator for steps 2 and 4.

### 9.3 If you record against the live deployment

Do **not** run step 5 on the live deployment before Demo Day: it consumes the seeded curator
bond. For the 90-second clip, stop after step 4, or run the whole sequence on the fork and show
the live dashboard only for the current state. The decoded-revert interaction can also be shown
from `?scenario=blocked`, which is the same component tree with the fixture's numbers.

### 9.4 Pre-flight on the live deployment

Run these immediately before recording. The keeper refresh is permissionless and only affects
the mandate badge; the exit gate is independent of it.

```bash
cd contracts
set -a; . ./.env; set +a

# 1. Refresh the risk evaluation so the mandate panel shows Normal for the next hour.
cast send 0x50932de3B04d26910D32ab10654acEecC0Ce5B07 'performUpkeep(bytes)' 0x \
  --private-key "$DEPLOYER_PRIVATE_KEY" --rpc-url "$BASE_SEPOLIA_RPC_URL"

# 2. Confirm the seed is pristine.
H=0x2B263944982CE27D9C90429C6ccf61B0c37c0f80
V=0xDF5C0a4a4aC83D34EdB73DF3CF3Ca804a49B759F
P=0x5ca84e8f59283a8d9dc4d23ead5f0528735d790f336a01df84bdc80262ceae38
cast call $H 'pendingLiquidity(bytes32)(int128)' $P --rpc-url "$BASE_SEPOLIA_RPC_URL"   # 0
cast call $H 'isCuratorExitBlocked(bytes32)(bool)' $P --rpc-url "$BASE_SEPOLIA_RPC_URL" # false
cast call $H 'curatorExitApproved(bytes32)(bool)' $P --rpc-url "$BASE_SEPOLIA_RPC_URL"  # false
cast call $V 'balanceOf(address)(uint256)' 0xc96d811952e6f87EFd0ddEDa3b85fe30F768AB5A \
  --rpc-url "$BASE_SEPOLIA_RPC_URL"                                                     # 5000000
```

**Retakes.** Each settlement permanently serves `2.5` of the demo wallet's `5.0` shares and
removes the matching assets from the pool. The demo wallet supports **one clean take, then one
more**; after that it has no shares. If you need a third take, transfer shares from the curator
(`0x27A2…`, holds `3.066599`) or redeploy. Rehearse the clicks on a fork before the live take.

Start the dashboard with the production build so the live env is baked in:

```bash
cd dashboard
npm run build && npm run start -- -p 3001   # http://localhost:3001/dashboard
```

---

*Next: `docs/12-VERIFICATION.md`.*
