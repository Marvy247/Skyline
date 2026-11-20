# 06 — API Specification

> Exact external interfaces, storage layout, errors and events. Implement against this document
> verbatim so that a second implementer produces a compatible codebase.

> **Verification required.** Function signatures on `IHooks` and `Hooks.Permissions` have
> changed across `v4-core` releases. Every signature below that is prefixed `v4:` must be
> confirmed against the pinned tag in Phase 0 (`docs/07-BUILD-ORDER.md`). Where this document
> and the pinned library disagree, **the library wins** — update this document.

---

## 1. `SkylineHook`

### 1.1 Constructor

```solidity
constructor(
    address _owner,             // protocol owner (multisig or EOA for the demo)
    address _registry           // CuratorRegistry
)
```

### 1.2 Hook callbacks (overrides)

```solidity
function _beforeAddLiquidity(
    address sender, PoolKey calldata key, ModifyLiquidityParams calldata params, bytes calldata hookData
) internal override returns (bytes4);

function _afterAddLiquidity(
    address sender, PoolKey calldata key, ModifyLiquidityParams calldata params,
    BalanceDelta delta, BalanceDelta feesAccrued, bytes calldata hookData
) internal override returns (bytes4, BalanceDelta);

function _beforeRemoveLiquidity(
    address sender, PoolKey calldata key, ModifyLiquidityParams calldata params, bytes calldata hookData
) internal override returns (bytes4);

function _afterRemoveLiquidity(
    address sender, PoolKey calldata key, ModifyLiquidityParams calldata params,
    BalanceDelta delta, BalanceDelta feesAccrued, bytes calldata hookData
) internal override returns (bytes4, BalanceDelta);

function _beforeSwap(
    address sender, PoolKey calldata key, SwapParams calldata params, bytes calldata hookData
) internal override returns (BeforeSwapDelta, uint24);
```

### 1.3 Registration and configuration

```solidity
function registerPool(
    PoolId poolId,
    address vault,
    address curator,
    address oracle,
    Mandate calldata mandate
) external onlyOwner;                       // one-shot per poolId

function setMandate(PoolId poolId, Mandate calldata m) external onlyOwner;   // only if no liquidity yet
function setOracle(PoolId poolId, address oracle) external onlyOwner;
```

### 1.4 Claim lifecycle

```solidity
function registerClaim(
    PoolId poolId,
    uint256 claimId,
    uint128 liquidityAmount,
    address depositor
) external onlyVault(poolId) returns (bool);

function settleClaim(
    PoolId poolId,
    uint256 claimId,
    int128 liquidityRemoved
) external onlyVault(poolId) returns (bool);

function expireClaim(PoolId poolId, uint256 claimId) external returns (bool);   // permissionless once expired

function approveCuratorExit(PoolId poolId) external onlyVault(poolId) returns (bool);
```

### 1.5 Views

```solidity
function pendingLiquidity(PoolId poolId) external view returns (int128);
function curatorLiquidity(PoolId poolId) external view returns (int128);
function depositorLiquidity(PoolId poolId) external view returns (int128);
function claim(PoolId poolId, uint256 claimId) external view returns (Claim memory);
function mandate(PoolId poolId) external view returns (Mandate memory);
function riskState(PoolId poolId) external view returns (uint8);
function isCuratorExitBlocked(PoolId poolId) external view returns (bool);
function curatorBondBalance(PoolId poolId) external view returns (int128);   // from pool state, not vault books
```

### 1.6 `Mandate` struct

```solidity
struct Mandate {
    uint24 maxFeeBps;        // cap on the dynamic LP fee
    int24  bandLower;        // curator position tick band
    int24  bandUpper;
    uint32 minSkinBps;       // curator liquidity / total vault liquidity
    uint32 maxDrawdownBps;   // risk-state threshold vs. mark
    uint32 claimTtl;         // seconds
    uint8  riskState;        // 0 normal, 1 restricted, 2 breached
}
```

---

## 2. `SkylineVault`

### 2.1 Constructor

```solidity
constructor(
    IERC20 asset_,            // USDC
    string name_,
    string symbol_,
    IPoolManager poolManager_,
    ISkylineHook hook_,
    address curator_,
    address feeRecipient_,
    uint16 perfFeeBps_
)
```

### 2.2 Depositor functions

```solidity
function deposit(uint256 assets, address receiver) public returns (uint256 shares);
function mint(uint256 shares, address receiver) public returns (uint256 assets);
function redeem(uint256 shares, address receiver, address owner) public returns (uint256 assets);
function withdraw(uint256 assets, address receiver, address owner) public returns (uint256 shares);

function requestWithdraw(uint256 shares) external returns (uint256 claimId);
function settleClaims(uint256 maxClaims) external returns (uint256 settled);
function claimStatus(uint256 claimId) external view returns (ClaimStatus memory);
```

### 2.3 Curator functions

```solidity
function curatorDeposit(uint256 assets) external returns (uint128 liquidityAdded);
function curatorTopUp(uint256 assets) external returns (uint128 liquidityAdded);
function requestCuratorExit() external returns (bool);
function curatorBondValue() external view returns (uint256);       // derived from pool state
function curatorExitProceeds() external view returns (uint256);   // bondValue − uncovered shortfall
```

### 2.4 Strategy functions

```solidity
function performRebalance(
    int24 tickLower, int24 tickUpper, uint128 targetLiquidity
) external onlyCurator returns (bool);

function setMandate(Mandate calldata m) external onlyCurator;   // subject to hook rules
function accruePerformanceFee() external returns (uint256 feeShares);
function migrate(uint256 assets, address targetVault) external onlyOwner returns (uint256);
```

### 2.5 Views

```solidity
function totalAssets() public view returns (uint256);
function convertToShares(uint256 assets) public view returns (uint256);
function convertToAssets(uint256 shares) public view returns (uint256);
function highWaterMark() external view returns (uint256);
function outstandingClaims() external view returns (uint256);       // count
function outstandingClaimLiquidity() external view returns (int128);
function uncoveredShortfall() external view returns (uint256);
function currentSkinBps() external view returns (uint32);
```

---

## 3. `CuratorRegistry`

```solidity
struct CuratorInfo {
    address curator;
    address feeRecipient;
    uint64  registeredAt;
    uint32  strategyCount;
    uint128 lifetimeFees;      // token units
    uint128 lifetimeAbsorbed;  // shortfall absorbed — published, not punished
    uint32  epochsActive;
    bool    active;
}

function registerCurator(address curator, address feeRecipient) external returns (bool);
function setFeeRecipient(address curator, address feeRecipient) external onlyCurator;
function recordAbsorption(address curator, uint256 amount) external onlyHook;
function recordFees(address curator, uint256 amount) external onlyVault;
function curators() external view returns (address[] memory);
function info(address curator) external view returns (CuratorInfo memory);
```

**Note:** `lifetimeAbsorbed` is *published*, never slashed. Being unable to absorb is a signal,
not a crime — see `docs/01-PROJECT-BRIEF.md` §6 non-goals. The registry publishes, the protocol
enforces.

---

## 4. Storage layout

### 4.1 `SkylineHook`

| Slot | Variable | Type |
|---|---|---|
| 0 | `owner` | `address` |
| 1 | `registry` | `address` |
| 2 | `poolConfigs` | `mapping(PoolId => PoolConfig)` |
| 3 | `mandates` | `mapping(PoolId => Mandate)` |
| 4 | `pendingLiquidity` | `mapping(PoolId => int128)` |
| 5 | `curatorLiquidity` | `mapping(PoolId => int128)` |
| 6 | `depositorLiquidity` | `mapping(PoolId => int128)` |
| 7 | `nextClaimId` | `mapping(PoolId => uint256)` |
| 8 | `claims` | `mapping(PoolId => mapping(uint256 => Claim))` |
| 9 | `curatorExitApproved` | `mapping(PoolId => bool)` |
| 10 | `nextPoolNonce` | `uint256` |

### 4.2 `Claim`

```solidity
struct Claim {
    uint128 liquidityAmount;
    uint128 settledAmount;
    uint128 totalLiquidityAtRegistration;
    uint64  registeredAt;
    uint64  expiresAt;
    uint8   status;
    address depositor;
}
```

### 4.3 `SkylineVault`

| Variable | Type | Notes |
|---|---|---|
| `asset` | `IERC20` | |
| `poolManager` | `IPoolManager` | |
| `hook` | `ISkylineHook` | |
| `curator` | `address` | |
| `feeRecipient` | `address` | |
| `totalSupply` | `uint256` | ERC-4626 shares |
| `highWaterMark` | `uint256` | per share, scaled 1e18 |
| `perfFeeBps` | `uint16` | |
| `totalCuratorLiquidity` | `uint128` | mirror of the hook's shadow counter (display only) |
| `uncoveredShortfall` | `uint256` | token units charged to the curator |
| `nextClaimId` | `uint256` | |
| `openClaimCount` | `uint256` | |
| `lastCuratorExitRequest` | `uint64` | cooldown |
| `rebalanceCount` | `mapping(uint64 => uint256)` | per-epoch count |

---

## 5. Errors

```solidity
// SkylineHook
error PoolAlreadyRegistered();
error PoolNotRegistered();
error NotVault();
error NotCurator();
error NotOwner();
error ClaimAlreadyExists();
error ClaimNotFound();
error ClaimExpired();
error ClaimAlreadySettled();
error ClaimNotExpired();
error ZeroLiquidity();
error OverClaim();
error NoLiquidityRemoved();
error SettlementNotCorroborated();
error CuratorExitBlocked(int128 pendingLiquidity);
error CuratorExitNotApproved();
error ExceedsShortfall();
error FeeCapExceeded(uint24 fee, uint24 cap);
error BelowBand(int24 tickLower, int24 bandLower);
error AboveBand(int24 tickUpper, int24 bandUpper);
error SkinTooLow(uint32 actualBps, uint32 requiredBps);
error RiskStateRestricted();
error RiskStateBreached();
error InvalidMandate();

// SkylineVault
error InsufficientShares();
error InsufficientAssets();
error ZeroAmount();
error ClaimLimitExceeded();
error MinClaimSize();
error NotRegistered();
error CoolingOff();
error NothingToSettle();
error VaultNotEmpty();
```

Use custom errors (not `require` strings) — cheaper and machine-readable, and the demo UI can
decode them.

---

## 6. Events

```solidity
// SkylineHook
event PoolRegistered(PoolId indexed poolId, address vault, address curator, address oracle);
event MandateUpdated(PoolId indexed poolId, Mandate mandate);
event ClaimRegistered(PoolId indexed poolId, uint256 indexed claimId, uint128 liquidityAmount, address depositor);
event ClaimSettled(PoolId indexed poolId, uint256 indexed claimId, int128 liquidityRemoved, uint128 remaining);
event ClaimExpired(PoolId indexed poolId, uint256 indexed claimId, uint128 restoredAmount);
event CuratorExitApproved(PoolId indexed poolId);
event CuratorExitRevoked(PoolId indexed poolId, uint128 pendingLiquidity);
event CuratorExitBlocked(PoolId indexed poolId, int128 pendingLiquidity);
event RiskStateChanged(PoolId indexed poolId, uint8 oldState, uint8 newState, uint256 drawdownBps);
event MandateViolation(PoolId indexed poolId, bytes32 violationCode);

// SkylineVault
event Deposited(address indexed sender, address indexed receiver, uint256 assets, uint256 shares);
event WithdrawalRequested(address indexed depositor, uint256 indexed claimId, uint256 shares, uint128 liquidityAmount);
event ClaimsSettled(uint256 count, uint256 assetsPaid);
event CuratorBonded(address indexed curator, uint256 assets, uint128 liquidityAdded);
event CuratorExitRequested(address indexed curator, uint64 timestamp);
event CuratorExited(address indexed curator, uint256 proceeds, uint256 shortfallNetted);
event ShortfallAbsorbed(address indexed curator, uint256 amount, uint256 remainingShortfall);
event PerformanceFeeAccrued(uint256 feeShares, uint256 hwm, uint256 navPerShare);
event Rebalanced(int24 tickLower, int24 tickUpper, uint128 liquidity);
event Migrated(address indexed to, uint256 assets, uint256 shares);
```

`MandateViolation.violationCode` should be a `bytes32` enum so the dashboard can decode it
without string matching:

```solidity
bytes32 constant VIOLATION_FEE_CAP      = keccak256("FEE_CAP");
bytes32 constant VIOLATION_BAND_LOWER   = keccak256("BAND_LOWER");
bytes32 constant VIOLATION_BAND_UPPER   = keccak256("BAND_UPPER");
bytes32 constant VIOLATION_MIN_SKIN     = keccak256("MIN_SKIN");
bytes32 constant VIOLATION_RESTRICTED   = keccak256("RESTRICTED_OPERATION");
```

---

## 7. Read-only "verifier" helpers

Put these on the hook (or a separate `MandateReader` contract). They are the basis of the
"anyone can verify" claim and make the dashboard trivial.

```solidity
/// Independently recompute the curator's bonded liquidity from pool state.
function verifyCuratorBond(PoolId poolId) external view returns (int128 poolDerived, int128 recorded);

/// Independently recompute outstanding obligations from the claim list.
function verifyPending(PoolId poolId) external view returns (int128 derived, int128 recorded);

/// Everything a third party needs to check the protocol's core claim.
function verifyCep(PoolId poolId) external view returns (
    bool cepHolds,
    int128 pending,
    int128 curatorLiquidity,
    bool curatorMayExit
);
```

**`verifyCep` is the demo's best asset.** It is a single view call that returns whether the
central invariant currently holds, computed independently from the pool. Wire it to a big green
or red badge in the dashboard.

---

## 8. Interface separation

```solidity
interface ISkylineHook {
    // --- registration ---
    function registerPool(PoolId poolId, address vault, address curator, address oracle, Mandate calldata m) external;
    function setMandate(PoolId poolId, Mandate calldata m) external;

    // --- claims ---
    function registerClaim(PoolId poolId, uint256 claimId, uint128 liquidityAmount, address depositor) external returns (bool);
    function settleClaim(PoolId poolId, uint256 claimId, int128 liquidityRemoved) external returns (bool);
    function expireClaim(PoolId poolId, uint256 claimId) external returns (bool);
    function approveCuratorExit(PoolId poolId) external returns (bool);

    // --- views ---
    function pendingLiquidity(PoolId poolId) external view returns (int128);
    function curatorLiquidity(PoolId poolId) external view returns (int128);
    function depositorLiquidity(PoolId poolId) external view returns (int128);
    function riskState(PoolId poolId) external view returns (uint8);
    function isCuratorExitBlocked(PoolId poolId) external view returns (bool);
    function verifyCep(PoolId poolId) external view returns (bool, int128, int128, bool);
}
```

---

*Next: `docs/07-BUILD-ORDER.md` — the step-by-step task list.*
