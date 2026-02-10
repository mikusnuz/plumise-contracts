// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./interfaces/IRewardPool.sol";
import "./interfaces/IAgentRegistry.sol";

/**
 * @title RewardPool
 * @notice Receives block rewards and distributes them to AI agents based on contributions
 * @dev Block rewards are sent by Geth's Finalize() function
 *
 * SECURITY NOTES:
 * - Oracle is single point of trust for reporting contributions
 * - Consider implementing multi-oracle or oracle reputation system
 * - Contribution bounds (MAX_TASK_COUNT, MAX_PROCESSED_TOKENS) prevent overflow
 * - Storage layout MUST NOT change (genesis contract at 0x1000)
 */
contract RewardPool is IRewardPool, Ownable, ReentrancyGuard {
    /// @notice Blocks per epoch (1200 blocks = 1 hour at 3s blocks)
    uint256 public constant BLOCKS_PER_EPOCH = 1200;

    /// @notice Agent registry contract (not immutable for genesis compatibility)
    IAgentRegistry public agentRegistry;

    /// @notice Oracle address authorized to report contributions
    address public oracle;

    /// @notice Reward formula weights V2 (out of 100)
    uint256 public tokenWeight = 40;
    uint256 public taskWeight = 25;
    uint256 public uptimeWeight = 20;
    uint256 public latencyWeight = 15;

    /// @notice Last tracked balance for syncRewards
    uint256 public lastTrackedBalance;

    /// @notice Agent contributions mapping
    mapping(address => Contribution) public contributions;

    /// @notice Pending rewards for each agent
    mapping(address => uint256) public pendingRewards;

    /// @notice Epoch rewards mapping
    mapping(uint256 => uint256) public epochRewards;

    /// @notice Epoch contribution tracking
    mapping(uint256 => mapping(address => Contribution)) public epochContributions;

    /// @notice Agents who contributed in each epoch
    mapping(uint256 => address[]) public epochAgents;

    /// @notice Track if an agent is already added to epoch
    mapping(uint256 => mapping(address => bool)) public epochAgentExists;

    /// @notice Track if epoch rewards have been distributed
    mapping(uint256 => bool) public epochDistributed;

    /// @notice Current epoch number
    uint256 public currentEpoch;

    /// @notice Block number when contract was deployed (not immutable for genesis compatibility)
    uint256 public deployBlock;

    /// @notice Maximum agents per epoch to prevent gas DOS
    uint256 public constant MAX_EPOCH_AGENTS = 200;

    /// @notice Input validation bounds
    uint256 public constant MAX_TASK_COUNT = 10_000;
    uint256 public constant MAX_UPTIME_SECONDS = 604_800; // 7 days
    uint256 public constant MAX_RESPONSE_SCORE = 1_000_000;
    uint256 public constant MAX_PROCESSED_TOKENS = 100_000_000; // 100M tokens
    uint256 public constant MAX_LATENCY_INV = 10_000; // Higher = faster

    /// @notice Emergency bypass for AgentRegistry dependency
    bool public emergencyBypassRegistry;

    /**
     * @notice Constructor
     * @param _agentRegistry Address of AgentRegistry contract
     * @param _oracle Address of oracle
     */
    constructor(address _agentRegistry, address _oracle) Ownable(msg.sender) {
        require(_agentRegistry != address(0), "Invalid registry");
        require(_oracle != address(0), "Invalid oracle");

        agentRegistry = IAgentRegistry(_agentRegistry);
        oracle = _oracle;
        deployBlock = block.number;
        currentEpoch = 0;
        lastTrackedBalance = 0;
    }

    /**
     * @notice Receive block rewards from Geth (also accepts donations)
     */
    receive() external payable {
        uint256 epoch = getCurrentEpoch();
        epochRewards[epoch] += msg.value;
        lastTrackedBalance = address(this).balance;
        emit RewardReceived(msg.value, epoch);
    }

    /**
     * @notice Sync rewards from balance (for Geth state.AddBalance)
     * @dev Block rewards are added via state.AddBalance(), not receive()
     */
    function syncRewards() external {
        uint256 currentBalance = address(this).balance;
        if (currentBalance <= lastTrackedBalance) {
            return; // No new rewards, exit gracefully
        }
        uint256 newRewards = currentBalance - lastTrackedBalance;
        uint256 epoch = getCurrentEpoch();
        epochRewards[epoch] += newRewards;
        lastTrackedBalance = currentBalance;
        emit RewardReceived(newRewards, epoch);
    }

    /**
     * @notice Report agent contribution V1 (backward compatible)
     * @param agent Agent address
     * @param taskCount Number of tasks completed
     * @param uptimeSeconds Uptime in seconds
     * @param responseScore Response quality score
     */
    function reportContribution(address agent, uint256 taskCount, uint256 uptimeSeconds, uint256 responseScore)
        external
        override
    {
        // Call V2 with zeros for new fields
        reportContribution(agent, taskCount, uptimeSeconds, responseScore, 0, 0);
    }

    /**
     * @notice Report agent contribution V2 with Phase 2 metrics (only oracle)
     * @param agent Agent address
     * @param taskCount Number of tasks completed
     * @param uptimeSeconds Uptime in seconds
     * @param responseScore Response quality score
     * @param processedTokens Total tokens processed (inference)
     * @param avgLatencyInv Inverse average latency (higher = faster)
     */
    function reportContribution(
        address agent,
        uint256 taskCount,
        uint256 uptimeSeconds,
        uint256 responseScore,
        uint256 processedTokens,
        uint256 avgLatencyInv
    ) public override {
        require(msg.sender == oracle, "Only oracle");
        require(taskCount <= MAX_TASK_COUNT, "Task count too high");
        require(uptimeSeconds <= MAX_UPTIME_SECONDS, "Uptime too high");
        require(responseScore <= MAX_RESPONSE_SCORE, "Response score too high");
        require(processedTokens <= MAX_PROCESSED_TOKENS, "Processed tokens too high");
        require(avgLatencyInv <= MAX_LATENCY_INV, "Latency inv too high");

        if (!emergencyBypassRegistry) {
            require(agentRegistry.isRegistered(agent), "Agent not registered");
            require(agentRegistry.isActive(agent), "Agent not active");
        }

        uint256 epoch = getCurrentEpoch();

        // SECURITY: Check for overflow before updating cumulative contributions
        // Solidity 0.8.20 has automatic overflow checks, but explicit bounds prevent DOS
        require(contributions[agent].taskCount + taskCount <= type(uint128).max, "Task count overflow");
        require(
            contributions[agent].processedTokens + processedTokens <= type(uint128).max, "Processed tokens overflow"
        );

        // Update cumulative contributions
        contributions[agent].taskCount += taskCount;
        contributions[agent].uptimeSeconds += uptimeSeconds;
        contributions[agent].responseScore += responseScore;
        contributions[agent].processedTokens += processedTokens;
        contributions[agent].avgLatencyInv += avgLatencyInv;
        contributions[agent].lastUpdated = block.timestamp;

        // Update epoch contributions
        if (!epochAgentExists[epoch][agent]) {
            require(epochAgents[epoch].length < MAX_EPOCH_AGENTS, "Max agents reached");
            epochAgents[epoch].push(agent);
            epochAgentExists[epoch][agent] = true;
        }

        epochContributions[epoch][agent].taskCount += taskCount;
        epochContributions[epoch][agent].uptimeSeconds += uptimeSeconds;
        epochContributions[epoch][agent].responseScore += responseScore;
        epochContributions[epoch][agent].processedTokens += processedTokens;
        epochContributions[epoch][agent].avgLatencyInv += avgLatencyInv;
        epochContributions[epoch][agent].lastUpdated = block.timestamp;

        emit ContributionReported(agent, taskCount, uptimeSeconds, responseScore, processedTokens, avgLatencyInv, epoch);
    }

    /**
     * @notice Distribute rewards for an epoch
     * @param epoch Epoch number to distribute
     * @dev SECURITY: Gas optimization - caches scores to avoid recalculation
     *      Maximum 200 agents per epoch prevents gas DOS
     */
    function distributeRewards(uint256 epoch) external override {
        require(epoch < getCurrentEpoch(), "Epoch not ended");
        require(!epochDistributed[epoch], "Already distributed");
        require(epochRewards[epoch] > 0, "No rewards");

        uint256 totalReward = epochRewards[epoch];
        address[] memory agents = epochAgents[epoch];
        uint256 agentCount = agents.length;

        if (agentCount == 0) {
            // No contributions, rewards stay in pool
            epochDistributed[epoch] = true;
            emit RewardsDistributed(epoch, 0, 0);
            return;
        }

        // OPTIMIZATION: Pre-calculate all scores to avoid double iteration gas cost
        uint256[] memory scores = new uint256[](agentCount);
        uint256 totalScore = 0;

        for (uint256 i = 0; i < agentCount; i++) {
            scores[i] = calculateScore(epochContributions[epoch][agents[i]]);
            totalScore += scores[i];
        }

        if (totalScore == 0) {
            // No valid contributions
            epochDistributed[epoch] = true;
            emit RewardsDistributed(epoch, 0, 0);
            return;
        }

        // Distribute rewards proportionally with dust prevention
        uint256 totalDistributed = 0;
        uint256 lastScoringIndex = type(uint256).max;

        // Find last scoring agent index
        for (uint256 i = 0; i < agentCount; i++) {
            if (scores[i] > 0) {
                lastScoringIndex = i;
            }
        }

        for (uint256 i = 0; i < agentCount; i++) {
            if (scores[i] > 0) {
                uint256 reward;
                if (i == lastScoringIndex) {
                    // Last agent gets remainder to prevent dust
                    reward = totalReward - totalDistributed;
                } else {
                    reward = (totalReward * scores[i]) / totalScore;
                }
                pendingRewards[agents[i]] += reward;
                totalDistributed += reward;
            }
        }

        epochDistributed[epoch] = true;
        emit RewardsDistributed(epoch, totalReward, agentCount);
    }

    /**
     * @notice Claim accumulated rewards
     */
    function claimReward() external override nonReentrant {
        require(agentRegistry.isRegistered(msg.sender), "Not registered");

        uint256 reward = pendingRewards[msg.sender];
        require(reward > 0, "No rewards");

        pendingRewards[msg.sender] = 0;
        lastTrackedBalance = address(this).balance - reward;

        (bool success,) = msg.sender.call{value: reward}("");
        require(success, "Transfer failed");

        emit RewardClaimed(msg.sender, reward);
    }

    /**
     * @notice Get pending reward for an agent
     * @param agent Agent address
     * @return Pending reward amount
     */
    function getPendingReward(address agent) external view override returns (uint256) {
        return pendingRewards[agent];
    }

    /**
     * @notice Get contribution data for an agent
     * @param agent Agent address
     * @return Contribution data
     */
    function getContribution(address agent) external view override returns (Contribution memory) {
        return contributions[agent];
    }

    /**
     * @notice Set reward formula weights V2 (4 dimensions)
     * @param _tokenWeight Token weight
     * @param _taskWeight Task weight
     * @param _uptimeWeight Uptime weight
     * @param _latencyWeight Latency weight
     */
    function setRewardFormula(uint256 _tokenWeight, uint256 _taskWeight, uint256 _uptimeWeight, uint256 _latencyWeight)
        external
        override
        onlyOwner
    {
        require(_tokenWeight + _taskWeight + _uptimeWeight + _latencyWeight == 100, "Weights must sum to 100");

        tokenWeight = _tokenWeight;
        taskWeight = _taskWeight;
        uptimeWeight = _uptimeWeight;
        latencyWeight = _latencyWeight;

        emit FormulaUpdated(_tokenWeight, _taskWeight, _uptimeWeight, _latencyWeight);
    }

    /**
     * @notice Set agent registry address (for post-genesis configuration)
     * @param _agentRegistry New AgentRegistry address
     */
    function setAgentRegistry(address _agentRegistry) external onlyOwner {
        require(_agentRegistry != address(0), "Invalid registry");
        agentRegistry = IAgentRegistry(_agentRegistry);
    }

    /**
     * @notice Set oracle address
     * @param _oracle New oracle address
     */
    function setOracle(address _oracle) external override onlyOwner {
        require(_oracle != address(0), "Invalid oracle");

        address oldOracle = oracle;
        oracle = _oracle;

        emit OracleUpdated(oldOracle, _oracle);
    }

    /// @notice Emitted when emergency bypass is changed
    event EmergencyBypassRegistryChanged(bool enabled);

    /**
     * @notice Set emergency bypass for AgentRegistry
     * @param enabled Emergency bypass status
     */
    function setEmergencyBypassRegistry(bool enabled) external onlyOwner {
        emergencyBypassRegistry = enabled;
        emit EmergencyBypassRegistryChanged(enabled);
    }

    /**
     * @notice Get current epoch number
     * @return Current epoch
     */
    function getCurrentEpoch() public view returns (uint256) {
        if (block.number <= deployBlock) return 0;
        return (block.number - deployBlock) / BLOCKS_PER_EPOCH;
    }

    /**
     * @notice Calculate agent score based on contributions (V2 formula)
     * @param contribution Contribution data
     * @return Calculated score
     * @dev SECURITY: Weights always sum to 100 (enforced by setRewardFormula)
     *      No division by zero possible. All multiplications are safe due to
     *      input validation (MAX_TASK_COUNT, MAX_PROCESSED_TOKENS, etc.)
     */
    function calculateScore(Contribution memory contribution) internal view returns (uint256) {
        return contribution.processedTokens * tokenWeight + contribution.taskCount * taskWeight
            + contribution.uptimeSeconds * uptimeWeight + contribution.avgLatencyInv * latencyWeight;
    }

    /**
     * @notice Get epoch agents
     * @param epoch Epoch number
     * @return Array of agent addresses
     */
    function getEpochAgents(uint256 epoch) external view returns (address[] memory) {
        return epochAgents[epoch];
    }

    /**
     * @notice Get epoch contribution for an agent
     * @param epoch Epoch number
     * @param agent Agent address
     * @return Contribution data
     */
    function getEpochContribution(uint256 epoch, address agent) external view returns (Contribution memory) {
        return epochContributions[epoch][agent];
    }
}
