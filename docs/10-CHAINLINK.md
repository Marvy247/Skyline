# 10 — Chainlink Integration

> Chainlink supplies **external information, never permission**. The exit restriction keeps
> working if the oracle or the automation service is unavailable.

---

## 1. Why Chainlink, and what it is *not* for

The obvious use of an oracle in a liquidity protocol is valuation. Skyline deliberately does not
use it that way, for one reason:

> **A stale, frozen, or manipulated price feed must never be able to trap a depositor's capital.**

So Chainlink is confined to **curator risk parameters**. It can tighten what the curator may do.
It can never gate an exit.

| Chainlink product | Role | On the exit path? |
|---|---|---|
| **Price Feeds** | Reference mark for the strategy's drawdown | **No** |
| **Data Streams** | Higher-frequency mark where a feed is too slow | **No** |
| **Automation** | Periodic claim settlement + risk-state refresh | **No** — both functions are permissionless |

The integration is not decorative. Three things in the shipped contracts depend on it:

1. `SkylineHook.updateRiskState` reads the feed, computes the drawdown against a high-water
   mark, and writes `RiskState`.
2. `SkylineHook.effectiveRiskState` turns a stale or never-run evaluation into `Restricted`,
   which the hook and the vault use to reject risk-increasing curator actions.
3. `SkylineKeeper` implements Chainlink Automation's `checkUpkeep` / `performUpkeep` so the
   regime is refreshed and claims are served without a human.

---

## 2. Which product for which prize track

We could not confirm UHI11's live sponsor list (see `docs/12-VERIFICATION.md` §5). Ask in the
Discord before writing sponsor-specific claims. What is built covers the two plausible asks:

| If the prize track wants… | We ship | Note |
|---|---|---|
| A price reference | **Price Feeds** | Base Sepolia ETH/USD, wired by default for a USDC/WETH pool |
| A high-frequency mark | **Data Streams** | The `IChainlinkFeed` surface is the standard `latestRoundData()`; a Data Streams adapter can implement it |
| Periodic execution | **Automation** | `SkylineKeeper` is `IAutomationCompatible` |
| Proof of reserve | Not applicable | We have no reserves to prove |

**Shipped MVP:** one price feed on Base Sepolia, one drawdown calculation, one hook read, one
Automation-compatible keeper. No oracle read on the swap path.

---

## 3. The risk state

```solidity
enum RiskState { Normal, Restricted, Breached }
```

| State | Condition | Effect |
|---|---|---|
| **Normal** | drawdown < `maxDrawdownBps` | Full curator authority within the mandate |
| **Restricted** | drawdown ≥ `maxDrawdownBps`, **or** the feed is unavailable/stale, **or** the evaluation is older than `RISK_STATE_MAX_STALENESS` | **Risk-increasing** curator actions frozen: `curatorDeposit`, liquidity adds, `performRebalance`. Curator **exit remains available**, subject to the exit gate. Depositor actions unaffected. |
| **Breached** | drawdown ≥ 2 × `maxDrawdownBps` on **two consecutive** evaluations | As Restricted, **plus** the performance fee is forfeited for the epoch. The bond is already exposed to outstanding claims by the exit ladder; the breach does not create a new slashing path. |

### 3.1 Locking is not slashing, and restriction is not punishment

Three distinct mechanisms, deliberately kept separate:

- **The exit gate** (CEP) blocks a curator removal only while depositor claims are outstanding.
  It is released by settlement, not by good behaviour.
- **The risk regime** freezes *risk-increasing* curator actions. It never traps the curator's
  capital: an exit is risk-reducing and stays available once the exit gate is clear.
- **Fee forfeiture** is the only economic penalty, and it is triggered only by a confirmed
  breach. It removes a fee; it does not touch principal.

Depositors are never restricted by any of them. Ever.

### 3.2 Why a single extreme print cannot breach

A manipulated or fat-fingered print must not be able to forfeit a curator's fee. The first
observation at ≥ 2 × the limit escalates to `Restricted` and increments `breachObservations`.
Only the second **consecutive** observation reaches `Breached`. A recovery in between resets the
counter. The parameter is `BREACH_CONFIRMATIONS = 2`.

---

## 4. Degradation behaviour (the important part)

**The rule: the risk state may only degrade toward more restrictive, never toward less.**

| Oracle condition | Behaviour |
|---|---|
| Returns a positive, fresh price in a complete round | Compute the drawdown normally |
| Returns `0` or a negative price | `_readMark` returns `ok = false` → escalate to `Restricted` |
| `updatedAt == 0` | Treat as unavailable → `Restricted` |
| `updatedAt` older than `RISK_STATE_MAX_STALENESS` (1 hour) | Treat as unavailable → `Restricted` |
| `answeredInRound < roundId` (incomplete round) | Treat as unavailable → `Restricted` |
| The call reverts | **Caught.** Never bubbles. → `Restricted` |
| An existing `Breached` and a failed read | Stays `Breached`; failure never relaxes |
| The stored evaluation is stale, or has never run, while an oracle is configured | `effectiveRiskState` returns `Restricted` |
| `oracle == address(0)` | No monitor configured. `effectiveRiskState` returns the stored state; the UI says "no oracle". |

### 4.1 The hook must never revert because of an oracle read

```solidity
function _readMark(PoolId poolId) internal view returns (uint256 price, bool ok) {
    address oracle = _poolConfigs[poolId].oracle;
    if (oracle == address(0)) return (0, false);

    try IChainlinkFeed(oracle).latestRoundData() returns (
        uint80 roundId, int256 answer, uint256, uint256 updatedAt, uint80 answeredInRound
    ) {
        if (answer <= 0) return (0, false);
        if (updatedAt == 0) return (0, false);
        if (block.timestamp > updatedAt && block.timestamp - updatedAt > RISK_STATE_MAX_STALENESS) {
            return (0, false);
        }
        if (answeredInRound < roundId) return (0, false);
        return (uint256(answer), true);
    } catch {
        return (0, false);
    }
}
```

A hook that reverts on a bad oracle read can brick a pool. That is the failure mode we are
avoiding. The subtraction is guarded so an untrusted future timestamp cannot overflow.

### 4.2 When is the risk state computed?

**Push, via a keeper, with a staleness floor.** `updateRiskState(poolId)` is permissionless and
stores `riskState` and `riskStateUpdatedAt`. `effectiveRiskState(poolId)` is a view that the
enforcement points read:

```
stored Breached                    -> Breached
stored Restricted                  -> Restricted
oracle unset                       -> stored (no monitoring configured)
never evaluated / older than 1h    -> Restricted
otherwise                          -> stored
```

That gives the failure-safe combination without paying for an oracle read on every swap: a
keeper that stops running does not leave the pool open, it leaves the curator restricted.
Depositor exits never call this function.

### 4.3 Escalation is monotone within a failure

`updateRiskState` recomputes the state from the stored mandate and the mark. A failed read
*raises* the state to at least `Restricted`; it never lowers it. A confirmed breach is only
cleared by a successful read with a drawdown below the limit — and because the reference price
is a high-water mark, a recovery raises the reference rather than lowering it.

---

## 5. Drawdown calculation

The drawdown is measured on the **external mark**, against that mark's own high-water mark:

```solidity
if (price > refPrice) refPrice = price;                 // ratchet, never falls
uint256 drawdownBps = price >= refPrice
    ? 0
    : ((refPrice - price) * 10_000) / refPrice;
```

The reference is stored in `referencePrice[poolId]`. The first successful observation
establishes it; subsequent observations only raise it. A decline is measured from the peak, not
from inception, so a strategy that rose 50% and fell 20% is in a 20% drawdown — not a 20%
gain.

**What the mark measures.** For a USDC/WETH pool on Base Sepolia the feed is ETH/USD. The risk
state therefore reflects a large, liquid, externally observed move in the volatile leg of the
position, which is the dominant source of directional drawdown for a concentrated range. It is
not a mark-to-market of the vault's NAV, and we do not claim it is.

**Why not NAV?** The vault's own `navPerShare` is already an accounting output, and using it as
the risk input would make the regime a function of the thing it is supposed to constrain.
Keeping the input external means a curator cannot move the risk state by depositing, withdrawing
or rebalancing.

**Be precise on stage.** Say: *"the mark informs the risk regime that constrains the curator;
the depositor's exit path never consults it."*

---

## 6. Automation

`src/SkylineKeeper.sol` implements the published `IAutomationCompatible` surface:

```solidity
function checkUpkeep(bytes calldata) external view returns (bool upkeepNeeded, bytes memory performData);
function performUpkeep(bytes calldata) external;
```

**What it does:**

1. `checkUpkeep` reports work when the stored risk evaluation is older than
   `RISK_STATE_MAX_STALENESS`, or when `vault.outstandingClaims() != 0`.
2. `performUpkeep` refreshes the risk state if due, then calls `vault.settleClaims(maxClaimsPerRun)`
   inside a `try/catch`.

**What it must not do:** be a dependency.

- `hook.updateRiskState` is permissionless.
- `vault.settleClaims` is permissionless.
- `performData` is **ignored**. It is an untrusted hint; the keeper re-reads authoritative
  state, so a forged hint cannot skip a check or authorise anything.
- The keeper only ever tightens the regime and serves claims. It cannot touch curator liquidity,
  the mandate, or the oracle address.

**Demo consideration:** a live Automation task on a free tier may not be reliable enough to
depend on for Demo Day. Present it as "settlement and risk refresh are permissionless;
Automation just does them for us", and demonstrate the permissionless path. That framing is
stronger, not weaker.

---

## 7. Testing

`test/Oracle.t.sol` — 21 tests, including a 10,000-run fuzz of INV-5:

| Input | Assertion |
|---|---|
| `answer = 0` | State escalates to `Restricted`; **no revert** |
| `answer < 0` | State escalates to `Restricted`; **no revert** |
| `updatedAt` far in the past | State escalates to `Restricted`; **no revert** |
| `updatedAt == 0` | Treated as unavailable; **no revert** |
| `answeredInRound < roundId` | Treated as unavailable; **no revert** |
| The feed reverts | State escalates to `Restricted`; **no revert** |
| A 50% single print | `Restricted` only; `breachObservations == 1` |
| Two consecutive extreme prints | `Breached`; fee forfeited |
| Failure after a breach | Stays `Breached` |
| `oracle = address(0)` | Stored state preserved; curator can operate |
| Stale evaluation | `effectiveRiskState == Restricted`; curator add reverts, depositor exit settles |
| Keeper | `checkUpkeep` true when due; `performUpkeep` refreshes and settles; keeper never required |

**The headline assertion (INV-5):** across every one of those cases, a depositor can still
request a withdrawal and still be settled. This is fuzzed over `(answer, staleness, revertFeed)`,
not asserted by hand.

```bash
forge test --match-path test/Oracle.t.sol
```

---

## 8. Failure-mode table for the submission

| Failure | Effect on the protocol | Effect on a depositor's exit |
|---|---|---|
| Feed returns zero | Risk state → `Restricted` | **None** |
| Feed is stale / incomplete | Risk state → `Restricted` | **None** |
| Feed reverts | Risk state → `Restricted` | **None** |
| Feed manipulated | `Restricted` at once; `Breached` only after 2 confirmations | **None** |
| Keeper stops | `effectiveRiskState` → `Restricted` for curator adds; settlement still permissionless | **None** |
| Oracle never configured | Stored state; no drawdown protection, disclosed in the UI | **None** |
| Hook paused (if ever paused) | — | Must still be possible; **never add a global pause** |

**Never add a global pause to this hook.** It would be the single line of code that could violate
R7 (no depositor lockout). The only emergency mechanism is scoped to *risk-increasing curator
operations*, and it expires toward restriction rather than toward permissiveness.

---

## 9. What we claim, and what we do not

**We claim:**
- Chainlink Price Feeds provide the external mark used to compute the curator's drawdown.
- The regime restricts **risk-increasing curator** operations and nothing else.
- The regime never restricts depositor exits, in any state, including every oracle failure mode.
- A stale evaluation degrades toward `Restricted`, not toward permissiveness.
- The protocol degrades safely when the oracle fails, and the exit gate works with no oracle at
  all.
- Chainlink Automation is integrated through a real `IAutomationCompatible` keeper, and is
  optional by construction.

**We do not claim:**
- That Chainlink validates the strategy.
- That the price feed is used to value the depositors' positions (the vault's own accounting does
  that).
- That the feed measures the vault's NAV; it measures the volatile leg's external price.
- That Automation is required for settlement or for the risk regime to be safe.

---

*Next: `docs/11-DEMO.md`.*
