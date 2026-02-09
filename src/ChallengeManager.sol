// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "./interfaces/IChallengeManager.sol";
import "./interfaces/IAgentRegistry.sol";
import "./interfaces/IRewardPool.sol";

/**
 * @title ChallengeManager
 * @notice Manages Proof of Useful Work challenges for AI agents
 * @dev Challenges require finding a hash with N leading zero bits
 */
contract ChallengeManager is IChallengeManager, Ownable {
    /// @notice Minimum difficulty (leading zero bits)
    uint256 public constant MIN_DIFFICULTY = 8;

    /// @notice Maximum difficulty (leading zero bits)
    uint256 public constant MAX_DIFFICULTY = 32;

    /// @notice Default challenge duration (1 hour)
    uint256 public constant DEFAULT_DURATION = 3600;

    /// @notice Agent registry contract
    IAgentRegistry public immutable agentRegistry;

    /// @notice Reward pool contract
    IRewardPool public immutable rewardPool;

    /// @notice Target solve time for difficulty adjustment (seconds)
    uint256 public targetSolveTime = 600; // 10 minutes

    /// @notice Current difficulty level
    uint256 public currentDifficulty = MIN_DIFFICULTY;

    /// @notice Challenge counter
    uint256 public challengeCounter;

    /// @notice Current active challenge ID
    uint256 public currentChallengeId;

    /// @notice Mapping of challenge ID to Challenge data
    mapping(uint256 => Challenge) public challenges;

    /// @notice Check if an address is authorized to create challenges
    mapping(address => bool) public isAutomation;

    /**
     * @notice Constructor
     * @param _agentRegistry Address of AgentRegistry contract
     * @param _rewardPool Address of RewardPool contract
     */
    constructor(
        address _agentRegistry,
        address _rewardPool
    ) Ownable(msg.sender) {
        require(_agentRegistry != address(0), "Invalid registry");
        require(_rewardPool != address(0), "Invalid reward pool");

        agentRegistry = IAgentRegistry(_agentRegistry);
        rewardPool = IRewardPool(_rewardPool);
    }

    /**
     * @notice Create a new challenge
     * @param difficulty Number of leading zero bits required
     * @param seed Random seed
     * @param duration Challenge duration in seconds
     */
    function createChallenge(
        uint256 difficulty,
        bytes32 seed,
        uint256 duration
    ) external override {
        require(
            msg.sender == owner() || isAutomation[msg.sender],
            "Not authorized"
        );
        require(difficulty >= MIN_DIFFICULTY && difficulty <= MAX_DIFFICULTY, "Invalid difficulty");
        require(duration > 0 && duration <= 7 days, "Invalid duration");

        // Expire current challenge if exists
        if (currentChallengeId > 0) {
            Challenge storage current = challenges[currentChallengeId];
            if (!current.solved && block.timestamp < current.expiresAt) {
                // Current challenge still active, cannot create new one
                revert("Challenge already active");
            }
        }

        challengeCounter++;
        currentChallengeId = challengeCounter;

        challenges[challengeCounter] = Challenge({
            id: challengeCounter,
            difficulty: difficulty,
            seed: seed,
            createdAt: block.timestamp,
            expiresAt: block.timestamp + duration,
            solved: false,
            solver: address(0),
            rewardBonus: 0 // Can be set separately if needed
        });

        emit ChallengeCreated(
            challengeCounter,
            difficulty,
            seed,
            block.timestamp + duration,
            0
        );
    }

    /**
     * @notice Submit a solution to current challenge
     * @param challengeId Challenge ID
     * @param solution Solution hash
     */
    function submitSolution(
        uint256 challengeId,
        bytes32 solution
    ) external override {
        require(agentRegistry.isActive(msg.sender), "Agent not active");
        require(challengeId == currentChallengeId, "Not current challenge");

        Challenge storage challenge = challenges[challengeId];
        require(!challenge.solved, "Already solved");
        require(block.timestamp < challenge.expiresAt, "Challenge expired");

        // Verify solution
        require(
            verifySolution(challengeId, solution, msg.sender),
            "Invalid solution"
        );

        // Mark as solved
        challenge.solved = true;
        challenge.solver = msg.sender;

        uint256 solveTime = block.timestamp - challenge.createdAt;

        // Report to reward pool as task contribution
        rewardPool.reportContribution(msg.sender, 1, 0, 100);

        // Adjust difficulty based on solve time
        _adjustDifficulty(solveTime);

        emit ChallengeSolved(challengeId, msg.sender, solution, solveTime);
    }

    /**
     * @notice Verify a solution without submitting
     * @param challengeId Challenge ID
     * @param solution Solution hash
     * @param solver Address to verify for
     * @return true if solution is valid
     */
    function verifySolution(
        uint256 challengeId,
        bytes32 solution,
        address solver
    ) public view override returns (bool) {
        Challenge memory challenge = challenges[challengeId];

        // Compute hash: keccak256(seed, solution, solver)
        bytes32 hash = keccak256(abi.encodePacked(
            challenge.seed,
            solution,
            solver
        ));

        // Check if hash has required number of leading zero bits
        return _hasLeadingZeroBits(hash, challenge.difficulty);
    }

    /**
     * @notice Get current active challenge
     * @return Challenge data
     */
    function getCurrentChallenge() external view override returns (Challenge memory) {
        require(currentChallengeId > 0, "No challenge exists");
        return challenges[currentChallengeId];
    }

    /**
     * @notice Get challenge history
     * @param offset Starting index (from most recent)
     * @param limit Number of challenges to return
     * @return Array of challenges
     */
    function getChallengeHistory(
        uint256 offset,
        uint256 limit
    ) external view override returns (Challenge[] memory) {
        require(limit > 0 && limit <= 100, "Invalid limit");

        uint256 total = challengeCounter;
        if (offset >= total) {
            return new Challenge[](0);
        }

        uint256 count = total - offset;
        if (count > limit) {
            count = limit;
        }

        Challenge[] memory history = new Challenge[](count);

        for (uint256 i = 0; i < count; i++) {
            uint256 id = total - offset - i;
            history[i] = challenges[id];
        }

        return history;
    }

    /**
     * @notice Set target solve time for difficulty adjustment
     * @param _targetSolveTime Target time in seconds
     */
    function setDifficultyAdjuster(uint256 _targetSolveTime) external override onlyOwner {
        require(_targetSolveTime >= 60 && _targetSolveTime <= 1 days, "Invalid target time");
        targetSolveTime = _targetSolveTime;
    }

    /**
     * @notice Set automation address
     * @param automation Address to authorize
     * @param authorized Authorization status
     */
    function setAutomation(address automation, bool authorized) external onlyOwner {
        require(automation != address(0), "Invalid address");
        isAutomation[automation] = authorized;
    }

    /**
     * @notice Get total number of challenges
     * @return Total challenge count
     */
    function getTotalChallenges() external view override returns (uint256) {
        return challengeCounter;
    }

    /**
     * @notice Get challenge by ID
     * @param id Challenge ID
     * @return Challenge data
     */
    function getChallenge(uint256 id) external view override returns (Challenge memory) {
        require(id > 0 && id <= challengeCounter, "Invalid challenge ID");
        return challenges[id];
    }

    /**
     * @notice Check if hash has N leading zero bits
     * @param hash Hash to check
     * @param bits Number of leading zero bits required
     * @return true if hash has enough leading zero bits
     */
    function _hasLeadingZeroBits(bytes32 hash, uint256 bits) internal pure returns (bool) {
        require(bits <= 256, "Too many bits");

        uint256 hashUint = uint256(hash);

        // Check if the top `bits` bits are zero
        return (hashUint >> (256 - bits)) == 0;
    }

    /**
     * @notice Adjust difficulty based on solve time
     * @param solveTime Time taken to solve challenge
     */
    function _adjustDifficulty(uint256 solveTime) internal {
        uint256 oldDifficulty = currentDifficulty;
        uint256 newDifficulty = oldDifficulty;

        // If solved much faster than target, increase difficulty
        if (solveTime < targetSolveTime / 2) {
            if (currentDifficulty < MAX_DIFFICULTY) {
                newDifficulty = currentDifficulty + 1;
                currentDifficulty = newDifficulty;
                emit DifficultyAdjusted(oldDifficulty, newDifficulty, "Too fast");
            }
        }
        // If solved much slower than target, decrease difficulty
        else if (solveTime > targetSolveTime * 2) {
            if (currentDifficulty > MIN_DIFFICULTY) {
                newDifficulty = currentDifficulty - 1;
                currentDifficulty = newDifficulty;
                emit DifficultyAdjusted(oldDifficulty, newDifficulty, "Too slow");
            }
        }
    }
}
