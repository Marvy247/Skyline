# 04 — Economics

> The numbers behind Curator Exit Parity. The formulas here describe the shipped mechanics; the
> worked example is reproduced by the test suite and used in the demo.

---

## 1. Definitions

| Symbol | Meaning | Unit |
|---|---|---|
| `D` | Total depositor liquidity in the pool (`depositorLiquidity`) | pool liquidity units |
| `C` | Curator bonded liquidity in the pool (`curatorLiquidity`) | pool liquidity units |
| `V` | Total vault-side liquidity, `D + C` | pool liquidity units |
| `Q` | Outstanding depositor obligations (`pendingLiquidity`) | pool liquidity units |
| `A` | Curator's bond claim in vault accounting | token units (e.g. USDC) |
| `F` | Bond value delivered to depositors in the last-resort path | token units |
| `σ` | Minimum skin: `C / V` must be ≥ `minSkinBps` | bps |
| `H` | Vault NAV high-water mark (per share, depositor side) | token units / share |
| `n` | Number of depositor shares | shares |

---

## 2. Curator Exit Parity, formally

> **CEP.** At every point in time, for every pool `p`:
>
> ```
> curatorWithdrawalCapacity(p)  ≤  Q(p)
> ```
>
> where `curatorWithdrawalCapacity(p)` is the curator-bonded liquidity that the protocol will
> permit to be removed in the current settlement window.

Equivalently, in the implementation:

```
removable_curator_liquidity(p) = 0                     if Q(p) = 0 and exit approved
                                 = Q(p) − D(p)          if Q(p) > D(p)   [last resort, bounded]
                                 = 0                     otherwise        [blocked]
```

**Why "≤ Q" and not "= 0".** In the ordinary case the curator is fully blocked while any
obligation is outstanding. Claims are slices of the depositor position, so in normal operation
`Q ≤ D`; the last-resort term is a defensive branch, not a promise that the bond covers market
losses. When it is used, it is *bounded by the shortfall*, so it can only move value **out of
the curator's capital and into the depositor's claim** — never give the curator an advantage.
The bond is **not** charged for a price move between claim registration and settlement; that
loss is borne by the shares that bore the risk.

**Restated for a judge:** *the curator's money is locked behind depositor withdrawals, and the
curator cannot leave the pool ahead of them.*

---

## 3. The exit ladder

```
                    ┌─────────────────────────────────────┐
  depositor         │  1. DEPOSITOR LIQUIDITY             │
  requests ────────►│     serve claims from D             │
  withdrawal        │     cost: price impact borne by D    │
                    └──────────────┬──────────────────────┘
                                   │ curator stays locked
                                   ▼
                    ┌─────────────────────────────────────┐
                    │  2. CURATOR BOND (LAST RESORT)      │
                    │     supplies Q − D only if D is    │
                    │     provably exhausted; pays the   │
                    │     depositor, bounded by Q − D    │
                    └──────────────┬──────────────────────┘
                                   │ still insufficient
                                   ▼
                    ┌─────────────────────────────────────┐
                    │  3. PRO-RATA / EXPIRY FALLBACK      │
                    │     claims are served pro rata if  │
                    │     total claims exceed liquidity; │
                    │     unserved shares can be restored │
                    └─────────────────────────────────────┘
```

**Liveness guarantee (R7):** the settlement loop always terminates. A claim can be served as far
as liquidity allows, and after its TTL anyone can expire it and restore the unserved shares.
The worst case is a partial payout, not a permanent lockout.

**Economic consequence:** the curator cannot leave ahead of depositor claims. That is the
asymmetry the protocol sells. The bond is the curator's own capital at risk in the pool; it is
not market-loss insurance, and a price move does not slash it.

---

## 4. Claim sizing

A depositor's claim is denominated in **pool liquidity units**, not tokens.

```
tokensClaimed  = sharesRedeemed × NAV_per_share          (token units)
liquidityClaim = ceil( tokensClaimed / valueOfOneLiquidityUnit )
```

where `valueOfOneLiquidityUnit` is computed from the pool's current amounts and tick range at
claim registration. Using `StateLibrary.getSlot0` + the tick/liquidity maths, or the simpler
practical approach:

```
liquidityClaim = tokensClaimed × currentLiquidity / totalPoolValue
```

with `currentLiquidity = poolManager.getLiquidity(poolId)` and `totalPoolValue` from the vault's
asset balance plus the pool's fee-adjusted value.

> **Implementation note.** Exact liquidity↔token conversion in a concentrated-liquidity pool is
> range-dependent. For the MVP, compute the claim as a **pro-rata share of the vault's current
> liquidity**:

```
liquidityClaim = ceil( tokensClaimed / totalVaultTokens × D )
```

This is conservative (it never over-promises), needs no tick maths, and is easy to explain on
stage. Upgrade to exact conversion in `docs/13-RISKS.md` R-08 if time allows.

**Rounding:** always round the claim **up** in liquidity and **down** in tokens. Over-promising
liquidity creates uncovered claims; under-promising just leaves the depositor slightly short.

---

## 5. Worked example — the demo scenario

This is the scenario in `docs/11-DEMO.md`. Every number is reproduced by
`test/Economics.t.sol::test_workedExample`.

### Setup

Pool: USDC / WETH. Vault holds two positions in the same tick range.

| Actor | Action | Result |
|---|---|---|
| Curator | bond deposit | `C = 20,000` liquidity units (20% of vault) |
| Alice | deposit | `D` grows by 50,000 units |
| Bob | deposit | `D` grows by 30,000 units |

```
V = 100,000        C = 20,000        D = 80,000        σ = 20%   (minSkinBps = 1000)
```

### Step 1 — degradation

The strategy loses 8%. Vault-side liquidity value falls; the *liquidity units* are unchanged,
but each unit is worth less.

```
NAV_per_share falls.  A = 72,000 token units (was 100,000).
```

### Step 2 — Alice requests withdrawal

Alice redeems 50,000 token units of NAV.

```
tokensClaimed  = 50,000
liquidityClaim = ceil( 50,000 / 72,000 × 80,000 ) = ceil(55,555.6) = 55,556 liquidity units
```

### Step 3 — the hook records the obligation

```
registerClaim(poolId, claimId = 1, liquidityAmount = 55,556)

pendingLiquidity = 55,556          Q = 55,556
```

### Step 4 — the curator attempts to exit *(the demo beat)*

The curator requests to withdraw its 20,000 units.

```
beforeRemoveLiquidity:
  salt == CURATOR_SALT
  Q = 55,556 > 0
  insolvency check:  Q > D ?   55,556 > 80,000 ?  NO
  ⇒ require(Q == 0) FAILS
  ⇒ revert CuratorExitBlocked(55,556)
```

**The curator is blocked while 55,556 units of depositor obligation are outstanding.** The hook
did not ask the vault whether this was true — it knows, from its own ledger.

### Step 5 — settlement

```
vault.settleClaims():
  available depositor liquidity = D = 80,000
  take = min(55,556, 80,000) = 55,556
  removeLiquidity(LP_SALT, 55,556)
  hook.settleClaim(poolId, 1, 55,556):
      totalLiquidityAtRegistration (100,000) − current total (44,444) = 55,556  ✓ corroborates
      Q = 55,556 − 55,556 = 0
  pay Alice the token value of 55,556 units ≈ 40,000 tokens
```

### Step 6 — market loss versus liquidity shortfall

A market loss between registration and settlement is **not** a bond charge. The claim is
denominated in liquidity units, so the liquidity owed is fixed; the token value delivered moves
with the pool. The depositor's shares bore that risk, and the loss stays there. The bond is not
slashed because the price moved.

The last-resort branch exists for the case where the depositor position provably cannot cover an
obligation (`Q > D`). Claims are slices of that position, so the normal claim maths cannot
produce this state; it is a defensive branch. If it is ever reached, the hook allows the bond to
be removed by at most `Q − D`, and those proceeds are paid to the depositor. The vault records
the amount as `uncoveredShortfall` for accountability. It does not net the same amount again at
the curator's exit — the value already left the position.

### Step 7 — the curator exits

```
Q = 0  ⇒ gate opens
curatorExitApproved = true
removeLiquidity(CURATOR_SALT, remaining curator liquidity)
proceeds = the live value of the remaining bond
```

The curator exits last, with whatever remains. There is no second deduction for a market loss.

### Summary table for the demo

| Moment | `Q` | Curator exit | Who bears the loss |
|---|---|---|---|
| Alice claims | 55,556 | **BLOCKED** | — |
| Alice settled | 0 | permitted | depositor liquidity (market loss stays with shares) |
| Last-resort branch (`Q > D`) | > 0 | bounded removal of `Q − D` | bond, paid to the depositor |
| After settlement | 0 | permitted | — |

---

## 6. Minimum skin

The curator cannot dilute its own skin below `minSkinBps` of vault liquidity.

```
σ = C / V        require σ ≥ minSkinBps
```

**Enforcement point:** the hook, in `beforeModifyLiquidity`, using the projected post-modification
values.

**Default:** `minSkinBps = 1000` (10%). At 10%, the curator's capital is a meaningful fraction
of the pool, so the curator shares the strategy's market risk and the exit lock has real capital
behind it.

**Interaction with deposits:** a large deposit dilutes the curator's skin. Two options:

1. **Allow it** — the curator tops up when it breaches. Simple; creates a maintenance burden.
2. **Scale the bond** — the vault auto-scales the curator position to maintain σ. Elegant;
   requires the vault to be able to add liquidity, which it can.

**Recommendation:** option 1 for the MVP, with the dashboard showing the current σ prominently
and an explicit "Top up bond" button. Option 2 is a Phase 7 stretch.

---

## 7. Performance fee

### 7.1 Structure

High-water-mark, dilution-only, shares minted to the curator.

```
HWM update (on any fee accrual):
    if (NAV_per_share > HWM)  HWM = NAV_per_share
    fee = 0
    if (NAV_per_share > HWM_at_last_accrual)
        fee = (NAV_per_share − HWM_at_last_accrual) × n × perfFeeBps / 10_000
    feeShares = fee × n / NAV_per_share
    mint(feeShares, feeRecipient)
```

**Dilution-only:** the curator is paid by minting new shares. The curator can never withdraw
principal. This is the correct ERC-4626 pattern and is the same mechanism VaultCurator uses —
but here it sits on top of a protocol that actually protects depositors, which is the
differentiation.

### 7.2 Defaults

| Parameter | Default | Notes |
|---|---|---|
| `perfFeeBps` | 1500 (15%) | Industry-standard for a curated strategy |
| `mgmtFeeBps` | 0 | Skip the management fee — one fee is easier to explain on stage |
| `claimTtl` | 86400 (24h) | Claims expire; shares are restored |
| `minSkinBps` | 1000 (10%) | |
| `maxFeeBps` | 3000 (0.30%) | Dynamic LP fee cap |
| `maxDrawdownBps` | 1000 (10%) | Triggers `Restricted` |
| `bandLower` / `bandUpper` | strategy range ± 1 tick spacing | MVP: effectively fixed range |

### 7.3 Forfeiture

Performance fees are forfeited (shares burned, not minted) when a mandate violation is
**proven**. See `docs/05-SECURITY.md` §6 for exactly what counts as proven.

The MVP ships forfeiture as a **vault-level, curator-triggerable-by-nobody** flag set by the
hook when it detects a violation in-band. The hook's `beforeModifyLiquidity` reverts on
violations, so a violation cannot actually occur — forfeiture is therefore a *belt-and-braces*
path for violations that are detected post-hoc (e.g., the oracle-based drawdown breach, which
is detected rather than prevented).

**Honest framing for the submission:** the tick band and fee cap are **prevented**; the
drawdown breach is **detected and penalised**. Say exactly that. Do not claim slashing for
things the hook prevents.

---

## 8. Fees the protocol takes

The hook can set the dynamic LP fee. The protocol's share of it goes to the vault to fund
settlements (reducing the chance of a shortfall in the first place).

```
dynamicFee = base + volatilityComponent, capped at mandate.maxFeeBps
```

The protocol's fee share is the `PROTOCOL_FEE` share of the LP fee, collected by the hook's
`afterSwap`/`afterAddLiquidity` via `hookData`... 

> **Simpler MVP:** do not implement protocol fee collection. It adds a `BEFORE_SWAP_RETURNS_DELTA`
> flag and a lot of surface area for a feature that is not part of the thesis. Ship a dynamic
> fee within the cap, and revisit protocol revenue in Phase 7 if time permits.

---

## 9. Sensible parameter relationships

The parameters are not independent. These constraints should be asserted in the constructor:

```
minSkinBps ≤ 5000                     // curator cannot hold majority by accident
perfFeeBps ≤ 3000                     // standard
maxFeeBps  ≤ 10000                    // 100%
maxFeeBps  ≥ 100                      // must allow a non-trivial dynamic range
bandUpper  > bandLower
claimTtl   ≥ 3600 && claimTtl ≤ 7 days
```

---

## 10. Why a curator would accept this

A judge will ask: *why would anyone run a strategy under these terms?* The answer must be in
your Demo Day, not in a footnote.

1. **The bond is capital, not a fee.** A curator with a strong track record is *choosing* to
   signal confidence. Skin in the game is a marketing asset.
2. **The constraint is symmetric with the upside.** If the curator's strategy works, they earn
   15% of the gain, on a larger pool, with depositors who stayed because the mechanism told
   them they could.
3. **The exit lock is bounded.** It lasts only as long as depositor obligations are
   outstanding — a short, mechanical window — not indefinitely.
4. **It solves the thing curators cannot solve alone.** A curator *cannot* credibly promise
   "I won't run" without this mechanism. This protocol makes that promise enforceable, so the
   curator can make it.

**Demo Day line:** *"A curator who wants depositors to trust them is currently asked to make a
promise. Skyline lets them make a guarantee."*

---

## 11. Edge cases the maths must survive

| Case | Handling |
|---|---|
| Claim registered while a curator exit is already approved | `registerClaim` revokes approval when `Q` transitions 0 → > 0 |
| Multiple claims, partial settlement | `settledAmount` per claim; `Q` decremented by actual removals |
| Claim expires unsettled | Depositor shares restored; `Q` decremented by the unsettled remainder |
| Curator exits while `Q > 0` | Blocked, unless the last-resort condition holds |
| Depositor deposits during an outstanding claim | New liquidity increases `D`, which *relaxes* the last-resort condition — correct |
| `D` reaches zero and `Q > 0` | Defensive last-resort branch; the bond supplies up to `Q − D` and is paid to the depositor |
| Curator's bond is fully consumed | Only in the last-resort branch; the curator must top up or remain unable to increase risk |
| Price moves sharply between claim and settlement | Claims are liquidity-denominated, so the *liquidity* owed is fixed; the *token* value delivered moves with the market, and the loss stays with the shares. The bond is not charged. |
| Rounding dust | Round claims up in liquidity, down in tokens; the dust stays in the pool |

---

*Next: `docs/05-SECURITY.md`.*
