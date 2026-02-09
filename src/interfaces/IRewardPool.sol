// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

/**
 * @title IRewardPool
 * @notice Interface for RewardPool contract
 */
interface IRewardPool {
    /**
     * @notice Contribution data for an agent
     * @param taskCount Number of tasks completed
     * @param uptimeSeconds Total uptime in seconds
     * @param responseScore Response quality score
     * @param lastUpdated Last update timestamp
     */
    struct Contribution {
        uint256 taskCount;
        uint256 uptimeSeconds;
        uint256 responseScore;
        uint256 lastUpdated;
    }

    /**
     * @notice Emitted when rewards are received
     * @param amount Amount of rewards received
     * @param epoch Epoch number
     */
    event RewardReceived(uint256 amount, uint256 epoch);

    /**
     * @notice Emitted when contribution is reported
     * @param agent Agent address
     * @param taskCount Number of tasks
     * @param uptimeSeconds Uptime in seconds
     * @param responseScore Response score
     * @param epoch Epoch number
     */
    event ContributionReported(
        address indexed agent,
        uint256 taskCount,
        uint256 uptimeSeconds,
        uint256 responseScore,
        uint256 epoch
    );

    /**
     * @notice Emitted when rewards are distributed
     * @param epoch Epoch number
     * @param totalReward Total reward distributed
     * @param agentCount Number of agents rewarded
     */
    event RewardsDistributed(uint256 indexed epoch, uint256 totalReward, uint256 agentCount);

    /**
     * @notice Emitted when reward is claimed
     * @param agent Agent address
     * @param amount Amount claimed
     */
    event RewardClaimed(address indexed agent, uint256 amount);

    /**
     * @notice Emitted when reward formula is updated
     * @param taskWeight New task weight
     * @param uptimeWeight New uptime weight
     * @param responseWeight New response weight
     */
    event FormulaUpdated(uint256 taskWeight, uint256 uptimeWeight, uint256 responseWeight);

    /**
     * @notice Emitted when oracle is updated
     * @param oldOracle Previous oracle address
     * @param newOracle New oracle address
     */
    event OracleUpdated(address indexed oldOracle, address indexed newOracle);

    /**
     * @notice Report agent contribution
     * @param agent Agent address
     * @param taskCount Number of tasks completed
     * @param uptimeSeconds Uptime in seconds
     * @param responseScore Response quality score
     */
    function reportContribution(
        address agent,
        uint256 taskCount,
        uint256 uptimeSeconds,
        uint256 responseScore
    ) external;

    /**
     * @notice Distribute rewards for an epoch
     * @param epoch Epoch number to distribute
     */
    function distributeRewards(uint256 epoch) external;

    /**
     * @notice Claim accumulated rewards
     */
    function claimReward() external;

    /**
     * @notice Get pending reward for an agent
     * @param agent Agent address
     * @return Pending reward amount
     */
    function getPendingReward(address agent) external view returns (uint256);

    /**
     * @notice Get contribution data for an agent
     * @param agent Agent address
     * @return Contribution data
     */
    function getContribution(address agent) external view returns (Contribution memory);

    /**
     * @notice Set reward formula weights
     * @param taskWeight Task weight
     * @param uptimeWeight Uptime weight
     * @param responseWeight Response weight
     */
    function setRewardFormula(
        uint256 taskWeight,
        uint256 uptimeWeight,
        uint256 responseWeight
    ) external;

    /**
     * @notice Set oracle address
     * @param oracle New oracle address
     */
    function setOracle(address oracle) external;

    /**
     * @notice Sync rewards from balance changes (for Geth state.AddBalance)
     */
    function syncRewards() external;
}
