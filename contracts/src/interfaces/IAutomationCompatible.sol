// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/**
 * @title IAutomationCompatible
 * @notice The minimal Chainlink Automation surface Skyline's keeper implements.
 * @dev Defined locally so the repository does not take a dependency on the full Chainlink
 *      contracts package. The signatures are byte-for-byte the published interface.
 */
interface IAutomationCompatible {
    /// @notice Simulated off-chain by Chainlink Automation to decide whether to run the upkeep.
    function checkUpkeep(bytes calldata checkData) external returns (bool upkeepNeeded, bytes memory performData);

    /// @notice Executed on-chain by the Automation network, or by anyone else.
    function performUpkeep(bytes calldata performData) external;
}
