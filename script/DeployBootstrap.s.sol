// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "forge-std/Script.sol";
import "../src/ChallengeManager.sol";
import "../src/RewardPool.sol";
import "../src/interfaces/IEcosystemFund.sol";

/**
 * @title DeployBootstrap
 * @notice Bootstrap deployment: ChallengeManager + deployer funding + oracle setup
 * @dev Requires zero-fee transactions (baseFee=0 bootstrapping mode)
 */
contract DeployBootstrap is Script {
    address payable constant REWARD_POOL = payable(0x0000000000000000000000000000000000001000);
    address constant AGENT_REGISTRY = 0xC9CF64344D22f02f6cDB8e7B5349f30E09F9043C;
    address constant ECOSYSTEM_FUND = 0x0000000000000000000000000000000000001002;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("=== Bootstrap Deployment ===");
        console.log("Deployer:", deployer);
        console.log("Chain ID:", block.chainid);

        vm.startBroadcast(deployerPrivateKey);

        // 1. Deploy ChallengeManager
        ChallengeManager challengeManager = new ChallengeManager(AGENT_REGISTRY, REWARD_POOL);
        console.log("\n[1/4] ChallengeManager deployed at:", address(challengeManager));

        // 2. Set oracle (deployer) as automation on ChallengeManager
        challengeManager.setAutomation(deployer, true);
        console.log("[2/4] ChallengeManager.setAutomation(deployer) done");

        // 3. Fund deployer from EcosystemFund (100 PLM for operations)
        IEcosystemFund ecosystemFund = IEcosystemFund(ECOSYSTEM_FUND);
        ecosystemFund.transfer(deployer, 100 ether);
        console.log("[3/4] EcosystemFund.transfer(deployer, 100 PLM) done");

        // 4. Set ChallengeManager as authorized caller on RewardPool
        RewardPool rewardPool = RewardPool(REWARD_POOL);
        rewardPool.setOracle(deployer);
        console.log("[4/4] RewardPool.setOracle(deployer) done");

        vm.stopBroadcast();

        // Verify
        console.log("\n=== Verification ===");
        console.log("ChallengeManager:", address(challengeManager));
        console.log("ChallengeManager.owner():", challengeManager.owner());
        console.log("isAutomation(deployer):", challengeManager.isAutomation(deployer));
        console.log("Deployer balance:", deployer.balance);
    }
}
