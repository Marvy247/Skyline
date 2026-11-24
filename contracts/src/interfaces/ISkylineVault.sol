// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/**
 * @title ISkylineVault
 * @notice The depositor-facing surface of a Skyline vault.
 */
interface ISkylineVault {
    /// @notice Deposits assets and mints shares.
    function deposit(uint256 assets, address receiver) external returns (uint256 shares);

    /// @notice Total assets under management, excluding the curator bond.
    function totalAssets() external view returns (uint256);

    /// @notice Serves due withdrawal claims, FIFO. Permissionless.
    function settleClaims(uint256 maxClaims) external returns (uint256 settled);

    /// @notice Total depositor shares outstanding.
    function totalSupply() external view returns (uint256);

    /// @notice NAV per share, scaled by 1e18.
    function navPerShare() external view returns (uint256);

    /// @notice The curator's bonded liquidity, recomputed from pool state.
    function curatorBondValueFromPool() external view returns (uint256);

    /// @notice The curator's exit proceeds right now: the live value of the bonded position.
    function curatorExitProceeds() external view returns (uint256);

    /// @notice Bond value already delivered to depositors in the last-resort path.
    /// @dev This is a historical accountability counter, not a live deduction. The value left the
    ///      curator's position when it was removed, so it is not netted from exit proceeds again.
    function uncoveredShortfall() external view returns (uint256);

    /// @notice The curator's skin as a share of total vault liquidity, in bps.
    function currentSkinBps() external view returns (uint32);

    /// @notice The outstanding obligation, in pool liquidity units.
    function outstandingClaimLiquidity() external view returns (int128);

    /// @notice The number of open claims.
    function outstandingClaims() external view returns (uint256);
}
