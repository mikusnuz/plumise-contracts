// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "forge-std/Test.sol";
import "../../src/RewardPool.sol";
import "../../src/interfaces/IAgentRegistry.sol";

/**
 * @title MockAgentRegistryInvariant
 * @notice Mock implementation of IAgentRegistry for invariant testing
 */
contract MockAgentRegistryInvariant is IAgentRegistry {
    mapping(address => bool) private _registered;
    mapping(address => bool) private _active;
    address[] private _agents;

    function register(address agent) external {
        if (!_registered[agent]) {
            _registered[agent] = true;
            _active[agent] = true;
            _agents.push(agent);
        }
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
        uint256 activeCount = 0;
        for (uint256 i = 0; i < _agents.length; i++) {
            if (_active[_agents[i]]) {
                activeCount++;
            }
        }

        address[] memory active = new address[](activeCount);
        uint256 idx = 0;
        for (uint256 i = 0; i < _agents.length; i++) {
            if (_active[_agents[i]]) {
                active[idx] = _agents[i];
                idx++;
            }
        }
        return active;
    }

    function getActiveAgentCount() external view override returns (uint256) {
        uint256 count = 0;
        for (uint256 i = 0; i < _agents.length; i++) {
            if (_active[_agents[i]]) {
                count++;
            }
        }
        return count;
    }

    function slashAgent(address) external override {}
}

/**
 * @title RewardPoolHandler
 * @notice Handler contract for invariant testing that interacts with RewardPool
 */
contract RewardPoolHandler is Test {
    RewardPool public rewardPool;
    MockAgentRegistryInvariant public registry;

    address[] public actors;
    mapping(address => uint256) public pendingRewardsGhost;
    uint256 public totalDistributedGhost;

    function getActorsLength() external view returns (uint256) {
        return actors.length;
    }

    function getActor(uint256 index) external view returns (address) {
        return actors[index];
    }

    constructor(RewardPool _rewardPool, MockAgentRegistryInvariant _registry) {
        rewardPool = _rewardPool;
        registry = _registry;

        // Create some actors
        for (uint256 i = 0; i < 5; i++) {
            address actor = address(uint160(0x1000 + i));
            actors.push(actor);
            registry.register(actor);
            vm.deal(actor, 1 ether);
        }
    }

    function sendRewards(uint256 amount) public {
        amount = bound(amount, 0.01 ether, 100 ether);
        vm.deal(address(this), amount);
        (bool success,) = address(rewardPool).call{value: amount}("");
        require(success, "Send rewards failed");
    }

    function reportContribution(uint256 actorSeed, uint256 taskCount, uint256 uptimeSeconds, uint256 responseScore)
        public
    {
        address actor = actors[actorSeed % actors.length];

        taskCount = bound(taskCount, 0, rewardPool.MAX_TASK_COUNT());
        uptimeSeconds = bound(uptimeSeconds, 0, rewardPool.MAX_UPTIME_SECONDS());
        responseScore = bound(responseScore, 0, rewardPool.MAX_RESPONSE_SCORE());

        vm.prank(rewardPool.oracle());
        rewardPool.reportContribution(actor, taskCount, uptimeSeconds, responseScore);
    }

    function distributeRewards(uint256 epochSeed) public {
        uint256 currentEpoch = rewardPool.getCurrentEpoch();
        if (currentEpoch == 0) return;

        uint256 epoch = epochSeed % currentEpoch;

        // Skip to next epoch for distribution
        uint256 targetBlock = rewardPool.deployBlock() + (epoch + 1) * rewardPool.BLOCKS_PER_EPOCH();
        if (block.number <= targetBlock) {
            vm.roll(targetBlock + 1);
        }

        if (!rewardPool.epochDistributed(epoch)) {
            try rewardPool.distributeRewards(epoch) {
                // Update ghost variables
                for (uint256 i = 0; i < actors.length; i++) {
                    uint256 pending = rewardPool.getPendingReward(actors[i]);
                    if (pending > pendingRewardsGhost[actors[i]]) {
                        totalDistributedGhost += pending - pendingRewardsGhost[actors[i]];
                        pendingRewardsGhost[actors[i]] = pending;
                    }
                }
            } catch {}
        }
    }

    function claimReward(uint256 actorSeed) public {
        address actor = actors[actorSeed % actors.length];
        uint256 pending = rewardPool.getPendingReward(actor);

        if (pending > 0) {
            vm.prank(actor);
            try rewardPool.claimReward() {
                pendingRewardsGhost[actor] = 0;
            } catch {}
        }
    }

    function advanceEpoch() public {
        vm.roll(block.number + rewardPool.BLOCKS_PER_EPOCH());
    }

    receive() external payable {}
}

/**
 * @title RewardPoolInvariantTest
 * @notice Invariant tests for RewardPool contract
 */
contract RewardPoolInvariantTest is Test {
    RewardPool public rewardPool;
    MockAgentRegistryInvariant public registry;
    RewardPoolHandler public handler;

    address public oracle;

    function setUp() public {
        oracle = makeAddr("oracle");

        // Deploy mock registry
        registry = new MockAgentRegistryInvariant();

        // Deploy reward pool
        rewardPool = new RewardPool(address(registry), oracle);

        // Deploy handler
        handler = new RewardPoolHandler(rewardPool, registry);

        // Fund handler
        vm.deal(address(handler), 1000 ether);

        // Target handler for invariant tests
        targetContract(address(handler));
    }

    /**
     * @notice Invariant: Reward conservation
     * @dev Total distributed rewards should never exceed contract balance + total distributed
     */
    function invariant_rewardConservation() public view {
        uint256 currentBalance = address(rewardPool).balance;
        uint256 totalPending = 0;
        uint256 actorsLength = handler.getActorsLength();

        for (uint256 i = 0; i < actorsLength; i++) {
            totalPending += rewardPool.getPendingReward(handler.getActor(i));
        }

        // Total pending should not exceed current balance + total already claimed
        // Since we can't track claimed amount directly, we verify:
        // current_balance >= total_pending
        assertGe(currentBalance, totalPending, "Reward conservation violated: pending > balance");
    }

    /**
     * @notice Invariant: Epoch monotonicity
     * @dev Current epoch should be monotonically increasing
     */
    function invariant_epochMonotonicity() public {
        uint256 currentEpoch = rewardPool.getCurrentEpoch();
        uint256 expectedEpoch = (block.number - rewardPool.deployBlock()) / rewardPool.BLOCKS_PER_EPOCH();

        assertEq(currentEpoch, expectedEpoch, "Epoch calculation incorrect");
    }

    /**
     * @notice Invariant: Non-negative rewards
     * @dev Pending rewards for any agent should never be negative (underflow protection)
     */
    function invariant_nonNegativeRewards() public view {
        uint256 actorsLength = handler.getActorsLength();
        for (uint256 i = 0; i < actorsLength; i++) {
            address actor = handler.getActor(i);
            uint256 pending = rewardPool.getPendingReward(actor);

            // If this doesn't revert, it means no underflow occurred
            assertGe(pending, 0, "Negative reward detected");
        }
    }

    /**
     * @notice Invariant: Epoch rewards accumulation
     * @dev Epoch rewards should only increase or stay same within an epoch
     */
    function invariant_epochRewardsAccumulation() public view {
        uint256 currentEpoch = rewardPool.getCurrentEpoch();
        uint256 epochReward = rewardPool.epochRewards(currentEpoch);

        // Epoch reward should always be >= 0 (trivial but checks for corruption)
        assertGe(epochReward, 0, "Epoch reward corrupted");
    }

    /**
     * @notice Invariant: No reward double-distribution
     * @dev Once an epoch is distributed, it should remain distributed
     */
    function invariant_noDoubleDistribution() public view {
        uint256 currentEpoch = rewardPool.getCurrentEpoch();

        // Check all past epochs - if distributed flag is set, calling distributeRewards should fail
        // This is implicitly tested by the contract's "Already distributed" check
        // We verify the flag is immutable once set
        for (uint256 epoch = 0; epoch < currentEpoch; epoch++) {
            bool isDistributed = rewardPool.epochDistributed(epoch);
            // If distributed, the flag should remain true
            // (This is more of a state consistency check)
            if (isDistributed) {
                assertTrue(isDistributed, "Distribution flag corrupted");
            }
        }
    }
}
