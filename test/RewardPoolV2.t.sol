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
 * @title RewardPoolV2Test
 * @notice Test suite for RewardPool V2 contract with Phase 2 metrics
 */
contract RewardPoolV2Test is Test {
    RewardPool public rewardPool;
    MockAgentRegistry public registry;

    address public owner;
    address public oracle;
    address public agent1;
    address public agent2;
    address public agent3;

    event ContributionReported(
        address indexed agent,
        uint256 taskCount,
        uint256 uptimeSeconds,
        uint256 responseScore,
        uint256 processedTokens,
        uint256 avgLatencyInv,
        uint256 epoch
    );
    event FormulaUpdated(uint256 tokenWeight, uint256 taskWeight, uint256 uptimeWeight, uint256 latencyWeight);

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

    function test_V2_Constructor() public view {
        // Check V2 weights
        assertEq(rewardPool.tokenWeight(), 40);
        assertEq(rewardPool.taskWeight(), 25);
        assertEq(rewardPool.uptimeWeight(), 20);
        assertEq(rewardPool.latencyWeight(), 15);
    }

    function test_V2_ReportContribution() public {
        vm.startPrank(oracle);

        uint256 epoch = rewardPool.getCurrentEpoch();

        vm.expectEmit(true, true, true, true);
        emit ContributionReported(agent1, 10, 3600, 95, 50000, 100, epoch);

        rewardPool.reportContribution(agent1, 10, 3600, 95, 50000, 100);

        IRewardPool.Contribution memory contrib = rewardPool.getContribution(agent1);
        assertEq(contrib.taskCount, 10);
        assertEq(contrib.uptimeSeconds, 3600);
        assertEq(contrib.responseScore, 95);
        assertEq(contrib.processedTokens, 50000);
        assertEq(contrib.avgLatencyInv, 100);

        vm.stopPrank();
    }

    function test_V2_BackwardCompatibility() public {
        vm.startPrank(oracle);

        // Use old V1 function (4 params)
        rewardPool.reportContribution(agent1, 10, 3600, 95);

        IRewardPool.Contribution memory contrib = rewardPool.getContribution(agent1);
        assertEq(contrib.taskCount, 10);
        assertEq(contrib.uptimeSeconds, 3600);
        assertEq(contrib.responseScore, 95);
        assertEq(contrib.processedTokens, 0); // Should be 0
        assertEq(contrib.avgLatencyInv, 0); // Should be 0

        vm.stopPrank();
    }

    function test_V2_SetRewardFormula() public {
        vm.expectEmit(true, true, true, true);
        emit FormulaUpdated(30, 30, 25, 15);

        rewardPool.setRewardFormula(30, 30, 25, 15);

        assertEq(rewardPool.tokenWeight(), 30);
        assertEq(rewardPool.taskWeight(), 30);
        assertEq(rewardPool.uptimeWeight(), 25);
        assertEq(rewardPool.latencyWeight(), 15);
    }

    function test_V2_SetRewardFormula_InvalidWeights() public {
        vm.expectRevert("Weights must sum to 100");
        rewardPool.setRewardFormula(40, 25, 20, 20); // Sum = 105
    }

    function test_V2_DistributeRewards_WithPhase2Metrics() public {
        // Send rewards to pool
        uint256 rewardAmount = 10 ether;
        (bool success,) = address(rewardPool).call{value: rewardAmount}("");
        assertTrue(success);

        // Report contributions with Phase 2 metrics
        // Formula: processedTokens × 40 + taskCount × 25 + uptimeSeconds × 20 + avgLatencyInv × 15
        vm.startPrank(oracle);
        rewardPool.reportContribution(agent1, 10, 3600, 90, 100000, 1000);
        // score1 = 100000*40 + 10*25 + 3600*20 + 1000*15 = 4000000 + 250 + 72000 + 15000 = 4087250

        rewardPool.reportContribution(agent2, 5, 1800, 95, 50000, 500);
        // score2 = 50000*40 + 5*25 + 1800*20 + 500*15 = 2000000 + 125 + 36000 + 7500 = 2043625

        rewardPool.reportContribution(agent3, 8, 2700, 85, 75000, 800);
        // score3 = 75000*40 + 8*25 + 2700*20 + 800*15 = 3000000 + 200 + 54000 + 12000 = 3066200
        vm.stopPrank();

        // Move to next epoch
        vm.roll(block.number + 1200);

        // Distribute rewards
        rewardPool.distributeRewards(0);

        // Total score = 4087250 + 2043625 + 3066200 = 9197075
        uint256 totalScore = 9197075;
        uint256 reward1 = (rewardAmount * 4087250) / totalScore;
        uint256 reward2 = (rewardAmount * 2043625) / totalScore;
        uint256 reward3 = rewardAmount - reward1 - reward2; // Remainder

        assertEq(rewardPool.getPendingReward(agent1), reward1);
        assertEq(rewardPool.getPendingReward(agent2), reward2);
        assertEq(rewardPool.getPendingReward(agent3), reward3);

        // Verify no dust loss
        assertEq(reward1 + reward2 + reward3, rewardAmount);
    }

    function test_V2_ValidationBounds() public {
        vm.startPrank(oracle);

        // Test MAX_PROCESSED_TOKENS
        vm.expectRevert("Processed tokens too high");
        rewardPool.reportContribution(agent1, 10, 3600, 95, 100_000_001, 100);

        // Test MAX_LATENCY_INV
        vm.expectRevert("Latency inv too high");
        rewardPool.reportContribution(agent1, 10, 3600, 95, 50000, 10_001);

        // Valid values at maximum
        rewardPool.reportContribution(agent1, 10_000, 604_800, 1_000_000, 100_000_000, 10_000);

        IRewardPool.Contribution memory contrib = rewardPool.getContribution(agent1);
        assertEq(contrib.taskCount, 10_000);
        assertEq(contrib.processedTokens, 100_000_000);
        assertEq(contrib.avgLatencyInv, 10_000);

        vm.stopPrank();
    }

    function test_V2_MixedV1V2Contributions() public {
        vm.startPrank(oracle);

        // Agent1 uses V1
        rewardPool.reportContribution(agent1, 10, 3600, 90);

        // Agent2 uses V2
        rewardPool.reportContribution(agent2, 5, 1800, 95, 50000, 500);

        IRewardPool.Contribution memory contrib1 = rewardPool.getContribution(agent1);
        assertEq(contrib1.processedTokens, 0);
        assertEq(contrib1.avgLatencyInv, 0);

        IRewardPool.Contribution memory contrib2 = rewardPool.getContribution(agent2);
        assertEq(contrib2.processedTokens, 50000);
        assertEq(contrib2.avgLatencyInv, 500);

        vm.stopPrank();
    }

    function testFuzz_V2_ReportContribution(
        uint256 taskCount,
        uint256 uptimeSeconds,
        uint256 responseScore,
        uint256 processedTokens,
        uint256 avgLatencyInv
    ) public {
        // Bound inputs to validation limits
        taskCount = bound(taskCount, 0, 10_000);
        uptimeSeconds = bound(uptimeSeconds, 0, 604_800);
        responseScore = bound(responseScore, 0, 1_000_000);
        processedTokens = bound(processedTokens, 0, 100_000_000);
        avgLatencyInv = bound(avgLatencyInv, 0, 10_000);

        vm.prank(oracle);
        rewardPool.reportContribution(agent1, taskCount, uptimeSeconds, responseScore, processedTokens, avgLatencyInv);

        IRewardPool.Contribution memory contrib = rewardPool.getContribution(agent1);
        assertEq(contrib.taskCount, taskCount);
        assertEq(contrib.uptimeSeconds, uptimeSeconds);
        assertEq(contrib.responseScore, responseScore);
        assertEq(contrib.processedTokens, processedTokens);
        assertEq(contrib.avgLatencyInv, avgLatencyInv);
    }

    receive() external payable {}
}
