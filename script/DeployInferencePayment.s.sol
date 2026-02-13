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

        // ========== CT-03: Post-Deployment Verification ==========
        console.log("\n=== Post-Deployment Verification ===");

        // 1. Verify contract code deployment
        require(address(inferencePayment).code.length > 0, "InferencePayment not deployed");
        console.log("[PASS] Contract has code deployed");

        // 2. Verify ownership
        require(inferencePayment.owner() == deployer, "Owner should be deployer");
        console.log("[PASS] Owner verified:", deployer);

        // 3. Verify initial parameters
        require(inferencePayment.gateway() == deployer, "Gateway should be deployer initially");
        require(inferencePayment.treasury() == FOUNDATION_TREASURY, "Treasury should be Foundation");
        console.log("[PASS] Gateway and Treasury verified");

        // 4. Verify constants
        require(inferencePayment.PRO_TIER_MINIMUM() == 100 ether, "PRO_TIER_MINIMUM should be 100 PLM");
        require(inferencePayment.costPer1000Tokens() == 0.001 ether, "costPer1000Tokens should be 0.001 PLM");
        console.log("[PASS] Constants verified");

        // 5. Verify treasury address is valid (not zero)
        require(FOUNDATION_TREASURY != address(0), "Treasury address is zero");
        console.log("[PASS] Treasury address is non-zero");

        // 6. Test getUserTier on zero address (should return 0 for Free tier)
        uint256 zeroAddressTier = inferencePayment.getUserTier(address(0));
        require(zeroAddressTier == 0, "getUserTier(0x0) should be 0");
        console.log("[PASS] getUserTier for zero address returns Free tier");

        // 7. Verify getUserBalance on zero address (should be 0)
        uint256 zeroBalance = inferencePayment.getUserBalance(address(0));
        require(zeroBalance == 0, "Zero address should have 0 balance");
        console.log("[PASS] Zero address has 0 balance");

        // Verify deployment
        console.log("\n=== Verification ===");
        console.log("Owner:", inferencePayment.owner());
        console.log("Gateway:", inferencePayment.gateway());
        console.log("Treasury:", inferencePayment.treasury());
        console.log("PRO_TIER_MINIMUM:", inferencePayment.PRO_TIER_MINIMUM() / 1 ether, "PLM");
        console.log("Cost per 1000 tokens:", inferencePayment.costPer1000Tokens());

        console.log("\n=== Deployment Complete ===");
        console.log("Contract Address:", address(inferencePayment));
        console.log("\nNext steps:");
        console.log("1. Update gateway address via setGateway() when inference-api is ready");
        console.log("2. Adjust cost via setCostPer1000Tokens() if needed");
        console.log("3. Users can deposit PLM to get Pro tier access (min 100 PLM)");
    }
}
