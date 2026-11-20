// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/**
 * @title IChainlinkFeed
 * @notice The minimal Chainlink-compatible aggregator surface Skyline reads.
 * @dev Deliberately minimal. Skyline uses the mark for RISK PARAMETERS only; it is never
 *      consulted on the depositor exit path. See docs/10-CHAINLINK.md.
 */
interface IChainlinkFeed {
    /// @notice Latest round data.
    /// @return roundId The round id.
    /// @return answer The price, scaled by the feed's decimals.
    /// @return startedAt When the round started.
    /// @return updatedAt When the round was last updated.
    /// @return answeredInRound The round the answer belongs to.
    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound);
}
