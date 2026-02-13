// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "forge-std/Test.sol";
import "../src/AgentRegistry.sol";
import "../src/RewardPool.sol";
import "../src/ChallengeManager.sol";
import "../src/InferencePayment.sol";

/**
 * @title DeploymentVerificationTest
 * @notice CT-03: Tests deployment scripts verification logic
 * @dev Simulates deployment and verifies all post-deployment checks
 */
contract DeploymentVerificationTest is Test {
    address public deployer;

    function setUp() public {
        deployer = address(this);
    }

    /**
     * @notice Test: Full deployment verification (Deploy.s.sol)
     */
    function test_FullDeploymentVerification() public {
        // 1. Deploy AgentRegistry
        AgentRegistry agentRegistry = new AgentRegistry();

        // 2. Deploy RewardPool
        RewardPool rewardPool = new RewardPool(
            address(agentRegistry),
            deployer // Initial oracle
        );

        // 3. Deploy ChallengeManager
        ChallengeManager challengeManager = new ChallengeManager(address(agentRegistry), address(rewardPool));

        // 4. Configure
        rewardPool.setOracle(address(challengeManager));
        challengeManager.setAutomation(deployer, true);

        // ========== CT-03: Verification Checks ==========

        // Verify contract code deployment
        assertTrue(address(agentRegistry).code.length > 0, "AgentRegistry not deployed");
        assertTrue(address(rewardPool).code.length > 0, "RewardPool not deployed");
        assertTrue(address(challengeManager).code.length > 0, "ChallengeManager not deployed");

        // Verify ownership
        assertEq(agentRegistry.owner(), deployer, "AgentRegistry owner mismatch");
        assertEq(rewardPool.owner(), deployer, "RewardPool owner mismatch");
        assertEq(challengeManager.owner(), deployer, "ChallengeManager owner mismatch");

        // Verify cross-references
        assertEq(address(rewardPool.agentRegistry()), address(agentRegistry), "RewardPool agentRegistry mismatch");
        assertEq(rewardPool.oracle(), address(challengeManager), "RewardPool oracle mismatch");
        assertEq(
            address(challengeManager.agentRegistry()), address(agentRegistry), "ChallengeManager agentRegistry mismatch"
        );
        assertEq(address(challengeManager.rewardPool()), address(rewardPool), "ChallengeManager rewardPool mismatch");

        // Verify initial parameters
        assertEq(rewardPool.tokenWeight(), 40, "RewardPool tokenWeight incorrect");
        assertEq(rewardPool.taskWeight(), 25, "RewardPool taskWeight incorrect");
        assertEq(rewardPool.uptimeWeight(), 20, "RewardPool uptimeWeight incorrect");
        assertEq(rewardPool.latencyWeight(), 15, "RewardPool latencyWeight incorrect");
        assertEq(rewardPool.currentEpoch(), 0, "RewardPool initial epoch should be 0");
        assertEq(rewardPool.deployBlock(), block.number, "RewardPool deployBlock incorrect");

        // Verify AgentRegistry constants
        assertEq(agentRegistry.HEARTBEAT_TIMEOUT(), 300, "AgentRegistry HEARTBEAT_TIMEOUT incorrect");
        assertEq(agentRegistry.getTotalAgentCount(), 0, "AgentRegistry should have 0 agents initially");

        // Verify ChallengeManager automation
        assertTrue(challengeManager.isAutomation(deployer), "Deployer should be automation");
    }

    /**
     * @notice Test: Post-genesis deployment verification (DeployPostGenesis.s.sol)
     * @dev Simplified test without vm.etch complications
     */
    function test_PostGenesisDeploymentVerification() public {
        // Deploy RewardPool (simulating genesis contract)
        AgentRegistry dummyRegistry = new AgentRegistry();
        RewardPool rewardPool = new RewardPool(address(dummyRegistry), deployer);

        // Enable emergency bypass (simulating genesis state)
        rewardPool.setEmergencyBypassRegistry(true);

        // Deploy AgentRegistry
        AgentRegistry agentRegistry = new AgentRegistry();

        // Configure RewardPool (post-genesis setup)
        rewardPool.setAgentRegistry(address(agentRegistry));
        rewardPool.setEmergencyBypassRegistry(false);

        // ========== CT-03: Verification Checks ==========

        // Verify contract code deployment
        assertTrue(address(agentRegistry).code.length > 0, "AgentRegistry not deployed");
        assertTrue(address(rewardPool).code.length > 0, "RewardPool not deployed (genesis)");

        // Verify ownership
        assertEq(agentRegistry.owner(), deployer, "AgentRegistry owner mismatch");
        assertEq(rewardPool.owner(), deployer, "RewardPool owner mismatch");

        // Verify RewardPool configuration
        assertEq(address(rewardPool.agentRegistry()), address(agentRegistry), "RewardPool agentRegistry mismatch");
        assertFalse(rewardPool.emergencyBypassRegistry(), "Emergency bypass should be disabled");

        // Verify AgentRegistry initial state
        assertEq(agentRegistry.HEARTBEAT_TIMEOUT(), 300, "HEARTBEAT_TIMEOUT incorrect");
        assertEq(agentRegistry.getTotalAgentCount(), 0, "Initial agent count should be 0");
    }

    /**
     * @notice Test: InferencePayment deployment verification (DeployInferencePayment.s.sol)
     */
    function test_InferencePaymentDeploymentVerification() public {
        address FOUNDATION_TREASURY = 0x0000000000000000000000000000000000001001;

        // Deploy InferencePayment
        InferencePayment inferencePayment = new InferencePayment(deployer, FOUNDATION_TREASURY);

        // ========== CT-03: Verification Checks ==========

        // Verify contract code deployment
        assertTrue(address(inferencePayment).code.length > 0, "InferencePayment not deployed");

        // Verify ownership
        assertEq(inferencePayment.owner(), deployer, "Owner should be deployer");

        // Verify initial parameters
        assertEq(inferencePayment.gateway(), deployer, "Gateway should be deployer initially");
        assertEq(inferencePayment.treasury(), FOUNDATION_TREASURY, "Treasury should be Foundation");

        // Verify constants
        assertEq(inferencePayment.PRO_TIER_MINIMUM(), 100 ether, "PRO_TIER_MINIMUM should be 100 PLM");
        assertEq(inferencePayment.costPer1000Tokens(), 0.001 ether, "costPer1000Tokens should be 0.001 PLM");

        // Verify treasury address is valid (not zero)
        assertTrue(FOUNDATION_TREASURY != address(0), "Treasury address is zero");

        // Test getUserTier on zero address (should return 0 for Free tier)
        uint256 zeroAddressTier = inferencePayment.getUserTier(address(0));
        assertEq(zeroAddressTier, 0, "getUserTier(0x0) should be 0");

        // Verify getUserBalance on zero address (should be 0)
        uint256 zeroBalance = inferencePayment.getUserBalance(address(0));
        assertEq(zeroBalance, 0, "Zero address should have 0 balance");
    }

    /**
     * @notice Test: Detect owner mismatch
     */
    function test_DetectOwnerMismatch() public {
        AgentRegistry agentRegistry = new AgentRegistry();

        // Transfer ownership to someone else
        address newOwner = makeAddr("newOwner");
        agentRegistry.transferOwnership(newOwner);

        // Verification detects mismatch
        assertNotEq(agentRegistry.owner(), deployer, "Should detect owner mismatch");
    }

    /**
     * @notice Test: Detect contract not deployed
     */
    function test_DetectContractNotDeployed() public {
        address fakeContract = makeAddr("fakeContract");

        // No code at address - verification would fail
        assertEq(fakeContract.code.length, 0, "Contract has no code");
    }

    /**
     * @notice Test: Detect parameters incorrect
     */
    function test_DetectParametersIncorrect() public {
        AgentRegistry agentRegistry = new AgentRegistry();
        RewardPool rewardPool = new RewardPool(address(agentRegistry), address(this));

        // Change parameters
        rewardPool.setRewardFormula(50, 25, 15, 10); // Wrong values

        // Verification detects mismatch
        assertNotEq(rewardPool.tokenWeight(), 40, "Should detect tokenWeight mismatch");
    }

    /**
     * @notice Test: Detect cross-references wrong
     */
    function test_DetectCrossReferencesWrong() public {
        AgentRegistry agentRegistry = new AgentRegistry();
        RewardPool rewardPool = new RewardPool(address(agentRegistry), address(this));
        ChallengeManager challengeManager = new ChallengeManager(address(agentRegistry), address(rewardPool));

        // Don't set oracle - verification would detect this
        assertNotEq(rewardPool.oracle(), address(challengeManager), "Should detect oracle mismatch");
    }

    /**
     * @notice Test: InferencePayment fails if treasury is zero
     */
    function test_RevertIf_TreasuryIsZero() public {
        vm.expectRevert("Invalid treasury");
        new InferencePayment(deployer, address(0));
    }

    /**
     * @notice Test: InferencePayment fails if gateway is zero
     */
    function test_RevertIf_GatewayIsZero() public {
        address FOUNDATION_TREASURY = 0x0000000000000000000000000000000000001001;

        vm.expectRevert("Invalid gateway");
        new InferencePayment(address(0), FOUNDATION_TREASURY);
    }
}
