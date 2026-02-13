// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "forge-std/Script.sol";
import "../src/AgentRegistry.sol";
import "../src/RewardPool.sol";
import "../src/ChallengeManager.sol";

/**
 * @title Deploy
 * @notice Deployment script for Plumise AI-native blockchain contracts
 * @dev Deploys all three core contracts and sets up their integrations
 */
contract Deploy is Script {
    function run() external {
        // Get deployer private key from environment
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("Deploying contracts...");
        console.log("Deployer:", deployer);
        console.log("Chain ID:", block.chainid);

        vm.startBroadcast(deployerPrivateKey);

        // 1. Deploy AgentRegistry
        console.log("\n1. Deploying AgentRegistry...");
        AgentRegistry agentRegistry = new AgentRegistry();
        console.log("AgentRegistry deployed at:", address(agentRegistry));

        // 2. Deploy RewardPool with AgentRegistry address
        console.log("\n2. Deploying RewardPool...");
        RewardPool rewardPool = new RewardPool(
            address(agentRegistry),
            deployer // Initial oracle (will be updated to ChallengeManager)
        );
        console.log("RewardPool deployed at:", address(rewardPool));

        // 3. Deploy ChallengeManager with AgentRegistry and RewardPool addresses
        console.log("\n3. Deploying ChallengeManager...");
        ChallengeManager challengeManager = new ChallengeManager(address(agentRegistry), address(rewardPool));
        console.log("ChallengeManager deployed at:", address(challengeManager));

        // 4. Set up cross-references
        console.log("\n4. Setting up cross-references...");

        // Set ChallengeManager as oracle for RewardPool
        console.log("Setting ChallengeManager as RewardPool oracle...");
        rewardPool.setOracle(address(challengeManager));
        console.log("Oracle updated successfully");

        // Optional: Set up initial automation address (deployer for now)
        console.log("Setting deployer as automation...");
        challengeManager.setAutomation(deployer, true);
        console.log("Automation configured");

        vm.stopBroadcast();

        // ========== CT-03: Post-Deployment Verification ==========
        console.log("\n=== Post-Deployment Verification ===");

        // 1. Verify contract code deployment
        require(address(agentRegistry).code.length > 0, "AgentRegistry not deployed");
        require(address(rewardPool).code.length > 0, "RewardPool not deployed");
        require(address(challengeManager).code.length > 0, "ChallengeManager not deployed");
        console.log("[PASS] All contracts have code deployed");

        // 2. Verify ownership
        require(agentRegistry.owner() == deployer, "AgentRegistry owner mismatch");
        require(rewardPool.owner() == deployer, "RewardPool owner mismatch");
        require(challengeManager.owner() == deployer, "ChallengeManager owner mismatch");
        console.log("[PASS] All contracts owned by deployer:", deployer);

        // 3. Verify cross-references
        require(address(rewardPool.agentRegistry()) == address(agentRegistry), "RewardPool agentRegistry mismatch");
        require(rewardPool.oracle() == address(challengeManager), "RewardPool oracle mismatch");
        require(
            address(challengeManager.agentRegistry()) == address(agentRegistry),
            "ChallengeManager agentRegistry mismatch"
        );
        require(address(challengeManager.rewardPool()) == address(rewardPool), "ChallengeManager rewardPool mismatch");
        console.log("[PASS] Cross-references configured correctly");

        // 4. Verify initial parameters
        require(rewardPool.tokenWeight() == 40, "RewardPool tokenWeight incorrect");
        require(rewardPool.taskWeight() == 25, "RewardPool taskWeight incorrect");
        require(rewardPool.uptimeWeight() == 20, "RewardPool uptimeWeight incorrect");
        require(rewardPool.latencyWeight() == 15, "RewardPool latencyWeight incorrect");
        require(rewardPool.currentEpoch() == 0, "RewardPool initial epoch should be 0");
        require(rewardPool.deployBlock() == block.number, "RewardPool deployBlock incorrect");
        console.log("[PASS] RewardPool parameters verified");

        // 5. Verify AgentRegistry constants
        require(agentRegistry.HEARTBEAT_TIMEOUT() == 300, "AgentRegistry HEARTBEAT_TIMEOUT incorrect");
        require(agentRegistry.getTotalAgentCount() == 0, "AgentRegistry should have 0 agents initially");
        console.log("[PASS] AgentRegistry initial state verified");

        // 6. Verify ChallengeManager automation
        require(challengeManager.isAutomation(deployer), "Deployer should be automation");
        console.log("[PASS] ChallengeManager automation configured");

        // Print deployment summary
        console.log("\n=== Deployment Summary ===");
        console.log("Chain ID:", block.chainid);
        console.log("Deployer:", deployer);
        console.log("");
        console.log("Deployed Contracts:");
        console.log("  AgentRegistry:     ", address(agentRegistry));
        console.log("  RewardPool:        ", address(rewardPool));
        console.log("  ChallengeManager:  ", address(challengeManager));
        console.log("");
        console.log("Configuration:");
        console.log("  RewardPool.agentRegistry:", address(rewardPool.agentRegistry()));
        console.log("  RewardPool.oracle:       ", rewardPool.oracle());
        console.log("  ChallengeManager.agentRegistry:", address(challengeManager.agentRegistry()));
        console.log("  ChallengeManager.rewardPool:   ", address(challengeManager.rewardPool()));
        console.log("");
        console.log("Next steps:");
        console.log("1. Verify contracts on block explorer");
        console.log("2. Create initial challenge via ChallengeManager");
        console.log("3. Register AI agents via AgentRegistry");
        console.log("4. Fund RewardPool with block rewards or manual transfers");
    }
}
