// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IChainlinkFeed} from "../../src/interfaces/IChainlinkFeed.sol";

/**
 * @title MockChainlinkFeed
 * @notice A controllable Chainlink aggregator for tests.
 * @dev Models every failure mode Skyline must survive: zero, negative, stale, incomplete and
 *      reverting reads. The hook must NEVER revert because of any of them.
 */
contract MockChainlinkFeed is IChainlinkFeed {
    uint80 public roundId = 1;
    int256 public answer;
    uint256 public startedAt;
    uint256 public updatedAt;
    uint80 public answeredInRound = 1;
    bool public revertOnRead;

    /// @notice Sets a healthy-looking round.
    function setAnswer(int256 answer_, uint256 updatedAt_) external {
        answer = answer_;
        startedAt = updatedAt_;
        updatedAt = updatedAt_;
        roundId += 1;
        answeredInRound = roundId;
    }

    /// @notice Sets every field, including an incomplete round.
    function setRaw(uint80 roundId_, int256 answer_, uint256 updatedAt_, uint80 answeredInRound_) external {
        roundId = roundId_;
        answer = answer_;
        startedAt = updatedAt_;
        updatedAt = updatedAt_;
        answeredInRound = answeredInRound_;
    }

    /// @notice Makes `latestRoundData` revert.
    function setRevert(bool value) external {
        revertOnRead = value;
    }

    /// @inheritdoc IChainlinkFeed
    function latestRoundData() external view returns (uint80, int256, uint256, uint256, uint80) {
        if (revertOnRead) revert("MockChainlinkFeed: feed unavailable");
        return (roundId, answer, startedAt, updatedAt, answeredInRound);
    }
}
