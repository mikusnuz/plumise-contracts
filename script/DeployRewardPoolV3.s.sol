// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "forge-std/Script.sol";
import "../src/RewardPoolV3.sol";

/**
 * @title DeployRewardPoolV3
 * @notice Deployment script for RewardPoolV3 with initial model registry
 * @dev Usage: forge script script/DeployRewardPoolV3.s.sol:DeployRewardPoolV3 --rpc-url <RPC> --broadcast
 */
contract DeployRewardPoolV3 is Script {
    // Model multipliers (computed from PRD formula)
    uint256 constant QWEN3_1_7B_MULTIPLIER = 157; // 1.57x
    uint256 constant QWEN3_8B_MULTIPLIER = 650; // 6.50x
    uint256 constant GPT_OSS_20B_MULTIPLIER = 1507; // 15.07x
    uint256 constant QWEN3_32B_MULTIPLIER = 2263; // 22.63x
    uint256 constant QWEN3_5_397B_MULTIPLIER = 2277; // 22.77x

    function run() external {
        // Get deployer private key from environment
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("Deploying RewardPoolV3...");
        console.log("Deployer:", deployer);

        vm.startBroadcast(deployerPrivateKey);

        // Deploy RewardPoolV3 (oracle = deployer)
        RewardPoolV3 rewardPool = new RewardPoolV3(deployer);

        console.log("RewardPoolV3 deployed at:", address(rewardPool));
        console.log("Owner:", rewardPool.owner());
        console.log("Oracle:", rewardPool.oracle());
        console.log("Deploy Block:", rewardPool.deployBlock());

        // Register initial models
        console.log("\n=== Registering Models ===");

        // Qwen3-1.7B (lightweight option)
        bytes32 qwen3_1_7b_hash = keccak256("qwen3-1.7b");
        rewardPool.setModel(qwen3_1_7b_hash, QWEN3_1_7B_MULTIPLIER);
        console.log("Qwen3-1.7B:", uint256(qwen3_1_7b_hash));
        console.log("  Multiplier: 157 (1.57x)");

        // Qwen3-8B (primary lightweight model)
        bytes32 qwen3_8b_hash = keccak256("qwen3-8b");
        rewardPool.setModel(qwen3_8b_hash, QWEN3_8B_MULTIPLIER);
        console.log("Qwen3-8B:", uint256(qwen3_8b_hash));
        console.log("  Multiplier: 650 (6.50x)");

        // GPT-OSS-20B (legacy, active for transition)
        bytes32 gpt_oss_20b_hash = keccak256("gpt-oss-20b");
        rewardPool.setModel(gpt_oss_20b_hash, GPT_OSS_20B_MULTIPLIER);
        console.log("GPT-OSS-20B:", uint256(gpt_oss_20b_hash));
        console.log("  Multiplier: 1507 (15.07x)");

        // Qwen3-32B (primary mid-range model)
        bytes32 qwen3_32b_hash = keccak256("qwen3-32b");
        rewardPool.setModel(qwen3_32b_hash, QWEN3_32B_MULTIPLIER);
        console.log("Qwen3-32B:", uint256(qwen3_32b_hash));
        console.log("  Multiplier: 2263 (22.63x)");

        // Qwen3.5-397B-A17B (cluster-only flagship)
        bytes32 qwen3_5_397b_hash = keccak256("qwen3.5-397b-a17b");
        rewardPool.setModel(qwen3_5_397b_hash, QWEN3_5_397B_MULTIPLIER);
        console.log("Qwen3.5-397B-A17B:", uint256(qwen3_5_397b_hash));
        console.log("  Multiplier: 2277 (22.77x)");

        console.log("\n=== Deployment Summary ===");
        console.log("Contract: RewardPoolV3");
        console.log("Address:", address(rewardPool));
        console.log("Blocks per epoch:", rewardPool.BLOCKS_PER_EPOCH());
        console.log("Dispute period:", rewardPool.DISPUTE_PERIOD());
        console.log("Cluster bonus per node:", rewardPool.clusterBonusPerNode());
        console.log("Max cluster bonus:", rewardPool.maxClusterBonus());

        vm.stopBroadcast();

        console.log("\n=== Next Steps ===");
        console.log("1. Verify contract on explorer");
        console.log("2. Update Geth consensus to redirect block rewards to new address");
        console.log("3. Set RewardPoolV3Block fork in Geth");
        console.log("4. Update Oracle to use v3 formula and Merkle tree generation");
        console.log("5. Update agent-app to claim from v3 contract");
    }
}
