// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "forge-std/Script.sol";
import "../src/AgentRegistry.sol";
import "../src/RewardPool.sol";

/**
 * @title DeployPostGenesis
 * @notice Post-genesis deployment: AgentRegistry + RewardPool integration
 * @dev RewardPool is already at 0x1000 (genesis). This script:
 *   1. Deploys AgentRegistry
 *   2. Calls RewardPool.setAgentRegistry()
 *   3. Calls RewardPool.setEmergencyBypassRegistry(false)
 */
contract DeployPostGenesis is Script {
    address payable constant REWARD_POOL = payable(0x0000000000000000000000000000000000001000);

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("=== Post-Genesis Deployment ===");
        console.log("Deployer:", deployer);
        console.log("Chain ID:", block.chainid);
        console.log("RewardPool (genesis):", REWARD_POOL);

        vm.startBroadcast(deployerPrivateKey);

        // 1. Deploy AgentRegistry
        AgentRegistry agentRegistry = new AgentRegistry();
        console.log("\n[1/3] AgentRegistry deployed at:", address(agentRegistry));

        // 2. Set AgentRegistry on RewardPool
        RewardPool rewardPool = RewardPool(REWARD_POOL);
        rewardPool.setAgentRegistry(address(agentRegistry));
        console.log("[2/3] RewardPool.setAgentRegistry() done");

        // 3. Disable emergency bypass
        rewardPool.setEmergencyBypassRegistry(false);
        console.log("[3/3] RewardPool.setEmergencyBypassRegistry(false) done");

        vm.stopBroadcast();

        // Verify
        console.log("\n=== Verification ===");
        console.log("RewardPool.agentRegistry():", address(rewardPool.agentRegistry()));
        console.log("RewardPool.emergencyBypassRegistry():", rewardPool.emergencyBypassRegistry());
        console.log("AgentRegistry.owner():", agentRegistry.owner());
    }
}
