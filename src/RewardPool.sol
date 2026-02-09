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
 */
contract RewardPool is IRewardPool, Ownable, ReentrancyGuard {
    /// @notice Blocks per epoch (1200 blocks = 1 hour at 3s blocks)
    uint256 public constant BLOCKS_PER_EPOCH = 1200;

    /// @notice Agent registry contract (not immutable for genesis compatibility)
    IAgentRegistry public agentRegistry;

    /// @notice Oracle address authorized to report contributions
    address public oracle;

    /// @notice Reward formula weights (out of 100)
    uint256 public taskWeight = 50;
    uint256 public uptimeWeight = 30;
    uint256 public responseWeight = 20;

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
        require(currentBalance > lastTrackedBalance, "No new rewards");

        uint256 newRewards = currentBalance - lastTrackedBalance;
        uint256 epoch = getCurrentEpoch();

        epochRewards[epoch] += newRewards;
        lastTrackedBalance = currentBalance;

        emit RewardReceived(newRewards, epoch);
    }

    /**
     * @notice Report agent contribution (only oracle)
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
    ) external override {
        require(msg.sender == oracle, "Only oracle");
        require(agentRegistry.isRegistered(agent), "Agent not registered");
        require(agentRegistry.isActive(agent), "Agent not active");

        uint256 epoch = getCurrentEpoch();

        // Update cumulative contributions
        contributions[agent].taskCount += taskCount;
        contributions[agent].uptimeSeconds += uptimeSeconds;
        contributions[agent].responseScore += responseScore;
        contributions[agent].lastUpdated = block.timestamp;

        // Update epoch contributions
        if (!epochAgentExists[epoch][agent]) {
            epochAgents[epoch].push(agent);
            epochAgentExists[epoch][agent] = true;
        }

        epochContributions[epoch][agent].taskCount += taskCount;
        epochContributions[epoch][agent].uptimeSeconds += uptimeSeconds;
        epochContributions[epoch][agent].responseScore += responseScore;
        epochContributions[epoch][agent].lastUpdated = block.timestamp;

        emit ContributionReported(agent, taskCount, uptimeSeconds, responseScore, epoch);
    }

    /**
     * @notice Distribute rewards for an epoch
     * @param epoch Epoch number to distribute
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

        // Calculate total score
        uint256 totalScore = 0;
        for (uint256 i = 0; i < agentCount; i++) {
            address agent = agents[i];
            uint256 score = calculateScore(epochContributions[epoch][agent]);
            totalScore += score;
        }

        if (totalScore == 0) {
            // No valid contributions
            epochDistributed[epoch] = true;
            emit RewardsDistributed(epoch, 0, 0);
            return;
        }

        // Distribute rewards proportionally
        for (uint256 i = 0; i < agentCount; i++) {
            address agent = agents[i];
            uint256 score = calculateScore(epochContributions[epoch][agent]);
            
            if (score > 0) {
                uint256 reward = (totalReward * score) / totalScore;
                pendingRewards[agent] += reward;
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

        // Update tracked balance after transfer
        (bool success, ) = msg.sender.call{value: reward}("");
        require(success, "Transfer failed");

        lastTrackedBalance = address(this).balance;
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
     * @notice Set reward formula weights
     * @param _taskWeight Task weight
     * @param _uptimeWeight Uptime weight
     * @param _responseWeight Response weight
     */
    function setRewardFormula(
        uint256 _taskWeight,
        uint256 _uptimeWeight,
        uint256 _responseWeight
    ) external override onlyOwner {
        require(_taskWeight + _uptimeWeight + _responseWeight == 100, "Weights must sum to 100");
        
        taskWeight = _taskWeight;
        uptimeWeight = _uptimeWeight;
        responseWeight = _responseWeight;

        emit FormulaUpdated(_taskWeight, _uptimeWeight, _responseWeight);
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

    /**
     * @notice Get current epoch number
     * @return Current epoch
     */
    function getCurrentEpoch() public view returns (uint256) {
        return (block.number - deployBlock) / BLOCKS_PER_EPOCH;
    }

    /**
     * @notice Calculate agent score based on contributions
     * @param contribution Contribution data
     * @return Calculated score
     */
    function calculateScore(Contribution memory contribution) internal view returns (uint256) {
        return 
            contribution.taskCount * taskWeight +
            contribution.uptimeSeconds * uptimeWeight +
            contribution.responseScore * responseWeight;
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
