# 16 — Implementation Notes

> **What the code does, where it differs from the specification, and why.**
>
> The specification in `docs/01`–`docs/08` was written before the code. The code was built
> against Uniswap v4's actual mechanics, and in several places the mechanics forced the design
> to change. This document is the honest record of those changes.
>
> **Nothing here is optional reading.** If you are reviewing Skyline, read this alongside
> `docs/03-ARCHITECTURE.md`.

---

## 1. Summary of the deltas

| # | Area | Spec said | Code does | Why |
|---|---|---|---|---|
| D1 | Ledger decrement | A vault calls `hook.settleClaim(...)` | The hook decrements **inside `afterRemoveLiquidity`**, from the removal it observes | Strictly stronger: the ledger cannot be decremented without real liquidity leaving the pool |
| D2 | Loss absorption | Denominated in **liquidity units** | Denominated in the vault's **asset** (owed − paid) | A liquidity-unit shortfall is impossible by construction; the real loss is a *value* loss when the strategy degrades |
| D3 | Two-sided positions | Not addressed | Each deposit swaps **half** into the pool's other currency | A concentrated position straddling the price needs **both** currencies; a single-asset vault cannot fund it otherwise |
| D4 | Claim TTL | Ambiguous | The TTL is an **expiry** only. Settlement is immediate | A depositor who asks to leave must not be made to wait a day |
| D5 | Minimum skin | Applied to every modification | Applies once a bond exists; **exempts a full curator exit** | Otherwise the curator could never leave, and a depositor's first deposit would be rejected |
| D6 | Hook base | `uniswap-hooks` package | A hand-written `SkylineBaseHook` against `v4-core@v4.0.0` | The published package tracks a newer v4-core whose `ModifyLiquidityParams` lives in a different module |
| D7 | Pool bootstrap | Not addressed | The deployer must seed the pool with a third-party position | A fresh pool has no liquidity, so the first swap crashes the price to the limit |
| D8 | Exit approval | The vault's approval is the gate | The hook's ledger is the gate; approval is necessary but never sufficient | The whole point of the thesis |

---

## 2. D1 — the ledger is decremented by observed pool events

**Spec (`docs/03` §4):** `hook.settleClaim(poolId, claimId, liquidityRemoved)` is called by the
vault, and the hook "verifies" it.

**Code:** there is no `settleClaim`. The hook decrements `pendingLiquidity` inside
`_afterRemoveLiquidity`, using the `liquidityDelta` of the removal the PoolManager just
performed.

```solidity
// SkylineHook._afterRemoveLiquidity
(uint256 claimId, bool isSettlement) = SkylineTypes.decodeSettlement(hookData);
if (isSettlement) {
    int128 removed = liquidityDelta < 0 ? -liquidityDelta : 0;
    _applySettlement(poolId, claimId, removed);
}
```

**Why this is better.** A v4 position is keyed by `(owner, tickLower, tickUpper, salt)` with
`owner = msg.sender` at the PoolManager. Only the registered vault can remove the vault's
liquidity, so a decrement can only ever follow real liquidity leaving the pool. The
"corroboration" check the spec asked for is not needed as a separate step — it is structural.

`hookData` is used only to say **which** claim the removal was for. It never authorises
anything: the hook still checks that the claim exists, is open, and that the removed amount
does not exceed the claim's outstanding remainder.

---

## 3. D2 — loss absorption is denominated in the vault's asset

**Spec (`docs/04` §3):** the ladder is "depositor liquidity → curator bond → pro rata", with
the shortfall measured in **pool liquidity units**.

**Problem discovered in implementation.** A liquidity-unit shortfall is *impossible by
construction*: a claim is sized from the depositor's own share of the position, so the total of
all claims can never exceed the depositor liquidity. The third stage of the ladder could never
fire.

**What actually goes wrong is a value loss.** A claim promises a depositor a value. If the
strategy degrades between registration and settlement, the liquidity removed is worth less than
it was promised. That difference is the loss, and it is measured in the vault's asset.

**Code.** The claim records both sides:

```solidity
struct ClaimRecord {
    uint256 shares;
    uint128 liquidityAmount;   // pool liquidity units owed
    uint128 settledLiquidity;  // pool liquidity units delivered
    uint256 assetsOwed;        // the asset value promised at registration
    uint256 assetsPaid;        // the asset value actually delivered
    address depositor;
    uint64 createdAt;
    uint8 status;
}
```

At settlement:

```solidity
if (c.assetsOwed > c.assetsPaid) {
    uint256 shortfall = c.assetsOwed - c.assetsPaid;
    uint256 consumed = shortfall < curatorBondValue ? shortfall : curatorBondValue;
    curatorBondValue -= consumed;
    uncoveredShortfall += consumed;
    emit ShortfallAbsorbed(curator, consumed, uncoveredShortfall);
}
```

and the curator's exit proceeds are netted by `uncoveredShortfall`.

**Consequence worth stating honestly.** The bond also covers the vault's own execution cost —
the swap that converts the position's second currency back into the asset the vault pays in.
In the test suite that residual is ~14 bps on an undisturbed pool. It is charged to the bond
because the bond is the protocol's loss-absorbing capital. If you would rather the vault
absorbed its own costs, that is a one-line change — but then the bond is strictly smaller and
the curator's alignment is weaker.

---

## 4. D3 — deposits fund a two-sided position

**Spec:** silent.

**Code.** A concentrated position that straddles the price needs both pool currencies. A
single-asset vault receives only its own asset. So each deposit is split:

```
swapIn   = assets / 2          → swapped into the pool's other currency
token0   = assets - swapIn     → funds the currency0 side
liquidity = min(token0 / cost0, token1Held / cost1) × margin
```

The liquidity is sized against what the vault can actually pay for on **both** sides, with a
2% margin, so the vault never promises liquidity it cannot fund.

**Consequence.** The vault holds a small balance of the pool's second currency as a surplus. It
is never counted in `totalAssets()` — the vault values its position in its own asset only.
`docs/04` §"ACCOUNTING MODEL" is now accurate about this.

---

## 5. D4 — the claim TTL is an expiry, not a delay

**Spec (`docs/03` §6.3):** ambiguous — it read as though settlement might wait for the TTL.

**Code:** `settleClaims` serves any registered claim immediately. The TTL (`claimTtl`, default
1 day) governs only **expiry**: an unsettled claim is cancelled after the TTL and the
depositor's shares are restored.

This is the right behaviour. A depositor who asks to leave must not be told to wait a day for
their own money.

---

## 6. D5 — the minimum-skin rule

**Spec:** stated without edge cases.

**Code:**

```solidity
// On an ADD
bool isCuratorAdd = params.salt == CURATOR_SALT;
bool hasBond = curatorLiquidity[poolId] != 0;
if (hasBond || isCuratorAdd) { /* enforce */ }

// On a REMOVE, the curator's exit
int128 postCurator = curatorLiquidity[poolId] + delta;
int128 postTotal = curatorLiquidity[poolId] + depositorLiquidity[poolId] + delta;
if (postCurator != 0 && postTotal != 0) { /* enforce */ }
```

Two edge cases the spec did not cover, both discovered by failing tests:

- **A depositor's first deposit must not be rejected.** Before the curator has bonded there is
  no skin to protect, so the check is skipped until a bond exists.
- **A full curator exit must not be rejected.** `postCurator == 0` skips the check, because the
  rule constrains a curator who *remains* in the pool, not one who leaves with an empty ledger.

---

## 7. D6 — the hook base is hand-written

**Spec (`docs/14` §2):** `uniswap-hooks` package.

**Problem.** `Uniswap/v4-hooks-public` (which publishes the `uniswap-hooks` package) imports
`ModifyLiquidityParams` from `@uniswap/v4-core/src/types/PoolOperation.sol`, which does not
exist in the released `v4-core@v4.0.0` — there the struct lives inside `IPoolManager`. The two
cannot be combined.

`Uniswap/hooks` no longer exists (404). `Uniswap/v4-hooks-public` has **no tags**, so there is
no release that matches `v4.0.0`.

**Code.** `src/SkylineBaseHook.sol` implements `IHooks` directly against `v4-core@v4.0.0` —
about 120 lines, including the permission-flag validation at construction. This removes a
dependency whose release cadence does not match the core it must compile against.

**Bonus:** the base exposes a virtual `validateHookAddress`, which is what lets the test
harness deploy the implementation at an arbitrary address and etch its bytecode onto a
permission-correct one.

---

## 8. D7 — the pool needs bootstrap liquidity

**Spec:** silent.

**Problem.** The vault's first deposit swaps half its capital into the pool's other currency. On
a pool with **no** liquidity, that swap walks the price to the limit and the transaction
reverts with `PriceLimitAlreadyExceeded`.

**Code.** The deployer seeds the pool with a third-party position (salt `0`) before any vault
activity. Real pools are seeded by their creator; Skyline does the same. The bootstrap is
deliberately outside Skyline's two managed positions and is invisible to the hook's ledgers.

The test fixture uses `BOOTSTRAP_LIQUIDITY = 1e29` so that the vault's own swaps do not move
the price materially — otherwise the vault's execution cost (and therefore the residual
shortfall) is dominated by price impact rather than by the fee.

---

## 9. D8 — the exit gate lives in the hook, not the vault

**Spec:** already correct in principle, and the code makes it literal:

- `hook.approveCuratorExit` reverts with `CuratorExitBlocked(pending)` when the ledger is not
  empty. The curator's exit *request* is refused.
- `hook.beforeRemoveLiquidity` independently rejects the **removal** if a claim arrives after
  the approval was granted. The vault's `curatorExitRequested` flag is still set, so the
  curator's removal reaches the PoolManager and is rejected there.

The second path is the one that matters, and it is proven in
`test/unit/ClaimLedger.t.sol::test_curatorRemovalIsBlockedEvenWhenTheExitWasApproved`, which
asserts the **full wrapped error** — proving the block came from the hook, at the
`beforeRemoveLiquidity` callback, below the vault.

---

## 10. Uniswap v4 mechanics that the spec got wrong

These were corrected against the `v4.0.0` source and are worth recording, because they are
easy to get wrong.

| Fact | Correction |
|---|---|
| `SwapParams.amountSpecified` | **Negative = exact input**, positive = exact output. The spec assumed the opposite. |
| The delta returned by `modifyLiquidity` / `swap` | **Positive = the caller RECEIVED** tokens; negative = the caller owes. The spec's `_settleDelta` had the signs inverted. |
| Settlement order | `sync(currency)` → transfer in → `settle()`. The spec's `transfer` → `sync` → `clear` is wrong. `clear` requires the transient delta to equal the amount exactly and is not the user-facing path. |
| `IPoolManager` getters | There are **none**. Everything is `StateLibrary` (`extsload`/`exttload`). `poolManager.getSlot0(...)` does not compile. |
| `getSlot0` return | Four values: `(sqrtPriceX96, tick, protocolFee, lpFee)`. |
| `PoolId` | `keccak256(abi.encode(poolKey))` — `abi.encode`, not `abi.encodePacked`. |
| Position key | `keccak256(abi.encodePacked(owner, tickLower, tickUpper, salt))` — **packed**, and the owner is part of it. |

---

## 11. Things the spec promised that are NOT implemented

Honesty list. None of these are load-bearing for the thesis, and each is a candidate for the
remaining time before 3 December.

| Promised | Status | Priority |
|---|---|---|
| `CuratorRegistry` (Phase 6) | **Not implemented.** The vault holds the curator address. | Low — the dashboard can read the curator from the vault |
| `SkylineFactory` (Phase 6) | **Not implemented.** The deploy script wires the pieces directly. | Low |
| `migrate()` between vaults | **Removed** from the shipped surface; cross-vault migration is out of scope. | — |
| Chainlink integration (Phase 7) | **Implemented and tested**: `IChainlinkFeed`, `updateRiskState`, `effectiveRiskState`, risk-gated curator actions, `test/Oracle.t.sol` (21 tests). Wired to the Base Sepolia ETH/USD feed by the deploy script; not yet exercised against the live feed. | Done except live-feed verification |
| Performance fee **forfeiture** on a detected drawdown breach | **Implemented.** `accruePerformanceFee` detects `Breached`, forfeits the epoch's fee, ratchets the HWM and emits `PerformanceFeeForfeited`. | Done |
| `performRebalance` | **Removed** from the shipped surface; the mandate fixes the pool and range. | — |
| `mgmtFeeBps` | Declared, never used. | None — remove it |
| Pro-rata third stage of the ladder | **Implemented** (`proRata` branch in `settleClaims`) but the branch is hard to reach and is not exercised by a test. | Low |
| Fork tests against a live testnet PoolManager | **Not written.** | High if time permits — the strongest remaining proof |

---

## 12. Test coverage as shipped

| Suite | Tests | Status |
|---|---|---|
| `test/unit/Primitives.t.sol` | 8 | Phase 0 — the v4 mechanics, plus deposit pricing |
| `test/unit/ClaimLedger.t.sol` | 17 | Phase 2 — the ledger, the gate, expiry, limits |
| `test/unit/ExitLadder.t.sol` | 8 | Phase 4 — the demo script |
| `test/Oracle.t.sol` | 21 | Phase 7 — every feed failure mode, HWM ratchet, breach confirmation, keeper, fuzzed INV-5 |
| `test/invariant/Cep.t.sol` | 7 invariants | 2,000 runs × 100,000 calls each, 0 reverts |
| **Total** | **61** | All green |

**Commands:**

```bash
forge test                                            # everything
forge test --match-path "test/unit/*.t.sol"           # fast
FOUNDRY_PROFILE=ci forge test --match-path "test/invariant/Cep.t.sol"   # 10,000 runs
```

---

## 13. Known limitations to disclose on stage

1. **The vault's positions are funded by a swap.** A single-asset vault holding a two-sided
   concentrated position must convert. The conversion cost is real and small.
2. **The bond covers the vault's execution costs** as well as the strategy's losses.
3. **The strategy is not modelled.** Skyline enforces ordering; it does not decide whether a
   strategy is good.
4. **Single pool per vault.** The ledger is keyed by `PoolId`, so the architecture allows more.
5. **The contracts are unaudited.** What exists is an invariant suite, not an audit.
6. **Residual idle balances are outside NAV.** `totalAssets()` values the deployed positions,
   not the vault's loose balances. Improved sizing keeps idle below ~0.3% in the demo; a
   production version should sweep it into the position or count it and pay claims from it
   (`docs/16` §14.5).

---

## 14. Defects found by running the deploy path (20 November 2026)

`script/Deploy.s.sol` had never been executed. Running it end-to-end found five defects the
unit suite could not see. All are fixed; §14.6 records the verification.

### 14.1 The salt miner could never have found a salt

Two independent faults:

- the loop hashed `salt` (still zero) instead of `candidate`, so every iteration produced the
  same address;
- the predicate was `predicted & ~HOOK_FLAGS == 0`, which requires all 155 bits outside the
  five permission bits to be zero — a 2^-155 event.

The correct predicate is `(predicted & 0x3fff) == HOOK_FLAGS`, a 1-in-16,384 event. Mining
2,000,000 candidates leaves a wide margin.

### 14.2 Foundry broadcasts CREATE2 through the deterministic deployment proxy

Even with the predicate fixed, the mined salt produced the wrong on-chain address and the
hook's constructor reverted with `HookAddressNotValid(0x61F0…)`. A `CREATE2` opcode cannot be
put in a transaction, so `forge script --broadcast` sends `new C{salt: …}` to the deterministic
deployment proxy at `0x4e59b44847b379578588920cA78FbF26c0B4956C`, which performs the create.
The resulting address is derived from the proxy, not the EOA. `_mineSalt` now mines against
that deployer and documents why.

### 14.3 The PoolManager does not fit under EIP-170 at the default optimizer settings

At the project default (`optimizer_runs = 1_000_000`) the vendored `PoolManager` compiles to
26,947 bytes. `forge script` simulates the deployment successfully and then refuses to
broadcast, because EIP-170 caps runtime code at 24,576 bytes. A `[profile.deploy]` with
`optimizer_runs = 200` brings the stack to: PoolManager 19,725, SkylineVault 19,311,
SkylineHook 15,729. Every deployment command now uses `FOUNDRY_PROFILE=deploy`.

### 14.4 A second depositor was diluted by 28%

`_previewDeposit` priced a deposit as

    assets * supply / (totalAssets() + assets)

But `totalAssets()` values only deployed liquidity, and the incoming assets are transferred
*after* the preview, so they were counted twice: once because they are about to be deployed
and once because they are already "in" the denominator. In the demo scenario the second
depositor received 190,090 shares for 300,000 assets, worth 215,576 immediately — an instant
28% loss, funded by the first depositor's gain.

Fixed to `assets * supply / totalAssets()`. The regression test
`test_depositIsPricedAtPreDepositNav` asserts the minted shares equal `convertToShares(assets)`
at the pre-deposit NAV, and that the depositor's value survives within a loose bound.

### 14.5 A flat 50/50 swap left up to 13% of the deposit idle — and NAV did not see it

The vault swapped exactly half of every deposit into the other currency. A concentrated
position does not want half of each currency: away from the range midpoint it wants more of
one side. The excess stayed in the vault as an idle balance, and `totalAssets()` values only
`depositorLiquidity`, so the depositor's NAV silently fell.

In the first seeded local deployment, 800,000 of deposits were marked at 693,823 (NAV 0.825), and the
second depositor was priced at 1.578 NAV. The vault was also holding 105,034 currency1 that
belonged to depositors and was invisible to the share price.

Fixed by sizing the position against the whole deposit first, swapping only the currency0 the
position does not need, then re-sizing against the post-swap price. Deposits now mark at
796,859 for 800,000 (NAV 0.9946); the residual is the 30 bp pool fee on two swaps.

**Still open:** `totalAssets()` continues to exclude any residual idle balance. The fixed
sizing keeps it below ~0.3% in the demo (about 2,400 of 800,000), but a production version
should either sweep idle into the position or include it in NAV and teach settlement to pay
from it. This is listed in §13 rather than hidden.

### 14.6 Verification

Local anvil, chain id 31337. Artifact: `contracts/deployments/31337.json`.

| Step | Result |
|---|---|
| Deploy + seed | 800,000 deposited, 200,000 bonded, NAV 0.9946 |
| `requestCuratorExit()` with no claims | approved |
| `requestWithdraw(50% of shares)` | 66,507,846,997,809,853,769,525,799 liquidity units recorded; approval revoked |
| `curatorExit(all)` | reverted with `WrappedError(hook, beforeRemoveLiquidity, CuratorExitBlocked(pending), HookCallFailed)` |
| `settleClaims(10)` | paid the depositor; pending 0; claim `Settled` |
| re-request after the 1 hour cooldown, `curatorExit(all)` | succeeded; `curatorLiquidity` 0 |

The revert is the exact wrapper asserted by
`test_curatorRemovalIsBlockedEvenWhenTheExitWasApproved`, now reproduced against a real chain
rather than only in a Foundry test.

---

## 15. D9 — the risk regime freezes risk-increasing curator actions only (20 November 2026)

`docs/05-SECURITY.md` §6 and the original `docs/10-CHAINLINK.md` §3 said `Restricted` freezes
"curator operations", listing "no exit" among them. `docs/05` also says a curator is never
punished merely for LPs withdrawing. Those two statements conflict, and the code resolves the
conflict in favour of not trapping curator capital:

| Action | `Normal` | `Restricted` | `Breached` |
|---|---|---|---|
| Depositor deposit / request / settle / pro-rata | allowed | allowed | allowed |
| Curator **exit** (subject to the CEP gate) | allowed | **allowed** | **allowed** |
| `curatorDeposit`, liquidity adds | allowed | **blocked** | **blocked** |
| Performance fee accrual | normal | normal | **forfeited** |

The rationale: freezing an exit is not a risk control, it is a punishment, and it would trap the
curator's own capital indefinitely. Freezing *increases* is a genuine risk control. The lock
that matters — CEP — is separate, is released by settlement, and does not depend on the risk
state.

### 15.1 D10 — the drawdown mark is external, not NAV

The spec proposed measuring drawdown on `navPerShare` (docs/10 §5). The implementation measures
it on the Chainlink mark against a high-water mark of that mark. Reasons:

- the NAV is derived from pool state and vault accounting; using it as the risk input makes the
  regime a function of the thing it constrains;
- a curator can move NAV by depositing or rebalancing, but cannot move the external mark;
- the mark is a single, auditable, externally published number, which is what a sponsor prize
  expects to see consumed.

The cost is that the mark reflects the volatile leg (ETH/USD for a USDC/WETH pool), not the
vault's exact asset mix. That is disclosed in `docs/10` §5 and §9.
