// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";

import {SkylineHook} from "../../src/SkylineHook.sol";
import {SkylineBaseHook} from "../../src/SkylineBaseHook.sol";

/**
 * @title DeployableSkylineHook
 * @notice Skyline's hook with the address validation skipped, so its bytecode can be etched onto
 *         a permission-correct address.
 * @dev Uniswap v4 decides which callbacks to invoke by inspecting the low bits of the hook
 *      address. A hook deployed to an arbitrary address therefore fails its constructor's
 *      validation. This subclass disables that check so the implementation can be deployed
 *      normally and then etched onto an address carrying the right flags — the standard v4
 *      testing pattern.
 */
contract DeployableSkylineHook is SkylineHook {
    constructor(IPoolManager manager_, address owner_) SkylineHook(manager_, owner_) {}

    /// @inheritdoc SkylineBaseHook
    function validateHookAddress(SkylineBaseHook) internal pure override {}
}
