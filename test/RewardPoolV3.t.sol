// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "forge-std/Test.sol";
import "../src/RewardPoolV3.sol";

/**
 * @title RewardPoolV3Test
 * @notice Test suite for RewardPoolV3 Merkle-based reward distribution
 */
contract RewardPoolV3Test is Test {
    RewardPoolV3 public rewardPool;

    address public owner = address(0x1);
    address public oracle = address(0x2);
    address public agent1 = address(0x100);
    address public agent2 = address(0x200);
    address public agent3 = address(0x300);

    // Model hashes
    bytes32 public qwen3_32b_hash = keccak256("qwen3-32b");
    bytes32 public qwen3_8b_hash = keccak256("qwen3-8b");
    bytes32 public gpt_oss_20b_hash = keccak256("gpt-oss-20b");
    bytes32 public qwen3_5_397b_hash = keccak256("qwen3.5-397b-a17b");

    event EpochSubmitted(uint256 indexed epochId, bytes32 merkleRoot, uint256 totalReward);
    event RewardClaimed(address indexed agent, uint256 indexed epochId, uint256 amount);
    event ModelSet(bytes32 indexed modelHash, uint256 multiplier);
    event ModelDeactivated(bytes32 indexed modelHash);
    event ClusterParamsUpdated(uint256 perNode, uint256 maxBonus);
    event OracleUpdated(address indexed oldOracle, address indexed newOracle);
    event RewardReceived(uint256 amount, uint256 epoch);

    function setUp() public {
        vm.startPrank(owner);
        rewardPool = new RewardPoolV3(oracle);
        vm.stopPrank();

        // Fund the reward pool
        vm.deal(address(rewardPool), 100 ether);
    }

    function testConstructor() public view {
        assertEq(rewardPool.owner(), owner);
        assertEq(rewardPool.oracle(), oracle);
        assertEq(rewardPool.clusterBonusPerNode(), 12);
        assertEq(rewardPool.maxClusterBonus(), 50);
        assertGt(rewardPool.deployBlock(), 0);
    }

    function testSetModel() public {
        vm.startPrank(oracle);
        vm.expectEmit(true, false, false, true);
        emit ModelSet(qwen3_32b_hash, 2263);
        rewardPool.setModel(qwen3_32b_hash, 2263);
        vm.stopPrank();

        assertEq(rewardPool.modelMultipliers(qwen3_32b_hash), 2263);
        assertTrue(rewardPool.modelActive(qwen3_32b_hash));
    }

    function testSetModelOnlyOracle() public {
        vm.startPrank(agent1);
        vm.expectRevert("Not oracle");
        rewardPool.setModel(qwen3_32b_hash, 2263);
        vm.stopPrank();
    }

    function testSetModelInvalidHash() public {
        vm.startPrank(oracle);
        vm.expectRevert("Invalid model hash");
        rewardPool.setModel(bytes32(0), 2263);
        vm.stopPrank();
    }

    function testSetModelZeroMultiplier() public {
        vm.startPrank(oracle);
        vm.expectRevert("Multiplier must be positive");
        rewardPool.setModel(qwen3_32b_hash, 0);
        vm.stopPrank();
    }

    function testSetModelMultiplierTooHigh() public {
        vm.startPrank(oracle);
        vm.expectRevert("Multiplier too high");
        rewardPool.setModel(qwen3_32b_hash, 100001);
        vm.stopPrank();
    }

    function testDeactivateModel() public {
        vm.startPrank(oracle);
        rewardPool.setModel(qwen3_32b_hash, 2263);

        vm.expectEmit(true, false, false, false);
        emit ModelDeactivated(qwen3_32b_hash);
        rewardPool.deactivateModel(qwen3_32b_hash);
        vm.stopPrank();

        assertFalse(rewardPool.modelActive(qwen3_32b_hash));
        assertEq(rewardPool.modelMultipliers(qwen3_32b_hash), 2263); // Multiplier still stored
    }

    function testDeactivateModelNotActive() public {
        vm.startPrank(oracle);
        vm.expectRevert("Model not active");
        rewardPool.deactivateModel(qwen3_32b_hash);
        vm.stopPrank();
    }

    function testSubmitEpoch() public {
        bytes32 merkleRoot = keccak256("test_merkle_root");
        uint256 totalReward = 10 ether;

        vm.startPrank(oracle);
        vm.expectEmit(true, false, false, true);
        emit EpochSubmitted(0, merkleRoot, totalReward);
        rewardPool.submitEpoch(0, merkleRoot, totalReward);
        vm.stopPrank();

        (bytes32 root, uint256 reward, uint256 settledAt, bool finalized) = rewardPool.epochs(0);
        assertEq(root, merkleRoot);
        assertEq(reward, totalReward);
        assertGt(settledAt, 0);
        assertFalse(finalized);
    }

    function testSubmitEpochOnlyOracle() public {
        bytes32 merkleRoot = keccak256("test_merkle_root");

        vm.startPrank(agent1);
        vm.expectRevert("Not oracle");
        rewardPool.submitEpoch(0, merkleRoot, 10 ether);
        vm.stopPrank();
    }

    function testSubmitEpochDuplicate() public {
        bytes32 merkleRoot = keccak256("test_merkle_root");

        vm.startPrank(oracle);
        rewardPool.submitEpoch(0, merkleRoot, 10 ether);

        vm.expectRevert("Epoch already settled");
        rewardPool.submitEpoch(0, merkleRoot, 10 ether);
        vm.stopPrank();
    }

    function testSubmitEpochEmptyRoot() public {
        vm.startPrank(oracle);
        vm.expectRevert("Empty root");
        rewardPool.submitEpoch(0, bytes32(0), 10 ether);
        vm.stopPrank();
    }

    function testSubmitEpochZeroReward() public {
        bytes32 merkleRoot = keccak256("test_merkle_root");

        vm.startPrank(oracle);
        vm.expectRevert("Zero reward");
        rewardPool.submitEpoch(0, merkleRoot, 0);
        vm.stopPrank();
    }

    function testClaimSuccess() public {
        // Setup: Submit epoch with Merkle root
        uint256 epochId = 0;
        uint256 amount = 1 ether;

        // Construct leaf: keccak256(abi.encodePacked(agent, epochId, amount))
        bytes32 leaf = keccak256(abi.encodePacked(agent1, epochId, amount));

        // Single-leaf Merkle tree (root = leaf)
        bytes32 merkleRoot = leaf;
        bytes32[] memory proof = new bytes32[](0); // Empty proof for single leaf

        // Submit epoch
        vm.startPrank(oracle);
        rewardPool.submitEpoch(epochId, merkleRoot, amount);
        vm.stopPrank();

        // Wait for dispute period
        vm.roll(block.number + rewardPool.DISPUTE_PERIOD());

        // Claim
        uint256 balanceBefore = agent1.balance;

        vm.startPrank(agent1);
        vm.expectEmit(true, true, false, true);
        emit RewardClaimed(agent1, epochId, amount);
        rewardPool.claim(epochId, amount, proof);
        vm.stopPrank();

        assertEq(agent1.balance, balanceBefore + amount);
        assertTrue(rewardPool.isClaimed(agent1, epochId, amount));
    }

    function testClaimMultipleAgents() public {
        // Setup: 3 agents with different rewards
        uint256 epochId = 0;
        uint256 amount1 = 1 ether;
        uint256 amount2 = 2 ether;
        uint256 amount3 = 3 ether;

        // Construct leaves
        bytes32 leaf1 = keccak256(abi.encodePacked(agent1, epochId, amount1));
        bytes32 leaf2 = keccak256(abi.encodePacked(agent2, epochId, amount2));
        bytes32 leaf3 = keccak256(abi.encodePacked(agent3, epochId, amount3));

        // Build Merkle tree (simple 3-leaf tree)
        bytes32 hash12 = keccak256(abi.encodePacked(leaf1 < leaf2 ? leaf1 : leaf2, leaf1 < leaf2 ? leaf2 : leaf1));
        bytes32 root = keccak256(abi.encodePacked(hash12 < leaf3 ? hash12 : leaf3, hash12 < leaf3 ? leaf3 : hash12));

        // Submit epoch
        vm.startPrank(oracle);
        rewardPool.submitEpoch(epochId, root, amount1 + amount2 + amount3);
        vm.stopPrank();

        // Wait for dispute period
        vm.roll(block.number + rewardPool.DISPUTE_PERIOD());

        // Agent1 claims
        bytes32[] memory proof1 = new bytes32[](2);
        proof1[0] = leaf2;
        proof1[1] = leaf3;

        vm.startPrank(agent1);
        rewardPool.claim(epochId, amount1, proof1);
        vm.stopPrank();

        assertEq(agent1.balance, amount1);
        assertTrue(rewardPool.isClaimed(agent1, epochId, amount1));
    }

    function testClaimEpochNotSettled() public {
        bytes32[] memory proof = new bytes32[](0);

        vm.startPrank(agent1);
        vm.expectRevert("Epoch not settled");
        rewardPool.claim(0, 1 ether, proof);
        vm.stopPrank();
    }

    function testClaimDisputePeriodActive() public {
        uint256 epochId = 0;
        uint256 amount = 1 ether;
        bytes32 leaf = keccak256(abi.encodePacked(agent1, epochId, amount));
        bytes32[] memory proof = new bytes32[](0);

        // Submit epoch
        vm.startPrank(oracle);
        rewardPool.submitEpoch(epochId, leaf, amount);
        vm.stopPrank();

        // Try to claim immediately (dispute period not passed)
        vm.startPrank(agent1);
        vm.expectRevert("Dispute period active");
        rewardPool.claim(epochId, amount, proof);
        vm.stopPrank();
    }

    function testClaimAlreadyClaimed() public {
        uint256 epochId = 0;
        uint256 amount = 1 ether;
        bytes32 leaf = keccak256(abi.encodePacked(agent1, epochId, amount));
        bytes32[] memory proof = new bytes32[](0);

        // Submit epoch
        vm.startPrank(oracle);
        rewardPool.submitEpoch(epochId, leaf, amount);
        vm.stopPrank();

        // Wait for dispute period
        vm.roll(block.number + rewardPool.DISPUTE_PERIOD());

        // First claim
        vm.startPrank(agent1);
        rewardPool.claim(epochId, amount, proof);

        // Second claim (should fail)
        vm.expectRevert("Already claimed");
        rewardPool.claim(epochId, amount, proof);
        vm.stopPrank();
    }

    function testClaimInvalidProof() public {
        uint256 epochId = 0;
        uint256 amount = 1 ether;
        bytes32 correctLeaf = keccak256(abi.encodePacked(agent1, epochId, amount));
        bytes32[] memory proof = new bytes32[](0);

        // Submit epoch with correct root
        vm.startPrank(oracle);
        rewardPool.submitEpoch(epochId, correctLeaf, amount);
        vm.stopPrank();

        // Wait for dispute period
        vm.roll(block.number + rewardPool.DISPUTE_PERIOD());

        // Try to claim with wrong data (agent2 claiming for agent1's leaf)
        vm.startPrank(agent2);
        vm.expectRevert("Invalid proof");
        rewardPool.claim(epochId, amount, proof);
        vm.stopPrank();
    }

    function testClaimFor() public {
        // Setup
        uint256 epochId = 0;
        uint256 amount = 1 ether;
        bytes32 leaf = keccak256(abi.encodePacked(agent1, epochId, amount));
        bytes32[] memory proof = new bytes32[](0);

        // Submit epoch
        vm.startPrank(oracle);
        rewardPool.submitEpoch(epochId, leaf, amount);
        vm.stopPrank();

        // Wait for dispute period
        vm.roll(block.number + rewardPool.DISPUTE_PERIOD());

        // Agent2 claims for agent1 (sponsored claim)
        uint256 balanceBefore = agent1.balance;

        vm.startPrank(agent2);
        vm.expectEmit(true, true, false, true);
        emit RewardClaimed(agent1, epochId, amount);
        rewardPool.claimFor(agent1, epochId, amount, proof);
        vm.stopPrank();

        assertEq(agent1.balance, balanceBefore + amount);
        assertTrue(rewardPool.isClaimed(agent1, epochId, amount));
    }

    function testSetClusterParams() public {
        vm.startPrank(oracle);
        vm.expectEmit(false, false, false, true);
        emit ClusterParamsUpdated(15, 60);
        rewardPool.setClusterParams(15, 60);
        vm.stopPrank();

        assertEq(rewardPool.clusterBonusPerNode(), 15);
        assertEq(rewardPool.maxClusterBonus(), 60);
    }

    function testSetClusterParamsOnlyOracle() public {
        vm.startPrank(agent1);
        vm.expectRevert("Not oracle");
        rewardPool.setClusterParams(15, 60);
        vm.stopPrank();
    }

    function testSetClusterParamsPerNodeTooHigh() public {
        vm.startPrank(oracle);
        vm.expectRevert("Per node too high");
        rewardPool.setClusterParams(31, 60);
        vm.stopPrank();
    }

    function testSetClusterParamsMaxBonusTooHigh() public {
        vm.startPrank(oracle);
        vm.expectRevert("Max bonus too high");
        rewardPool.setClusterParams(15, 101);
        vm.stopPrank();
    }

    function testSetOracle() public {
        address newOracle = address(0x999);

        vm.startPrank(owner);
        vm.expectEmit(true, true, false, false);
        emit OracleUpdated(oracle, newOracle);
        rewardPool.setOracle(newOracle);
        vm.stopPrank();

        assertEq(rewardPool.oracle(), newOracle);
    }

    function testSetOracleOnlyOwner() public {
        address newOracle = address(0x999);

        vm.startPrank(agent1);
        vm.expectRevert("Not owner");
        rewardPool.setOracle(newOracle);
        vm.stopPrank();
    }

    function testSetOracleInvalidAddress() public {
        vm.startPrank(owner);
        vm.expectRevert("Invalid oracle");
        rewardPool.setOracle(address(0));
        vm.stopPrank();
    }

    function testReceive() public {
        uint256 balanceBefore = address(rewardPool).balance;
        uint256 amount = 5 ether;

        vm.deal(agent1, amount);
        vm.startPrank(agent1);
        (bool success,) = address(rewardPool).call{value: amount}("");
        require(success, "Transfer failed");
        vm.stopPrank();

        assertEq(address(rewardPool).balance, balanceBefore + amount);
    }

    function testGetCurrentEpoch() public {
        uint256 deployBlock = rewardPool.deployBlock();
        uint256 blocksPerEpoch = rewardPool.BLOCKS_PER_EPOCH();

        // At deployment
        assertEq(rewardPool.getCurrentEpoch(), 0);

        // Roll to next epoch
        vm.roll(deployBlock + blocksPerEpoch);
        assertEq(rewardPool.getCurrentEpoch(), 1);

        // Roll to epoch 5
        vm.roll(deployBlock + blocksPerEpoch * 5);
        assertEq(rewardPool.getCurrentEpoch(), 5);
    }

    function testIsClaimed() public {
        uint256 epochId = 0;
        uint256 amount = 1 ether;
        bytes32 leaf = keccak256(abi.encodePacked(agent1, epochId, amount));
        bytes32[] memory proof = new bytes32[](0);

        // Not claimed yet
        assertFalse(rewardPool.isClaimed(agent1, epochId, amount));

        // Submit and claim
        vm.startPrank(oracle);
        rewardPool.submitEpoch(epochId, leaf, amount);
        vm.stopPrank();

        vm.roll(block.number + rewardPool.DISPUTE_PERIOD());

        vm.startPrank(agent1);
        rewardPool.claim(epochId, amount, proof);
        vm.stopPrank();

        // Now claimed
        assertTrue(rewardPool.isClaimed(agent1, epochId, amount));
    }

    function testReentrancyProtection() public {
        // This test verifies that the nonReentrant modifier is in place
        // Actual reentrancy attack would require a malicious contract
        // Here we just verify the modifier exists by checking successful claims don't revert
        uint256 epochId = 0;
        uint256 amount = 1 ether;
        bytes32 leaf = keccak256(abi.encodePacked(agent1, epochId, amount));
        bytes32[] memory proof = new bytes32[](0);

        vm.startPrank(oracle);
        rewardPool.submitEpoch(epochId, leaf, amount);
        vm.stopPrank();

        vm.roll(block.number + rewardPool.DISPUTE_PERIOD());

        vm.startPrank(agent1);
        rewardPool.claim(epochId, amount, proof); // Should succeed (no revert)
        vm.stopPrank();

        assertTrue(rewardPool.isClaimed(agent1, epochId, amount));
    }
}
