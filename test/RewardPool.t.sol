// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "forge-std/Test.sol";
import "../src/RewardPool.sol";
import "../src/interfaces/IAgentRegistry.sol";

/**
 * @title MockAgentRegistry
 * @notice Mock implementation of IAgentRegistry for testing
 */
contract MockAgentRegistry is IAgentRegistry {
    mapping(address => bool) private _registered;
    mapping(address => bool) private _active;

    function register(address agent) external {
        _registered[agent] = true;
        _active[agent] = true;
    }

    function deactivate(address agent) external {
        _active[agent] = false;
    }

    function isRegistered(address agent) external view override returns (bool) {
        return _registered[agent];
    }

    function isActive(address agent) external view override returns (bool) {
        return _active[agent];
    }

    // Stub implementations for interface compliance
    function registerAgent(bytes32, string memory) external override {}
    function heartbeat() external override {}
    function updateMetadata(string memory) external override {}
    function deregisterAgent() external override {}

    function getAgent(address) external view override returns (Agent memory) {
        return Agent(address(0), bytes32(0), "", 0, 0, AgentStatus.INACTIVE, 0);
    }

    function getActiveAgents() external view override returns (address[] memory) {
        return new address[](0);
    }

    function getActiveAgentCount() external view override returns (uint256) {
        return 0;
    }
    function slashAgent(address) external override {}
}

/**
 * @title RewardPoolTest
 * @notice Test suite for RewardPool contract
 */
contract RewardPoolTest is Test {
    RewardPool public rewardPool;
    MockAgentRegistry public registry;

    address public owner;
    address public oracle;
    address public agent1;
    address public agent2;
    address public agent3;

    event RewardReceived(uint256 amount, uint256 epoch);
    event ContributionReported(
        address indexed agent,
        uint256 taskCount,
        uint256 uptimeSeconds,
        uint256 responseScore,
        uint256 processedTokens,
        uint256 avgLatencyInv,
        uint256 epoch
    );
    event RewardsDistributed(uint256 indexed epoch, uint256 totalReward, uint256 agentCount);
    event RewardClaimed(address indexed agent, uint256 amount);
    event FormulaUpdated(uint256 tokenWeight, uint256 taskWeight, uint256 uptimeWeight, uint256 latencyWeight);
    event OracleUpdated(address indexed oldOracle, address indexed newOracle);

    function setUp() public {
        owner = address(this);
        oracle = makeAddr("oracle");
        agent1 = makeAddr("agent1");
        agent2 = makeAddr("agent2");
        agent3 = makeAddr("agent3");

        // Deploy mock registry
        registry = new MockAgentRegistry();

        // Register agents
        registry.register(agent1);
        registry.register(agent2);
        registry.register(agent3);

        // Deploy reward pool
        rewardPool = new RewardPool(address(registry), oracle);

        // Fund agents for gas
        vm.deal(agent1, 1 ether);
        vm.deal(agent2, 1 ether);
        vm.deal(agent3, 1 ether);
    }

    function test_Constructor() public view {
        assertEq(address(rewardPool.agentRegistry()), address(registry));
        assertEq(rewardPool.oracle(), oracle);
        assertEq(rewardPool.tokenWeight(), 40);
        assertEq(rewardPool.taskWeight(), 25);
        assertEq(rewardPool.uptimeWeight(), 20);
        assertEq(rewardPool.latencyWeight(), 15);
        assertEq(rewardPool.currentEpoch(), 0);
    }

    function test_ReceiveRewards() public {
        uint256 epoch = rewardPool.getCurrentEpoch();
        uint256 rewardAmount = 10 ether;

        vm.expectEmit(true, true, true, true);
        emit RewardReceived(rewardAmount, epoch);

        (bool success,) = address(rewardPool).call{value: rewardAmount}("");
        assertTrue(success);

        assertEq(rewardPool.epochRewards(epoch), rewardAmount);
    }

    function test_ReportContribution() public {
        vm.startPrank(oracle);

        uint256 epoch = rewardPool.getCurrentEpoch();

        vm.expectEmit(true, true, true, true);
        emit ContributionReported(agent1, 10, 3600, 95, 0, 0, epoch);

        rewardPool.reportContribution(agent1, 10, 3600, 95);

        IRewardPool.Contribution memory contrib = rewardPool.getContribution(agent1);
        assertEq(contrib.taskCount, 10);
        assertEq(contrib.uptimeSeconds, 3600);
        assertEq(contrib.responseScore, 95);

        vm.stopPrank();
    }

    function test_ReportContribution_OnlyOracle() public {
        vm.startPrank(agent1);

        vm.expectRevert("Only oracle");
        rewardPool.reportContribution(agent1, 10, 3600, 95);

        vm.stopPrank();
    }

    function test_ReportContribution_NotRegistered() public {
        address unregistered = makeAddr("unregistered");

        vm.startPrank(oracle);

        vm.expectRevert("Agent not registered");
        rewardPool.reportContribution(unregistered, 10, 3600, 95);

        vm.stopPrank();
    }

    function test_ReportContribution_NotActive() public {
        registry.deactivate(agent1);

        vm.startPrank(oracle);

        vm.expectRevert("Agent not active");
        rewardPool.reportContribution(agent1, 10, 3600, 95);

        vm.stopPrank();
    }

    function test_DistributeRewards_SingleAgent() public {
        // Send rewards to pool
        uint256 rewardAmount = 10 ether;
        (bool success,) = address(rewardPool).call{value: rewardAmount}("");
        assertTrue(success);

        // Report contribution
        vm.prank(oracle);
        rewardPool.reportContribution(agent1, 10, 3600, 95);

        // Move to next epoch
        vm.roll(block.number + 1200);

        // Distribute rewards
        uint256 epoch = 0;
        vm.expectEmit(true, true, true, true);
        emit RewardsDistributed(epoch, rewardAmount, 1);

        rewardPool.distributeRewards(epoch);

        // Check pending rewards (should get all rewards)
        assertEq(rewardPool.getPendingReward(agent1), rewardAmount);
    }

    function test_DistributeRewards_MultipleAgents() public {
        // Send rewards to pool
        uint256 rewardAmount = 10 ether;
        (bool success,) = address(rewardPool).call{value: rewardAmount}("");
        assertTrue(success);

        // Report contributions with different scores
        // V2 formula: processedTokens * 40 + taskCount * 25 + uptimeSeconds * 20 + avgLatencyInv * 15
        // Using V1 (backward compat): processedTokens=0, avgLatencyInv=0
        vm.startPrank(oracle);
        rewardPool.reportContribution(agent1, 10, 3600, 90); // score = 0*40 + 10*25 + 3600*20 + 0*15 = 250 + 72000 = 72250
        rewardPool.reportContribution(agent2, 5, 1800, 95); // score = 0*40 + 5*25 + 1800*20 + 0*15 = 125 + 36000 = 36125
        rewardPool.reportContribution(agent3, 8, 2700, 85); // score = 0*40 + 8*25 + 2700*20 + 0*15 = 200 + 54000 = 54200
        vm.stopPrank();

        // Move to next epoch
        vm.roll(block.number + 1200);

        // Distribute rewards
        rewardPool.distributeRewards(0);

        // Total score = 72250 + 36125 + 54200 = 162575
        uint256 totalScore = 162575;
        uint256 reward1 = (rewardAmount * 72250) / totalScore;
        uint256 reward2 = (rewardAmount * 36125) / totalScore;
        // reward3 gets the remainder due to dust prevention
        uint256 reward3 = rewardAmount - reward1 - reward2;

        assertEq(rewardPool.getPendingReward(agent1), reward1);
        assertEq(rewardPool.getPendingReward(agent2), reward2);
        assertEq(rewardPool.getPendingReward(agent3), reward3);

        // Verify total equals reward amount (no dust loss)
        assertEq(reward1 + reward2 + reward3, rewardAmount);
    }

    function test_DistributeRewards_NoContributions() public {
        // Send rewards to pool
        uint256 rewardAmount = 10 ether;
        (bool success,) = address(rewardPool).call{value: rewardAmount}("");
        assertTrue(success);

        // Move to next epoch without any contributions
        vm.roll(block.number + 1200);

        // Distribute - no agents so epochDistributed but rewards stay
        // Contract emits RewardsDistributed(epoch, 0, 0) for 0-agent case
        vm.expectEmit(true, true, true, true);
        emit RewardsDistributed(0, 0, 0);

        rewardPool.distributeRewards(0);

        // Rewards should stay in pool
        assertEq(rewardPool.epochRewards(0), rewardAmount);
    }

    function test_DistributeRewards_AlreadyDistributed() public {
        // Send rewards and report contribution
        (bool success,) = address(rewardPool).call{value: 10 ether}("");
        assertTrue(success);

        vm.prank(oracle);
        rewardPool.reportContribution(agent1, 10, 3600, 95);

        // Move to next epoch
        vm.roll(block.number + 1200);

        // Distribute once
        rewardPool.distributeRewards(0);

        // Try to distribute again
        vm.expectRevert("Already distributed");
        rewardPool.distributeRewards(0);
    }

    function test_DistributeRewards_EpochNotEnded() public {
        vm.expectRevert("Epoch not ended");
        rewardPool.distributeRewards(0);
    }

    function test_ClaimReward() public {
        // Send rewards and report contribution
        uint256 rewardAmount = 10 ether;
        (bool success,) = address(rewardPool).call{value: rewardAmount}("");
        assertTrue(success);

        vm.prank(oracle);
        rewardPool.reportContribution(agent1, 10, 3600, 95);

        // Move to next epoch and distribute
        vm.roll(block.number + 1200);
        rewardPool.distributeRewards(0);

        // Claim reward
        uint256 balanceBefore = agent1.balance;
        uint256 pendingReward = rewardPool.getPendingReward(agent1);

        vm.startPrank(agent1);
        vm.expectEmit(true, true, true, true);
        emit RewardClaimed(agent1, pendingReward);

        rewardPool.claimReward();
        vm.stopPrank();

        assertEq(agent1.balance, balanceBefore + pendingReward);
        assertEq(rewardPool.getPendingReward(agent1), 0);
    }

    function test_ClaimReward_NotRegistered() public {
        address unregistered = makeAddr("unregistered");

        vm.startPrank(unregistered);
        vm.expectRevert("Not registered");
        rewardPool.claimReward();
        vm.stopPrank();
    }

    function test_ClaimReward_NoRewards() public {
        vm.startPrank(agent1);
        vm.expectRevert("No rewards");
        rewardPool.claimReward();
        vm.stopPrank();
    }

    function test_SetRewardFormula() public {
        vm.expectEmit(true, true, true, true);
        emit FormulaUpdated(30, 30, 25, 15);

        rewardPool.setRewardFormula(30, 30, 25, 15);

        assertEq(rewardPool.tokenWeight(), 30);
        assertEq(rewardPool.taskWeight(), 30);
        assertEq(rewardPool.uptimeWeight(), 25);
        assertEq(rewardPool.latencyWeight(), 15);
    }

    function test_SetRewardFormula_InvalidWeights() public {
        vm.expectRevert("Weights must sum to 100");
        rewardPool.setRewardFormula(50, 30, 30, 10);
    }

    function test_SetRewardFormula_OnlyOwner() public {
        vm.startPrank(agent1);
        vm.expectRevert();
        rewardPool.setRewardFormula(30, 30, 25, 15);
        vm.stopPrank();
    }

    function test_SetOracle() public {
        address newOracle = makeAddr("newOracle");

        vm.expectEmit(true, true, true, true);
        emit OracleUpdated(oracle, newOracle);

        rewardPool.setOracle(newOracle);

        assertEq(rewardPool.oracle(), newOracle);
    }

    function test_SetOracle_InvalidAddress() public {
        vm.expectRevert("Invalid oracle");
        rewardPool.setOracle(address(0));
    }

    function test_SetOracle_OnlyOwner() public {
        address newOracle = makeAddr("newOracle");

        vm.startPrank(agent1);
        vm.expectRevert();
        rewardPool.setOracle(newOracle);
        vm.stopPrank();
    }

    function test_GetCurrentEpoch() public {
        assertEq(rewardPool.getCurrentEpoch(), 0);

        vm.roll(block.number + 1200);
        assertEq(rewardPool.getCurrentEpoch(), 1);

        vm.roll(block.number + 1200);
        assertEq(rewardPool.getCurrentEpoch(), 2);
    }

    function test_MultipleEpochs() public {
        // Epoch 0: agent1 contributes
        (bool success,) = address(rewardPool).call{value: 5 ether}("");
        assertTrue(success);

        vm.prank(oracle);
        rewardPool.reportContribution(agent1, 10, 3600, 90);

        // Move to epoch 1
        vm.roll(block.number + 1200);

        // Epoch 1: agent2 contributes
        (success,) = address(rewardPool).call{value: 5 ether}("");
        assertTrue(success);

        vm.prank(oracle);
        rewardPool.reportContribution(agent2, 8, 2700, 95);

        // Move to epoch 2
        vm.roll(block.number + 1200);

        // Distribute epoch 0
        rewardPool.distributeRewards(0);
        assertEq(rewardPool.getPendingReward(agent1), 5 ether);

        // Distribute epoch 1
        rewardPool.distributeRewards(1);
        assertEq(rewardPool.getPendingReward(agent2), 5 ether);
    }

    function test_GetEpochAgents() public {
        vm.startPrank(oracle);
        rewardPool.reportContribution(agent1, 10, 3600, 90);
        rewardPool.reportContribution(agent2, 5, 1800, 95);
        vm.stopPrank();

        address[] memory agents = rewardPool.getEpochAgents(0);
        assertEq(agents.length, 2);
        assertEq(agents[0], agent1);
        assertEq(agents[1], agent2);
    }

    function test_GetEpochContribution() public {
        vm.prank(oracle);
        rewardPool.reportContribution(agent1, 10, 3600, 90);

        IRewardPool.Contribution memory contrib = rewardPool.getEpochContribution(0, agent1);
        assertEq(contrib.taskCount, 10);
        assertEq(contrib.uptimeSeconds, 3600);
        assertEq(contrib.responseScore, 90);
    }

    function testFuzz_ReportContribution(uint256 taskCount, uint256 uptimeSeconds, uint256 responseScore) public {
        // Bound inputs to validation limits
        taskCount = bound(taskCount, 0, 10_000);
        uptimeSeconds = bound(uptimeSeconds, 0, 604_800);
        responseScore = bound(responseScore, 0, 1_000_000);

        vm.prank(oracle);
        rewardPool.reportContribution(agent1, taskCount, uptimeSeconds, responseScore);

        IRewardPool.Contribution memory contrib = rewardPool.getContribution(agent1);
        assertEq(contrib.taskCount, taskCount);
        assertEq(contrib.uptimeSeconds, uptimeSeconds);
        assertEq(contrib.responseScore, responseScore);
    }

    function testFuzz_DistributeRewards(uint256 rewardAmount) public {
        vm.assume(rewardAmount > 0 && rewardAmount <= 1000 ether);

        // Send rewards
        vm.deal(address(this), rewardAmount);
        (bool success,) = address(rewardPool).call{value: rewardAmount}("");
        assertTrue(success);

        // Report contribution
        vm.prank(oracle);
        rewardPool.reportContribution(agent1, 10, 3600, 95);

        // Move to next epoch and distribute
        vm.roll(block.number + 1200);
        rewardPool.distributeRewards(0);

        // Agent should get all rewards
        assertEq(rewardPool.getPendingReward(agent1), rewardAmount);
    }

    receive() external payable {}
}
