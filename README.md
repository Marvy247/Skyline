# Skyline — Curator Exit Parity for Uniswap v4

**UHI11 (11th Uniswap Hook Incubator) — Active Management & Curation**
Team: **Marvy247**

> The curator manages the liquidity. They share the risk. **They don't get to run first.**

Skyline is a Uniswap v4 protocol that makes a curator's capital **junior to depositor
withdrawals**. It is not another vault, yield strategy or copy-trading product: the contribution
is an **exit-ordering guarantee** enforced inside the hook, at the PoolManager, where no vault,
router or keeper can route around it.

**Live on Base Sepolia (84532).** The final hook, vault, keeper and `PoolId` are written by the
deploy script to [`contracts/deployments/84532.json`](contracts/deployments/84532.json). The
dashboard in [`dashboard/`](dashboard/) reads the same values from `dashboard/.env.local`. The
90-second demo script is [`docs/11-DEMO.md`](docs/11-DEMO.md).

---

## The problem

A curated vault lets a manager run a strategy with other people's money. The manager learns
first that the strategy is degrading. In every existing implementation, withdrawal is a
**symmetric ERC-4626 redeem**: the curator's exit is the same operation as a depositor's, and
the curator — who knows more and is closer to the controls — can take it first.

That exit consumes pool liquidity and moves the price against everyone still inside. The
manager was paid to manage the risk, then left ahead of the people who funded it.

The bug is not bad faith. It is **exit ordering**. No amount of disclosure fixes it, because the
incentive exists at the exact moment disclosure is least likely.

## The mechanism

A Skyline vault owns **two Uniswap v4 positions** in the same pool, distinguished by salt:

| Position | Salt | Capital |
|---|---|---|
| Depositor position | `LP_SALT` | All depositor capital, the active strategy |
| Curator bond | `CURATOR_SALT` | The curator's own bonded capital |

The vault is the PoolManager owner of both positions. The curator's economic claim on the bond
is recorded in vault accounting, but the position itself is held by the vault — so a last-resort
drawdown does not need the curator's cooperation.

Depositors exit through **claims**, not a direct redeem:

1. `requestWithdraw(shares)` reserves the shares and registers a claim. The hook records the
   obligation in `pendingLiquidity[poolId]`, denominated in **liquidity units**.
2. The hook **rejects any removal of curator-bonded liquidity** while that ledger is non-empty.
   The check runs in `beforeRemoveLiquidity`, below the vault.
3. `settleClaims` serves claims FIFO from depositor liquidity. The hook decrements the ledger
   only from the `liquidityDelta` it actually observes — never from a vault assertion.
4. If depositor liquidity **provably cannot** cover a claim (`pending > depositorLiquidity`), the
   hook permits a bond removal **bounded by the shortfall**, and the proceeds go to the
   depositor. This is a defensive branch, not a general escape hatch.
5. Only when the ledger is empty may the curator request an exit and realise the remaining bond.

The mandate — fee cap, tick band, minimum skin, claim TTL and drawdown limit — is committed at
pool registration and enforced by the same hook at the point of action. `Restricted` and
`Breached` risk states freeze **risk-increasing** curator actions only; exits and every depositor
action remain available.

## Why the hook is load-bearing

The interesting proof is not that a gate exists. It is what changes when it does.

[`test/unit/Counterfactual.t.sol`](contracts/test/unit/Counterfactual.t.sol) runs the same vault,
curator and withdrawal twice:

| | Without CEP | With CEP |
|---|---|---|
| Curator exits first | allowed | **blocked** |
| Bond at the moment the claim is registered | **0** | **still in the pool** |
| Depositor's market payout | whatever remains | the same market payout — **ordering changed, not the price** |
| Curator accountability | none | locked behind the claim until it settles |

That is the honest claim: CEP changes **who leaves first and what the curator owes**, not the
depositor's exposure to the market. The depositor was always exposed to the strategy; they were
never supposed to be exposed to the curator's head start.

## What the hook prevents, detects and refuses to do

| Surface | Behaviour |
|---|---|
| Tick band / fee cap / minimum skin | **Prevented** — a curator action outside the mandate reverts in the hook |
| Curator exit while obligations are outstanding | **Prevented** — `CuratorExitBlocked(pending)` from `beforeRemoveLiquidity` |
| Depositor exit | **Never blocked** — no oracle, risk state or curator action is on the depositor path |
| Drawdown breach | **Detected and penalised** — performance fee forfeited after two confirming observations |
| Market loss between request and settlement | **Borne by the shares that held it** — the bond is exit-priority collateral, not loss insurance |
| Curator merely being locked | **Not slashing** — the bond stays the curator's, and is paid out when the queue clears |

Depositor liveness has a backstop: claims are served pro rata if total claims ever exceed
available liquidity, and after the claim TTL **anyone** can expire an unsettled claim and restore
the unserved shares. The worst case is a partial payout, not a permanent lockout.

## What this is not

Skyline does not pick strategies, generate yield, or promise that the curator is good. It does
not insure depositors against market moves, and it does not slash a curator because the pool
moved. It is unaudited; what exists is a stateful invariant suite, not a security audit. One pool
per vault. The vault custodies the bond position, which is disclosed and independently
derivable from pool state.

## Status

| Component | State |
|---|---|
| Contracts | Implemented and tested — **67 tests, 0 failed** (39 core unit + 21 Chainlink/keeper + 7 invariants) |
| Invariants | 7 invariants at **2,000 runs × 100,000 calls**, 0 reverts |
| Dashboard | Next.js 15 + wagmi/viem — six tabs, live reads, decoded reverts, no-network demo fixture |
| Deployment | Base Sepolia (84532), canonical v4 PoolManager, real USDC/WETH, live Chainlink ETH/USD feed |
| Formatting | `forge fmt --check` clean; dashboard `tsc --noEmit` clean |

## Repository map

| Path | What it is |
|---|---|
| [`contracts/src/SkylineHook.sol`](contracts/src/SkylineHook.sol) | **The enforcement point** — obligation ledger, exit gate, mandate, risk state |
| [`contracts/src/SkylineVault.sol`](contracts/src/SkylineVault.sol) | Depositor accounting, claim queue, bond, performance fee |
| [`contracts/src/SkylineKeeper.sol`](contracts/src/SkylineKeeper.sol) | Chainlink Automation-compatible keeper (optional by construction) |
| [`contracts/test/unit/Counterfactual.t.sol`](contracts/test/unit/Counterfactual.t.sol) | With-CEP vs without-CEP ordering — the load-bearing proof |
| [`contracts/test/invariant/Cep.t.sol`](contracts/test/invariant/Cep.t.sol) | The stateful invariant suite |
| [`dashboard/`](dashboard/) | The demo dashboard |
| [`docs/02-SUBMISSION.md`](docs/02-SUBMISSION.md) | The submission text |
| [`docs/04-ECONOMICS.md`](docs/04-ECONOMICS.md) | CEP formalisation and the exit ladder |
| [`docs/16-IMPLEMENTATION-NOTES.md`](docs/16-IMPLEMENTATION-NOTES.md) | **Every place the code diverged from the spec, and why** |
| [`docs/15-PROGRESS.md`](docs/15-PROGRESS.md) | Living status log and handover notes |

## Quick start

```bash
# Contracts
cd contracts
./bootstrap.sh                                        # pinned deps: forge-std, OZ, v4-core, solmate
forge build
forge test                                            # 67 tests
FOUNDRY_PROFILE=ci forge test --match-path "test/invariant/Cep.t.sol"   # 10,000 runs

# Dashboard
cd ../dashboard
npm install
cp .env.example .env.local     # optional — without it the dashboard runs in demo mode
npm run dev                    # http://localhost:3000/dashboard
```

Demo mode needs no network: `?scenario=blocked` reproduces the worked example, and
`?scenario=lastresort` shows the defensive bond branch. The live deployment can be read back
with `script/Inspect.s.sol`; the exact cast commands are in `docs/11-DEMO.md` §9.

`FOUNDRY_PROFILE=deploy` is required for deployment: at the 1,000,000-run default the vendored
`PoolManager` exceeds EIP-170 (see `docs/16` §14.3). `contracts/lib` is not committed;
`bootstrap.sh` installs the exact pinned set.

## Documentation

Start with **`docs/02-SUBMISSION.md`** for the pitch, **`docs/03-ARCHITECTURE.md`** for the
mechanism, **`docs/04-ECONOMICS.md`** for the maths, and **`docs/05-SECURITY.md`** for the
invariants. **`docs/16-IMPLEMENTATION-NOTES.md`** is the honest delta between specification and
shipped code — read it before reviewing the contracts.
