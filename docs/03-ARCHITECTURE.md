# 03 — Architecture

> The design contract between the spec and the implementation. If the code and this document
> disagree, one of them is a bug. Read `docs/05-SECURITY.md` before changing anything here.

---

## 1. Design in one paragraph

A **vault** holds two Uniswap v4 positions in the strategy pool — depositor capital under
`salt = LP_SALT` and the curator's bond under `salt = CURATOR_SALT`. A **hook** watches every
liquidity modification at the PoolManager, maintains its own ledger of outstanding depositor
withdrawal obligations, and rejects any removal of curator-bonded liquidity while those
obligations are unsettled. Depositors exit by registering claims that are served FIFO from
depositor liquidity; where depositor liquidity cannot cover a claim, the curator's bond
absorbs the shortfall under an arithmetic condition the hook verifies itself. The hook also
enforces the curator's committed mandate: fee cap, tick band, minimum skin, and a risk state
derived from an external mark.

---

## 2. Contract inventory

| # | Contract | Kind | Responsibility |
|---|---|---|---|
| 1 | `SkylineHook` | `BaseHook` | Owns the obligation ledger, the shadow-liquidity ledgers, the mandate, the risk state, the fee cap. **The only authority on ordering.** |
| 2 | `SkylineVault` | ERC-4626-ish | Depositor accounting (shares, NAV), claims, settlement, curator bond accounting, performance fee, migration. Holds the two pool positions. |
| 3 | `CuratorRegistry` | registry | Curator registration, mandate publication, bond address, fee recipients, reputation record (post-MVP). |
| 4 | `SkylineFactory` | factory | Deploys a hook + vault pair per strategy pool, wires the manifest. |

**MVP scope:** contracts 1 and 2 are mandatory. 3 and 4 are strongly preferred (a registry makes
the dashboard and the demo much stronger); if time is short, fold registration into the vault
and ship a single-file deployment.

### 2.1 Why the hook is not "a hook attached to a vault"

| Property | Consequence |
|---|---|
| The hook owns `pendingLiquidity[poolId]` | The vault is never asked whether claims exist. The hook answers from its own state. |
| The hook maintains shadow liquidity counters derived from observed pool events | The curator's bond balance and the settlement amount are verifiable from pool state, not from vault bookkeeping. |
| The hook gates by `salt` at the PoolManager | A different router, an aggregator, or a buggy vault cannot route around it. |
| The hook's permission flags cover add/remove liquidity | The mandate is enforced where liquidity actually changes, not in a policy layer above it. |

---

## 3. The two positions

### 3.1 Position keys

v4 position identity is:

```
positionKey = keccak256(abi.encodePacked(owner, tickLower, tickUpper, salt))
```

Skyline exploits the `salt` component, which v4 defines as *"a value to set if you want unique
liquidity positions at the same range"*.

| Position | Owner | Salt | Contents |
|---|---|---|---|
| Depositor position | `SkylineVault` | `LP_SALT` | All depositor capital, the active strategy position |
| Curator bond position | `SkylineVault` | `CURATOR_SALT` | The curator's bonded capital |

Both are owned by the vault, because the vault must be able to force the bond to absorb a
shortfall **without the curator's cooperation**. The curator's ownership of that capital is an
*economic* claim recorded in vault accounting — and, critically, one that anyone can verify
independently from pool state (§6.4). The curator cannot be silently diluted.

### 3.2 Salts

```solidity
bytes32 public constant LP_SALT      = keccak256("SKYLINE.LP_SALT.v1");
bytes32 public constant CURATOR_SALT = keccak256("SKYLINE.CURATOR_SALT.v1");
```

Use **versioned** salt strings. Changing the salt convention later must not silently collide
with old positions.

### 3.3 Tick ranges

Depositor and curator positions share the strategy's tick range by default — they are two
positions in the same range with different salts. Fee growth accrues independently per position
key, so the curator's fee income is separable and auditable.

Rebalancing moves **both** positions together (the curator's bond follows the strategy) — unless
the mandate explicitly permits the curator's bond to sit in a different range, which the MVP
does not support.

> **Do not** use different tick ranges for the two positions in the MVP. It fragments the
> price-impact story and complicates the min-skin check. Note it in `docs/13-RISKS.md` R-06.

---

## 4. The hook's ledgers

All keyed by `PoolId`. **Never global.** A claim in pool A must not lock a curator's exit in
pool B.

### 4.1 Authoritative ledger

```solidity
mapping(PoolId => int128) public pendingLiquidity;      // outstanding depositor obligations
mapping(PoolId => uint256) public nextClaimId;
mapping(PoolId => mapping(uint256 => Claim)) public claims;
```

`Claim`:

```solidity
struct Claim {
    uint128 liquidityAmount;   // pool liquidity units owed
    uint128 settledAmount;     // pool liquidity units already delivered
    uint64  registeredAt;
    uint64  expiresAt;
    uint8   status;            // 0 = none, 1 = registered, 2 = settled, 3 = expired, 4 = partially settled
    address depositor;
}
```

`pendingLiquidity[poolId]` is **liquidity-denominated, not a count**. It is the sum over
non-settled claims of `(liquidityAmount - settledAmount)`.

Why liquidity and not token amounts: claims are served by *removing liquidity*, and the amount
of liquidity required to satisfy a token claim depends on the price at settlement. Denominating
in liquidity makes the ledger independent of price and makes partial settlement natural.

### 4.2 Shadow liquidity ledger

```solidity
mapping(PoolId => int128) public curatorLiquidity;      // sum of CURATOR_SALT positions
mapping(PoolId => int128) public depositorLiquidity;    // sum of LP_SALT positions owned by the vault
```

Maintained **exclusively from observed pool events** in `afterModifyLiquidity`:

```
curatorLiquidity[poolId]   += (salt == CURATOR_SALT) ? liquidityDelta : 0
depositorLiquidity[poolId] += (salt == LP_SALT)      ? liquidityDelta : 0
```

This gives three things for free:

1. **Settlement verification** — a claim can only be marked settled if the shadow counter
   actually fell by the claimed amount (§6.2).
2. **Minimum-skin enforcement** — the ratio `curatorLiquidity / (curatorLiquidity + depositorLiquidity)`
   is computable by the hook with no oracle.
3. **Independent auditability** — a depositor or auditor can confirm the curator's bond balance
   from pool state alone.

> The shadow counters are a *convenience*, not the security boundary. The security boundary is
> `pendingLiquidity`, which is decremented only through the settlement path (§6).

### 4.3 Mandate state

```solidity
struct Mandate {
    uint24 maxFeeBps;            // cap on the dynamic LP fee the hook will set
    int24  bandLower;            // curator position must stay within [bandLower, bandUpper]
    int24  bandUpper;
    uint32 minSkinBps;           // curator liquidity must be >= this % of vault liquidity
    uint32 maxDrawdownBps;       // against the mark; drives the risk state
    uint32 claimTtl;             // seconds; unclaimed claims expire
    uint8  riskState;            // 0 = normal, 1 = restricted, 2 = breached
}
mapping(PoolId => Mandate) public mandates;
```

### 4.4 Registration

```solidity
struct PoolConfig {
    address vault;
    address curator;          // fee recipient / bond owner of record
    address oracle;           // Chainlink feed; may be address(0) => risk state stays normal
    bool    registered;
}
mapping(PoolId => PoolConfig) public poolConfigs;
```

`registerPool` may be called **once** per `PoolId`, before any liquidity is added. Enforce:
`!registered` and `vault != address(0)` and `curator != address(0)`.

---

## 5. Hook permissions

```solidity
function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
    return Hooks.Permissions({
        beforeInitialize:      false,
        afterInitialize:       false,
        beforeAddLiquidity:    true,   // mandate checks on adds
        afterAddLiquidity:     true,   // shadow ledger updates
        beforeRemoveLiquidity: true,   // <<< the exit gate
        afterRemoveLiquidity:  true,   // shadow ledger updates
        beforeSwap:            true,   // dynamic fee within the cap
        afterSwap:             false,
        beforeDonate:          false,
        afterDonate:           false,
        beforeSwapReturnDelta: false,
        afterSwapReturnDelta:  false,
        afterAddLiquidityReturnDelta: false,
        afterRemoveLiquidityReturnDelta: false
    });
}
```

> Verify the exact `Hooks.Permissions` field list against the pinned `v4-core` version — the
> struct has changed across releases. See `docs/14-CONVENTIONS.md` §4.

---

## 6. Core flows

### 6.1 Deposit

```
depositor → vault.deposit(assets)
  vault → poolManager.unlock(settleDeposit)
    vault → poolManager.modifyLiquidity(LP_SALT, +delta)   // hook: afterAddLiquidity → shadow++
    vault → poolManager.take(usdc, depositor, assets)
    vault → poolManager.sync/clear
  vault → mint shares
```

The hook's `beforeAddLiquidity` checks:
- the pool is registered,
- the deposit does not break the **minimum skin** (projected `curatorLiquidity` ratio still ≥
  `minSkinBps`),
- the tick range is within the mandate band (for curator-salt adds).

### 6.2 Withdrawal: register a claim

```
depositor → vault.requestWithdraw(shares)
  vault: burn/reserve shares, compute liquidityAmount needed for the claim
  vault → hook.registerClaim(poolId, claimId, liquidityAmount)
    hook: claims[poolId][claimId] = { Registered, liquidityAmount, expiresAt }
          pendingLiquidity[poolId] += liquidityAmount
```

`registerClaim` is callable **only by the registered vault** for that pool.

The claim is FIFO by `claimId`. `expiresAt = now + mandate.claimTtl`.

### 6.3 Withdrawal: settle

```
anyone → vault.settleClaims(maxClaims)
  vault → poolManager.unlock(settle)
    for each due claim (FIFO):
      requiredLiquidity = claim.liquidityAmount - claim.settledAmount
      available = depositorLiquidity (from hook shadow ledger)
      take = min(requiredLiquidity, available)
      if take > 0:
        vault → poolManager.modifyLiquidity(LP_SALT, -take)   // hook: afterRemoveLiquidity → shadow--
        vault → hook.settleClaim(poolId, claimId, take)        // hook verifies, pending -= take
      if still short:
        shortfall = requiredLiquidity - take
        // LAST RESORT: curator bond absorbs
        vault → poolManager.modifyLiquidity(CURATOR_SALT, -shortfall)
                // hook allows ONLY because pendingLiquidity > depositorLiquidity
        vault → hook.settleClaim(poolId, claimId, shortfall)
      pay depositor the token value of the liquidity delivered
```

**The hook's `settleClaim` verification:**

```solidity
function settleClaim(PoolId poolId, uint256 claimId, int128 liquidityRemoved)
    external onlyVault(poolId) returns (bool)
{
    Claim storage c = claims[poolId][claimId];
    require(c.status == Registered || c.status == PartiallySettled, "bad status");
    require(liquidityRemoved > 0, "zero");
    require(liquidityRemoved <= c.liquidityAmount - c.settledAmount, "over-claim");
    // The shadow ledger must corroborate a real decrease in vault-side liquidity.
    require(depositorLiquidity[poolId] + curatorLiquidity[poolId] <= snapshotTotal, "no removal");
    c.settledAmount += uint128(liquidityRemoved);
    pendingLiquidity[poolId] -= liquidityRemoved;
    ...
}
```

> The corroboration check needs a per-claim snapshot of total vault-side liquidity taken at
> `registerClaim` time. Store it on the `Claim` struct: `uint128 totalLiquidityAtRegistration`.
> Then settlement requires `currentTotal <= totalLiquidityAtRegistration - liquidityRemoved`.
> This makes the decrement unforgeable even against a compromised vault.

### 6.4 Curator exit

```
curator → vault.requestCuratorExit()
  vault: only if no claim has been registered in the current epoch since the curator's last request
         (a de-facto cooling-off; the hook does not enforce this)
  vault → hook.approveCuratorExit(poolId)
    hook: require(pendingLiquidity[poolId] == 0)   // <<< THE GATE
          curatorExitApproved[poolId] = true
  vault → poolManager.unlock:
    vault → poolManager.modifyLiquidity(CURATOR_SALT, -delta)   // hook re-checks the gate
    vault → poolManager.take(usdc, curator, proceeds - nettedShortfall)
```

The hook's `beforeRemoveLiquidity` for curator-salt removals:

```solidity
// curator-salt removal
if (params.salt == CURATOR_SALT) {
    // LAST RESORT exception: only when depositor liquidity provably cannot cover claims
    bool insolvency = pendingLiquidity[poolId] > depositorLiquidity[poolId];
    if (!insolvency) {
        require(pendingLiquidity[poolId] == 0, "CuratorExitBlocked");
        require(curatorExitApproved[poolId], "CuratorExitNotApproved");
    } else {
        // bounded: may not remove more than the shortfall
        int128 shortfall = pendingLiquidity[poolId] - depositorLiquidity[poolId];
        require(-params.liquidityDelta <= shortfall, "ExceedsShortfall");
    }
}
```

**Why the exception is safe:** it relaxes the gate only when the protocol is *already* unable to
serve depositor claims from depositor liquidity alone. It is arithmetic over the hook's own
ledger, requires no oracle, no tag, and no curator cooperation, and it is bounded by the
shortfall so it cannot be used as a general escape hatch. In this state the curator is losing
their capital, not escaping with it — which is the correct economic outcome.

### 6.5 Mandate enforcement

**Fee cap** — the hook sets the dynamic fee in `beforeSwap`:

```solidity
uint24 fee = computeDynamicFee(key, params);   // volatility/volume based
require(fee <= mandates[poolId].maxFeeBps, "FeeCapExceeded");
return (BeforeSwapDeltaLibrary.ZERO_DELTA, fee);
```

**Tick band** — any modification to the `CURATOR_SALT` position must stay inside
`[bandLower, bandUpper]`:

```solidity
if (params.salt == CURATOR_SALT) {
    require(params.tickLower >= mandates[poolId].bandLower, "BelowBand");
    require(params.tickUpper <= mandates[poolId].bandUpper, "AboveBand");
}
```

**Minimum skin** — projected after the modification:

```solidity
int128 cur  = curatorLiquidity[poolId]   + (isCurator ? params.liquidityDelta : 0);
int128 dep  = depositorLiquidity[poolId] + (isDepositor ? params.liquidityDelta : 0);
int128 total = cur + dep;
require(total == 0 || (uint128(cur) * 10_000 >= uint128(total) * mandate.minSkinBps), "SkinTooLow");
```

> Use `int256` for the multiply and compare with a rounding-down bias **against** the curator,
> so the check can never be passed by rounding.

### 6.6 Risk state

```
Chainlink mark → drawdown vs. the mark's high-water mark
  drawdown <  maxDrawdownBps            → Normal
  drawdown >= maxDrawdownBps            → Restricted  (risk-increasing curator actions frozen)
  drawdown >= maxDrawdownBps * 2, twice → Breached    (as Restricted + fee forfeited)
```

`Restricted` **never blocks a curator exit**. An exit is risk-reducing, and freezing it would
trap the curator's own capital; the CEP gate already governs when an exit is allowed. It also
never blocks a depositor action.

**Degradation rule (critical):** if the oracle is stale, unavailable, incomplete, or returns a
non-positive price, the risk state must **degrade to the more restrictive of (last known state,
Restricted)**. It must never degrade to a *less* restrictive state, and it must never influence
the depositor exit path. A stale or never-run evaluation is treated as `Restricted` by
`effectiveRiskState`. See `docs/10-CHAINLINK.md` §4.

### 6.7 Performance fee

High-water-mark, dilution-only, minted as shares to the curator's fee recipient. Never
withdrawable as principal. Forfeitable on a **confirmed** `Breached` state: the epoch's fee is
not minted, and `PerformanceFeeForfeited` is emitted. A single extreme print cannot trigger
this — `BREACH_CONFIRMATIONS = 2`.

---

## 7. State machines

### 7.1 Claim lifecycle

```
                    registerClaim
                         │
                         ▼
                    ┌─────────┐   settleClaim (full)    ┌─────────┐
                    │Registered│ ─────────────────────► │ Settled │
                    └────┬─────┘                        └─────────┘
                         │ settleClaim (partial)
                         ▼
                    ┌──────────────┐   settleClaim (rest)  ┌─────────┐
                    │PartiallySettled│ ───────────────────► │ Settled │
                    └────┬─────────┘                       └─────────┘
                         │ expiresAt passed
                         ▼
                    ┌──────────┐
                    │ Expired  │  → depositor shares restored
                    └──────────┘
```

### 7.2 Curator exit lifecycle

```
  Idle ──requestCuratorExit──► Requested
                                   │
                                   │ hook.approveCuratorExit
                                   │   requires pendingLiquidity == 0
                                   ▼
                               Approved ──removeLiquidity(CURATOR_SALT)──► Exited
                                   │
                                   │ claim registered (pending > 0)
                                   ▼
                                Revoked  ──(auto, on next registerClaim)──► Idle
```

**Revocation on claim registration is essential.** A curator who was approved to exit and then
an obligation appears must be re-locked. Implement: in `registerClaim`, if `pendingLiquidity`
was zero before and is now positive, set `curatorExitApproved[poolId] = false`.

---

## 8. Trust model

| Party | Trusted for | Explicitly **not** trusted for |
|---|---|---|
| **Curator** | nothing | ordering its own exit ahead of depositor claims; exceeding the mandate |
| **Vault** | depositor accounting, share maths, performance fee | *ordering* — the hook's ledger is authoritative for the gate |
| **Hook** | the ordering gate and mandate enforcement | pricing, valuation, fairness of the strategy |
| **Chainlink** | supplying a reference mark | any permission; never the exit path |
| **Depositor** | nothing | griefing the curator (mitigated by share burn + claim TTL) |

**The central claim of the protocol** is that the *ordering* property holds even if the vault is
buggy, hostile, or upgraded, because the gate lives in the hook and is evaluated against
pool-derived state.

---

## 9. Dependency order for implementation

```
Phase 0  validate v4 primitives (position keying, salt, StateLibrary reads, hook callbacks)
   │
Phase 1  SkylineHook skeleton: permissions, registration, shadow ledgers  (no economics yet)
   │
Phase 2  claim ledger: registerClaim / settleClaim / expiry                  (the thesis)
   │
Phase 3  SkylineVault: deposit, shares, claim queue, settlement
   │
Phase 4  exit gate: approveCuratorExit, revocation, last-resort exception
   │
Phase 5  loss absorption: shortfall → bond
   │
Phase 6  mandate enforcement: fee cap, tick band, minimum skin
   │
Phase 7  performance fee + forfeiture; migration
   │
Phase 8  Chainlink risk state; Automation
   │
Phase 9  dashboard, demo scenario, docs
```

Phases 1–2 are the thesis. Phases 3–4 make it a usable protocol. Phases 5–7 are amplifiers.
Phase 8 is sponsor alignment. Phase 9 is the demo. **Never let 5–9 delay 1–4.**

---

## 10. Data flow diagram

```
                    ┌─────────────────────────────────────────┐
                    │            Chainlink (Price Feed)       │
                    │   external mark — risk state only       │
                    └──────────────────┬──────────────────────┘
                                       │ read
                                       ▼
  ┌────────────┐  deposit   ┌──────────────────┐   modifyLiquidity   ┌──────────────────┐
  │ Depositor  │───────────►│  SkylineVault    │──────────────────►│  PoolManager     │
  │            │◄───────────│                  │◄─────────────────│                  │
  └────────────┘  payout   │  • shares/NAV    │   settle/take      └────────┬─────────┘
       │                    │  • claim queue  │                            │
       │ requestWithdraw    │  • bond acct.   │                  before/after│ModifyLiquidity
       └───────────────────►│                  │                            │
                            └────────┬─────────┘                            ▼
                                     │                          ┌──────────────────┐
                                     │ registerClaim /          │   SkylineHook    │
                                     │ settleClaim /            │                  │
                                     │ approveCuratorExit       │  • pendingLedger │
                                     └─────────────────────────►│  • shadowLedger  │
                                                                │  • mandate       │
                                                                │  • risk state    │
                                                                └──────────────────┘
```

---

## 11. Reading pool state

All pool reads go through `StateLibrary` (`v4-core/src/libraries/StateLibrary.sol`):

```solidity
using StateLibrary for IPoolManager;

(uint128 liquidity, , ) = poolManager.getPositionInfo(
    poolId, vault, tickLower, tickUpper, LP_SALT
);
```

> **R8:** `PoolManager` exposes **no** public `get*` getters in current `v4-core`. Everything is
> via `StateLibrary` (`extsload`/`exttload`). `poolManager.getSlot0(...)` will not compile.
> Verify the exact `StateLibrary` signatures against the pinned tag in Phase 0.

---

## 12. Known deviations from a "pure" design, and why

| Deviation | Reason | Documented risk |
|---|---|---|
| Vault custodies the curator's bond position | The vault must be able to force absorption without curator cooperation | `R-02` — mitigated by the curator's balance being independently derivable from pool state |
| Curator exit uses an approval + ledger-empty gate rather than a pure queue | Simpler, and provably equivalent in the observable cases | `R-04` |
| No oracle in the exit path | Safety | Deliberate |
| Single pool per vault | 17-day build window | `R-07` — multi-pool is explicitly out of scope |

---

*Next: `docs/04-ECONOMICS.md` (the maths) → `docs/05-SECURITY.md` (the invariants).*
