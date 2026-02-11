// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "forge-std/Script.sol";
import "../src/InferencePayment.sol";

/**
 * @title DeployInferencePayment
 * @notice Deploys InferencePayment contract for AI inference payment on Plumise
 * @dev Constructor parameters:
 *   - gateway: inference-api gateway address (initially deployer, can be updated later)
 *   - treasury: Foundation Treasury at 0x1001 for collecting fees
 */
contract DeployInferencePayment is Script {
    address constant FOUNDATION_TREASURY = 0x0000000000000000000000000000000000001001;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("=== InferencePayment Deployment ===");
        console.log("Deployer:", deployer);
        console.log("Chain ID:", block.chainid);
        console.log("Gateway (initial):", deployer);
        console.log("Treasury:", FOUNDATION_TREASURY);

        vm.startBroadcast(deployerPrivateKey);

        // Deploy InferencePayment
        // - gateway: deployer address (can be updated later via setGateway)
        // - treasury: Foundation Treasury
        InferencePayment inferencePayment = new InferencePayment(deployer, FOUNDATION_TREASURY);
        console.log("\n[1/1] InferencePayment deployed at:", address(inferencePayment));

        vm.stopBroadcast();

        // Verify deployment
        console.log("\n=== Verification ===");
        console.log("Owner:", inferencePayment.owner());
        console.log("Gateway:", inferencePayment.gateway());
        console.log("Treasury:", inferencePayment.treasury());
        console.log("PRO_TIER_MINIMUM:", inferencePayment.PRO_TIER_MINIMUM() / 1 ether, "PLM");
        console.log("Cost per 1000 tokens:", inferencePayment.costPer1000Tokens());

        // Test getUserTier on zero address (should return 0 for Free tier)
        uint256 zeroAddressTier = inferencePayment.getUserTier(address(0));
        console.log("getUserTier(0x0):", zeroAddressTier, "(should be 0)");
        require(zeroAddressTier == 0, "getUserTier verification failed");

        console.log("\n=== Deployment Complete ===");
        console.log("Contract Address:", address(inferencePayment));
        console.log("\nNext steps:");
        console.log("1. Update gateway address via setGateway() when inference-api is ready");
        console.log("2. Adjust cost via setCostPer1000Tokens() if needed");
        console.log("3. Users can deposit PLM to get Pro tier access (min 100 PLM)");
    }
}
