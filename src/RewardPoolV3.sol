// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title RewardPoolV3
 * @notice Merkle-based reward distribution with multi-model support
 * @dev Supersedes RewardPool v2 with O(1) epoch settlement and O(log N) claims
 *
 * ARCHITECTURE:
 * - Oracle computes rewards off-chain and submits Merkle root per epoch
 * - Each agent claims their reward individually with a Merkle proof
 * - Dispute period allows for root challenges before claims activate
 *
 * SECURITY:
 * - Merkle proof verification prevents unauthorized claims
 * - Single-use leaf hashes prevent double claiming
 * - Dispute period allows off-chain verification before finalization
 * - ReentrancyGuard protects claim functions
 *
 * REWARD FORMULA V3 (computed off-chain by Oracle):
 * - UCU = verified_tokens × (multiplier / 100) × clusterBonus
 * - score = UCU × reliability × latencyFactor
 * - Only Router-signed tickets count (anti-farming)
 */
contract RewardPoolV3 is ReentrancyGuard {
    /// @notice Contract owner (can update oracle)
    address public owner;

    /// @notice Oracle address (authorized to submit epochs and manage models)
    address public oracle;

    /// @notice Blocks per epoch (1200 blocks = 1 hour at 3s blocks)
    uint256 public constant BLOCKS_PER_EPOCH = 1200;

    /// @notice Dispute period in blocks (~10 minutes at 3s/block)
    uint256 public constant DISPUTE_PERIOD = 200;

    /// @notice Block number when contract was deployed
    uint256 public deployBlock;

    /// @notice Last tracked balance for reward accounting
    uint256 public lastTrackedBalance;

    /// @notice Cluster bonus per extra node (in basis points, 12 = 0.12x)
    uint256 public clusterBonusPerNode = 12;

    /// @notice Maximum cluster bonus (in basis points, 50 = 0.50x)
    uint256 public maxClusterBonus = 50;

    /// @notice Model registry: modelHash => multiplier (e.g., 1507 = 15.07x)
    mapping(bytes32 => uint256) public modelMultipliers;

    /// @notice Model active status: modelHash => active
    mapping(bytes32 => bool) public modelActive;

    /// @notice Epoch settlement data
    struct EpochSettlement {
        bytes32 merkleRoot; // Merkle root of (agent, epochId, amount) leaves
        uint256 totalReward; // Total reward for this epoch
        uint256 settledAt; // Block number when submitted
        bool finalized; // Reserved for future dispute resolution
    }

    /// @notice Epoch settlements: epochId => EpochSettlement
    mapping(uint256 => EpochSettlement) public epochs;

    /// @notice Claim tracking: leaf hash => claimed
    mapping(bytes32 => bool) public claimed;

    /// @notice Emitted when epoch is submitted
    event EpochSubmitted(uint256 indexed epochId, bytes32 merkleRoot, uint256 totalReward);

    /// @notice Emitted when reward is claimed
    event RewardClaimed(address indexed agent, uint256 indexed epochId, uint256 amount);

    /// @notice Emitted when model is registered or updated
    event ModelSet(bytes32 indexed modelHash, uint256 multiplier);

    /// @notice Emitted when model is deactivated
    event ModelDeactivated(bytes32 indexed modelHash);

    /// @notice Emitted when cluster parameters are updated
    event ClusterParamsUpdated(uint256 perNode, uint256 maxBonus);

    /// @notice Emitted when oracle is updated
    event OracleUpdated(address indexed oldOracle, address indexed newOracle);

    /// @notice Emitted when rewards are received (block rewards or donations)
    event RewardReceived(uint256 amount, uint256 epoch);

    /// @notice Modifier to restrict to owner
    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }

    /// @notice Modifier to restrict to oracle
    modifier onlyOracle() {
        require(msg.sender == oracle, "Not oracle");
        _;
    }

    /**
     * @notice Constructor
     * @param _oracle Oracle address
     */
    constructor(address _oracle) {
        require(_oracle != address(0), "Invalid oracle");

        owner = msg.sender;
        oracle = _oracle;
        deployBlock = block.number;
        lastTrackedBalance = 0;
    }

    /**
     * @notice Receive block rewards from Geth
     * @dev Block rewards are sent via state.AddBalance() which triggers receive()
     */
    receive() external payable {
        _syncRewards();
    }

    /**
     * @notice Sync rewards from balance changes
     * @dev Accounts for block rewards added via state.AddBalance()
     */
    function _syncRewards() internal {
        uint256 currentBalance = address(this).balance;
        if (currentBalance > lastTrackedBalance) {
            uint256 newRewards = currentBalance - lastTrackedBalance;
            uint256 epoch = getCurrentEpoch();
            lastTrackedBalance = currentBalance;
            emit RewardReceived(newRewards, epoch);
        }
    }

    /**
     * @notice Register or update a model's multiplier
     * @param modelHash keccak256 hash of model ID (e.g., keccak256("qwen3-32b"))
     * @param multiplier Model multiplier in basis points (e.g., 2263 = 22.63x)
     * @dev Only oracle can call. Multiplier formula (off-chain):
     *      multiplier = floor((active_B + 0.04 × (total_B - active_B))^0.9 × 100)
     */
    function setModel(bytes32 modelHash, uint256 multiplier) external onlyOracle {
        require(modelHash != bytes32(0), "Invalid model hash");
        require(multiplier > 0, "Multiplier must be positive");
        require(multiplier <= 100000, "Multiplier too high"); // Max 1000x

        modelMultipliers[modelHash] = multiplier;
        modelActive[modelHash] = true;

        emit ModelSet(modelHash, multiplier);
    }

    /**
     * @notice Deactivate a model (deprecation)
     * @param modelHash Model hash to deactivate
     * @dev Deactivated models no longer earn rewards
     */
    function deactivateModel(bytes32 modelHash) external onlyOracle {
        require(modelActive[modelHash], "Model not active");

        modelActive[modelHash] = false;

        emit ModelDeactivated(modelHash);
    }

    /**
     * @notice Submit epoch settlement with Merkle root
     * @param epochId Epoch number to settle
     * @param merkleRoot Merkle root of reward leaves
     * @param totalReward Total reward for this epoch
     * @dev Only oracle can call. Leaf format: keccak256(abi.encodePacked(agent, epochId, amount))
     */
    function submitEpoch(uint256 epochId, bytes32 merkleRoot, uint256 totalReward) external onlyOracle {
        require(epochs[epochId].settledAt == 0, "Epoch already settled");
        require(merkleRoot != bytes32(0), "Empty root");
        require(totalReward > 0, "Zero reward");

        // Sync balance before settlement
        _syncRewards();

        epochs[epochId] = EpochSettlement({
            merkleRoot: merkleRoot, totalReward: totalReward, settledAt: block.number, finalized: false
        });

        emit EpochSubmitted(epochId, merkleRoot, totalReward);
    }

    /**
     * @notice Claim reward for a specific epoch
     * @param epochId Epoch number to claim from
     * @param amount Amount to claim
     * @param proof Merkle proof
     * @dev Leaf = keccak256(abi.encodePacked(msg.sender, epochId, amount))
     */
    function claim(uint256 epochId, uint256 amount, bytes32[] calldata proof) external nonReentrant {
        _claim(msg.sender, epochId, amount, proof);
    }

    /**
     * @notice Claim reward on behalf of another agent (sponsored claim)
     * @param agent Agent address to claim for
     * @param epochId Epoch number to claim from
     * @param amount Amount to claim
     * @param proof Merkle proof
     * @dev Enables sponsored claiming via precompile 0x23 or other authorized contracts
     *      Leaf = keccak256(abi.encodePacked(agent, epochId, amount))
     */
    function claimFor(address agent, uint256 epochId, uint256 amount, bytes32[] calldata proof) external nonReentrant {
        _claim(agent, epochId, amount, proof);
    }

    /**
     * @notice Internal claim logic
     * @param agent Agent address to claim for
     * @param epochId Epoch number
     * @param amount Amount to claim
     * @param proof Merkle proof
     */
    function _claim(address agent, uint256 epochId, uint256 amount, bytes32[] calldata proof) internal {
        EpochSettlement storage e = epochs[epochId];

        require(e.settledAt > 0, "Epoch not settled");
        require(block.number >= e.settledAt + DISPUTE_PERIOD, "Dispute period active");

        // Construct leaf hash
        bytes32 leaf = keccak256(abi.encodePacked(agent, epochId, amount));

        require(!claimed[leaf], "Already claimed");
        require(MerkleProof.verify(proof, e.merkleRoot, leaf), "Invalid proof");

        // Mark as claimed
        claimed[leaf] = true;

        // Update balance tracking
        lastTrackedBalance -= amount;

        // Transfer reward
        (bool success,) = payable(agent).call{value: amount}("");
        require(success, "Transfer failed");

        emit RewardClaimed(agent, epochId, amount);
    }

    /**
     * @notice Set cluster bonus parameters
     * @param perNode Bonus per extra node in basis points (e.g., 12 = 0.12x)
     * @param maxBonus Maximum cluster bonus in basis points (e.g., 50 = 0.50x)
     * @dev Only oracle can call. Prevents excessive cluster incentives.
     */
    function setClusterParams(uint256 perNode, uint256 maxBonus) external onlyOracle {
        require(perNode <= 30, "Per node too high"); // Max 0.30x per node
        require(maxBonus <= 100, "Max bonus too high"); // Max 1.00x bonus

        clusterBonusPerNode = perNode;
        maxClusterBonus = maxBonus;

        emit ClusterParamsUpdated(perNode, maxBonus);
    }

    /**
     * @notice Set oracle address
     * @param _oracle New oracle address
     * @dev Only owner can call
     */
    function setOracle(address _oracle) external onlyOwner {
        require(_oracle != address(0), "Invalid oracle");

        address oldOracle = oracle;
        oracle = _oracle;

        emit OracleUpdated(oldOracle, _oracle);
    }

    /**
     * @notice Get current epoch number
     * @return Current epoch
     */
    function getCurrentEpoch() public view returns (uint256) {
        if (block.number <= deployBlock) return 0;
        return (block.number - deployBlock) / BLOCKS_PER_EPOCH;
    }

    /**
     * @notice Check if a reward has been claimed
     * @param agent Agent address
     * @param epochId Epoch number
     * @param amount Amount
     * @return True if claimed
     */
    function isClaimed(address agent, uint256 epochId, uint256 amount) external view returns (bool) {
        bytes32 leaf = keccak256(abi.encodePacked(agent, epochId, amount));
        return claimed[leaf];
    }
}
