// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

/**
 * @title IChallengeManager
 * @notice Interface for ChallengeManager contract
 */
interface IChallengeManager {
    /**
     * @notice Challenge data structure
     * @param id Challenge ID
     * @param difficulty Number of leading zero bits required
     * @param seed Random seed for the challenge
     * @param createdAt Creation timestamp
     * @param expiresAt Expiration timestamp
     * @param solved Whether challenge is solved
     * @param solver Address that solved the challenge
     * @param rewardBonus Bonus reward for solving (in addition to normal rewards)
     */
    struct Challenge {
        uint256 id;
        uint256 difficulty;
        bytes32 seed;
        uint256 createdAt;
        uint256 expiresAt;
        bool solved;
        address solver;
        uint256 rewardBonus;
    }

    /**
     * @notice Emitted when a new challenge is created
     * @param id Challenge ID
     * @param difficulty Difficulty level
     * @param seed Challenge seed
     * @param expiresAt Expiration timestamp
     * @param rewardBonus Bonus reward amount
     */
    event ChallengeCreated(
        uint256 indexed id,
        uint256 difficulty,
        bytes32 seed,
        uint256 expiresAt,
        uint256 rewardBonus
    );

    /**
     * @notice Emitted when a challenge is solved
     * @param id Challenge ID
     * @param solver Agent that solved it
     * @param solution Solution hash
     * @param solveTime Time taken to solve (seconds)
     */
    event ChallengeSolved(
        uint256 indexed id,
        address indexed solver,
        bytes32 solution,
        uint256 solveTime
    );

    /**
     * @notice Emitted when difficulty is adjusted
     * @param oldDifficulty Previous difficulty
     * @param newDifficulty New difficulty
     * @param reason Reason for adjustment
     */
    event DifficultyAdjusted(
        uint256 oldDifficulty,
        uint256 newDifficulty,
        string reason
    );

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
    ) external;

    /**
     * @notice Submit a solution to current challenge
     * @param challengeId Challenge ID
     * @param solution Solution hash
     */
    function submitSolution(uint256 challengeId, bytes32 solution) external;

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
    ) external view returns (bool);

    /**
     * @notice Get current active challenge
     * @return Challenge data
     */
    function getCurrentChallenge() external view returns (Challenge memory);

    /**
     * @notice Get challenge history
     * @param offset Starting index
     * @param limit Number of challenges to return
     * @return Array of challenges
     */
    function getChallengeHistory(
        uint256 offset,
        uint256 limit
    ) external view returns (Challenge[] memory);

    /**
     * @notice Set target solve time for difficulty adjustment
     * @param targetSolveTime Target time in seconds
     */
    function setDifficultyAdjuster(uint256 targetSolveTime) external;

    /**
     * @notice Get total number of challenges
     * @return Total challenge count
     */
    function getTotalChallenges() external view returns (uint256);

    /**
     * @notice Get challenge by ID
     * @param id Challenge ID
     * @return Challenge data
     */
    function getChallenge(uint256 id) external view returns (Challenge memory);
}
