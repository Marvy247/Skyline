// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/**
 * @title SkylineTypes
 * @notice Shared types, constants and encoding helpers for the Skyline protocol.
 * @dev The two salts are the heart of the position-attribution design: depositor capital and
 *      curator bond live in two distinct Uniswap v4 positions that differ ONLY by `salt`.
 *
 *      v4 position identity is `keccak256(abi.encodePacked(owner, tickLower, tickUpper, salt))`
 *      and `owner` is `msg.sender` to the PoolManager, so a position is uniquely attributable
 *      to (owner, range, salt). Two salts under one owner therefore means two independent
 *      positions with independent liquidity and independent fee accounting.
 */
library SkylineTypes {
    /// @dev Position salt for depositor capital.
    bytes32 internal constant LP_SALT = keccak256("SKYLINE.LP_SALT.v1");
    /// @dev Position salt for the curator's bonded capital.
    bytes32 internal constant CURATOR_SALT = keccak256("SKYLINE.CURATOR_SALT.v1");

    /// @dev Magic marker that prefixes settlement intent in `hookData` ("MAND").
    bytes4 internal constant SETTLEMENT_MARKER = 0x4d414e44;

    /// @notice Lifecycle of a depositor withdrawal claim.
    enum ClaimStatus {
        None,
        Registered,
        PartiallySettled,
        Settled,
        Expired
    }

    /// @notice Operational risk state of a strategy, derived from the mandate's drawdown limit.
    enum RiskState {
        Normal,
        Restricted,
        Breached
    }

    /// @notice The parameters a curator commits to when the strategy is created.
    /// @dev Every field is enforced by the hook at the point of action, not by a policy layer
    ///      above it. `maxDrawdownBps` is the only one that cannot be prevented outright, because
    ///      it depends on an external mark; it is detected and penalised instead.
    struct Mandate {
        /// @dev Cap on the dynamic LP fee the hook is permitted to set, in bps.
        uint24 maxFeeBps;
        /// @dev Lower bound of the tick range the curator position must stay within.
        int24 bandLower;
        /// @dev Upper bound of the tick range the curator position must stay within.
        int24 bandUpper;
        /// @dev Minimum curator liquidity as a share of total vault liquidity, in bps.
        uint32 minSkinBps;
        /// @dev Drawdown from the high-water mark that escalates the risk state, in bps.
        uint32 maxDrawdownBps;
        /// @dev Lifetime of an unsettled claim, in seconds.
        uint32 claimTtl;
        /// @dev Current risk state. See `RiskState`.
        uint8 riskState;
    }

    /// @notice A depositor's recorded withdrawal request.
    /// @dev `liquidityAmount` is denominated in POOL LIQUIDITY UNITS, not tokens. That keeps the
    ///      ledger independent of price and makes partial settlement natural.
    struct Claim {
        /// @dev Pool liquidity units owed to the depositor.
        uint128 liquidityAmount;
        /// @dev Pool liquidity units already delivered.
        uint128 settledAmount;
        /// @dev Snapshot of total vault-side liquidity when the claim was registered.
        uint128 totalLiquidityAtRegistration;
        /// @dev Registration timestamp.
        uint64 registeredAt;
        /// @dev Expiry timestamp.
        uint64 expiresAt;
        /// @dev See `ClaimStatus`.
        uint8 status;
        /// @dev The depositor the claim belongs to.
        address depositor;
    }

    /// @notice Per-pool configuration, set once at registration.
    struct PoolConfig {
        /// @dev The vault authorised to register claims and settle them for this pool.
        address vault;
        /// @dev The curator of record.
        address curator;
        /// @dev Optional external mark source. May be address(0).
        address oracle;
        /// @dev Whether the pool has been registered.
        bool registered;
    }

    /// @notice Encodes settlement intent for `hookData`.
    /// @dev `hookData` is a CORRELATION channel only. It never authorises anything: the hook
    ///      still checks that only the registered vault can remove the vault's liquidity, that
    ///      the claim exists and is open, and that the removed amount does not exceed the
    ///      claim's outstanding remainder.
    /// @param claimId The claim the removal settles.
    /// @return data The encoded intent.
    function encodeSettlement(uint256 claimId) internal pure returns (bytes memory data) {
        return abi.encode(SETTLEMENT_MARKER, claimId);
    }

    /// @notice Decodes settlement intent from `hookData`.
    /// @param hookData The data passed to the PoolManager.
    /// @return claimId The decoded claim id, or 0.
    /// @return ok Whether the data carried a settlement intent.
    function decodeSettlement(bytes calldata hookData) internal pure returns (uint256 claimId, bool ok) {
        if (hookData.length != 64) return (0, false);

        bytes4 marker;
        assembly ("memory-safe") {
            marker := calldataload(hookData.offset)
        }
        if (marker != SETTLEMENT_MARKER) return (0, false);

        claimId = uint256(bytes32(hookData[32:64]));
        ok = true;
    }
}
