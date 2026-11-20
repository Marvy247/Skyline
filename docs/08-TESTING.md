# 08 — Testing

> The test suite is not QA — it is the **demo**. At Demo Day you will claim "the curator cannot
> run" and "no depositor can be locked out". This document is where those claims are earned.

---

## 1. Test matrix

| Suite | Type | Purpose | Target |
|---|---|---|---|
| `test/Primitives.t.sol` | unit | v4 mechanics: salt separation, owner-only modification, `StateLibrary` reads | 100% of Phase 0 assertions |
| `test/HookShadow.t.sol` | unit | Shadow-ledger correctness | all branches |
| `test/ClaimLedger.t.sol` | unit | Claim register/settle/expire, all revert paths | all branches |
| `test/Vault.t.sol` | unit + fuzz | ERC-4626 maths, NAV, share inflation | fuzz 10k runs |
| `test/ExitLadder.t.sol` | unit | The worked example, asserted number by number | exact values |
| `test/Mandate.t.sol` | unit | Every mandate constraint and its revert | all branches |
| `test/Fee.t.sol` | unit + invariant | HWM performance fee | invariant |
| `test/Oracle.t.sol` | fuzz | Oracle failure modes | fuzz 10k runs |
| `test/invariant/Cep.t.sol` | **invariant** | INV-2, INV-3, INV-8 | ≥ 10,000 runs, ≥ 500 calls |
| `test/invariant/NoLockout.t.sol` | **invariant** | INV-6 | ≥ 10,000 runs |
| `test/invariant/Ledger.t.sol` | **invariant** | INV-1, INV-2, INV-4, INV-11 | ≥ 10,000 runs |
| `test/invariant/Skin.t.sol` | **invariant** | INV-7, INV-9, INV-13 | ≥ 10,000 runs |
| `test/fork/BaseSepolia.t.sol` | fork | Live PoolManager integration | all critical paths |

---

## 2. Fuzz targets

| Function | Seeds | Notes |
|---|---|---|
| `vault.deposit(assets, receiver)` | `assets ∈ [1, 1e24]`, `receiver ∈ {addresses}` | Include `0`, `1`, `type(uint256).max` |
| `vault.requestWithdraw(shares)` | `shares ∈ [1, totalSupply]` | |
| `hook.registerClaim(...)` | `liquidityAmount ∈ [0, 1e24]`, `claimId ∈ [0, 2^32]` | Include duplicate ids |
| `hook.settleClaim(...)` | `liquidityRemoved ∈ [-1e24, 1e24]` | Include negatives, zeros, overshoots |
| `hook._beforeSwap` fee | volatile feed values | Assert fee ≤ cap |
| oracle `latestRoundData` | `answer ∈ [0, 1e30]`, `updatedAt ∈ [0, now]` | Include stale, zero, future |

**Fuzz runs:** `forge test --fuzz-runs 10000`. Run with `--fuzz-seed` recorded in CI.

---

## 3. The invariant handler

The handler is the most important artefact in the test suite. It must generate *adversarial*
sequences, not just random ones.

```solidity
contract CepHandler is Test {
    SkylineHook   hook;
    SkylineVault  vault;
    SkylineHook.PoolId poolId;

    address[] public actors;

    // --- call selection ---
    function registerClaim(uint128 liquidity, uint256 seed) external {
        uint256 claimId = hook.nextClaimId(poolId);
        vm.prank(address(vault));
        hook.registerClaim(poolId, claimId, liquidity, actors[seed % actors.length]);
    }

    function settleClaim(uint256 seed) external {
        uint256 claimId = seed % hook.nextClaimId(poolId);
        int128 removed = int128(uint128(bound(seed, 1, 1e18)));
        vm.prank(address(vault));
        try hook.settleClaim(poolId, claimId, removed) {} catch {}
    }

    function expireClaim(uint256 seed) external {
        uint256 claimId = seed % hook.nextClaimId(poolId);
        hook.expireClaim(poolId, claimId);
    }

    function approveCuratorExit() external {
        vm.prank(address(vault));
        try hook.approveCuratorExit(poolId) {} catch {}
    }

    function deposit(uint256 assets, uint256 seed) external {
        vm.prank(actors[seed % actors.length]);
        try vault.deposit(assets, actors[seed % actors.length]) {} catch {}
    }

    function requestWithdraw(uint256 shares, uint256 seed) external {
        address actor = actors[seed % actors.length];
        vm.prank(actor);
        try vault.requestWithdraw(shares) {} catch {}
    }

    function settleClaims() external { try vault.settleClaims(10) {} catch {} }

    function curatorExit() external {
        vm.prank(vault.curator());
        try vault.requestCuratorExit() {} catch {}
    }

    /// Call the curator's removal path directly, bypassing the vault, to try to break the gate.
    function sneakyCuratorRemoval(int128 delta) external {
        vm.prank(address(vault));
        try vault.forceCuratorRemovalForTest(delta) {} catch {}
    }
}
```

> `forceCuratorRemovalForTest` is a test-only helper on the vault that attempts a curator-salt
> removal **directly through the PoolManager**, skipping the vault's own logic. It exists
> purely to prove the hook blocks it. Gate it behind `if (block.timestamp == 0) revert` or a
> test-only subclass — **never ship it**.

### 3.1 Targeted handlers

Beyond random calls, write **targeted** handlers that construct the adversarial cases by hand:

| Handler | What it constructs |
|---|---|
| `ClaimGriefHandler` | Register claims and never settle them, to test expiry and the curator lock |
| `OverdrawHandler` | Try to settle more liquidity than was actually removed |
| `ApprovalRaceHandler` | Approve a curator exit, then register a claim in the same block — tests INV-8 |
| `SkinDrainHandler` | Repeatedly withdraw to try to push the curator's skin below the minimum |
| `OracleShuffleHandler` | Randomly toggle the oracle between stale/zero/extreme/reverting |

---

## 4. Invariant specifications

### INV-1 — claim registration is exclusive and unique

```solidity
function invariant_claimIdsUniqueAndMonotonic() public view {
    // claim ids issued by the hook are strictly increasing and never reused
    assert(hook.nextClaimId(poolId) >= totalClaimsEverRegistered);
}
```

### INV-2 — the ledger matches the claims

```solidity
function invariant_pendingMatchesClaims() public view {
    int128 derived;
    uint256 n = hook.nextClaimId(poolId);
    for (uint256 i = 0; i < n; i++) {
        Claim memory c = hook.claim(poolId, i);
        if (c.status == Registered || c.status == PartiallySettled) {
            derived += int128(c.liquidityAmount - c.settledAmount);
        }
    }
    assert(hook.pendingLiquidity(poolId) == derived);
    assert(hook.pendingLiquidity(poolId) >= 0);
}
```

### INV-3 — Curator Exit Parity (the thesis)

```solidity
function invariant_cepHolds() public view {
    int128 q = hook.pendingLiquidity(poolId);
    int128 d = hook.depositorLiquidity(poolId);

    if (q > 0) {
        // The curator may only have exited under insolvency, and only by the shortfall.
        assert(hook.curatorLiquidity(poolId) == 0 || d >= q || shortfallWasAbsorbed);
    }
    // The invariant the dashboard badge reports:
    assert(hook.verifyCep(poolId).cepHolds);
}
```

> The strongest form of INV-3 is an **event-based** assertion: subscribe to
> `ModifyLiquidity` and assert that no curator-salt removal ever exceeded the outstanding
> obligation at the time of removal. Implement it as a handler-level tracker.

### INV-4 — settlement is corroborated

```solidity
function invariant_settlementCorroborated() public view {
    for each claim c:
        assert(c.settledAmount <= c.liquidityAmount);
        assert(c.totalLiquidityAtRegistration - currentVaultTotal >= c.settledAmount);
}
```

### INV-5 — the oracle never gates a depositor exit

```solidity
function invariant_oracleNeverBlocksDepositors() public {
    // With the oracle set to each of: address(0), a reverting feed, a zero-price feed,
    // a stale feed, an extreme feed — a depositor must still be able to exit.
    for (address oracle : [address(0), revertingFeed, zeroFeed, staleFeed, extremeFeed]) {
        hook.setOracle(poolId, oracle);
        vm.prank(alice);
        vault.requestWithdraw(aliceShares);
        vm.prank(bob);
        vault.settleClaims(10);
        assert(aliceSharesAfter < aliceSharesBefore);
    }
}
```

### INV-6 — no depositor lockout

```solidity
function invariant_depositorNeverStuck() public {
    // After any handler sequence, a depositor who requests can always be settled to zero.
    // Practical formulation: settlement must reduce total vault-side liquidity by at least
    // the outstanding obligation, or the last-resort path must have executed.
    assert(vault.outstandingClaimLiquidity() == 0 || vault.uncoveredShortfall() > 0
           || hook.depositorLiquidity(poolId) > 0);
}
```

---

## 5. Fork tests

Against a live testnet PoolManager (Base Sepolia):

| Test | Purpose |
|---|---|
| `test_fork_depositAndWithdraw` | Real pool, real hook, full round trip |
| `test_fork_twoSalts` | Two positions in the same range with different salts, real fee accounting |
| `test_fork_hookSeesSenderAndSalt` | Log the callback arguments in a live pool |
| `test_fork_stateLibraryReads` | Confirm `getPositionInfo` returns what we expect on a live pool |
| `test_fork_curatorBlocked` | Live revert with `CuratorExitBlocked` |
| `test_fork_settlement` | Live settlement paying out real tokens |

Fork tests are the **highest-value proof** for the demo: they show the mechanism on a real
PoolManager, not a mock.

---

## 6. Gas benchmarks

Record these in `docs/15-PROGRESS.md` and compare against the budget.

| Operation | Target |
|---|---|
| `vault.deposit` | < 250k |
| `vault.requestWithdraw` | < 180k |
| `vault.settleClaims` (1 claim) | < 400k |
| `hook.registerClaim` | < 90k |
| curator removal attempt (reverts) | < 60k |
| `vault.performRebalance` | < 350k |

A revert that costs more than ~80k gas is unpleasant for the demo (it looks expensive). If the
gate is expensive, move the cheap check earlier in `beforeRemoveLiquidity`.

---

## 7. Coverage and quality gates

```
forge test --fuzz-runs 10000 --gas-report
forge coverage --report summary
forge fmt --check
forge build --sizes
```

**Quality gates before the 30 Nov progress update:**

- [ ] All suites green, including every invariant suite at ≥ 10,000 runs
- [ ] `forge fmt --check` clean
- [ ] No compiler warnings
- [ ] Coverage on `SkylineHook.sol` and `SkylineVault.sol` ≥ 90% line coverage, with every
      `revert` branch exercised
- [ ] No `TODO` in Solidity source; no commented-out code
- [ ] `docs/15-PROGRESS.md` updated with gas numbers and coverage output

---

## 8. Honest testing notes

Do not claim "audited". Do not claim "battle-tested". What you may claim:

- "We ran a formal invariant suite with a stateful handler under fuzzing."
- "The core claim — a curator cannot exit ahead of depositor obligations — is an asserted
  invariant, not a claim in prose."
- "The contracts are unaudited."

That is a stronger position than most projects are willing to take, because it is checkable.

---

*Next: `docs/09-FRONTEND.md`.*
