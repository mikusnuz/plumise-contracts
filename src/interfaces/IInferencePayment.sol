// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

/**
 * @title IInferencePayment
 * @notice Interface for InferencePayment contract
 */
interface IInferencePayment {
    /**
     * @notice User credit data structure
     * @param balance Deposited PLM balance
     * @param usedCredits Credits consumed
     * @param lastDeposit Last deposit timestamp
     * @param tier 0 = Free, 1 = Pro
     */
    struct UserCredit {
        uint256 balance;
        uint256 usedCredits;
        uint256 lastDeposit;
        uint256 tier;
    }

    /**
     * @notice Emitted when user deposits PLM
     * @param user User address
     * @param amount Amount deposited
     * @param newBalance New balance
     */
    event Deposited(address indexed user, uint256 amount, uint256 newBalance);

    /**
     * @notice Emitted when credit is used
     * @param user User address
     * @param tokens Number of tokens processed
     * @param cost Cost in wei
     */
    event CreditUsed(address indexed user, uint256 tokens, uint256 cost);

    /**
     * @notice Emitted when user withdraws
     * @param user User address
     * @param amount Amount withdrawn
     */
    event Withdrawn(address indexed user, uint256 amount);

    /**
     * @notice Emitted when user tier changes
     * @param user User address
     * @param oldTier Previous tier
     * @param newTier New tier
     */
    event TierChanged(address indexed user, uint256 oldTier, uint256 newTier);

    /**
     * @notice Emitted when gateway is updated
     * @param oldGateway Previous gateway address
     * @param newGateway New gateway address
     */
    event GatewayUpdated(address indexed oldGateway, address indexed newGateway);

    /**
     * @notice Emitted when cost is updated
     * @param oldCost Previous cost per 1000 tokens
     * @param newCost New cost per 1000 tokens
     */
    event CostUpdated(uint256 oldCost, uint256 newCost);

    /**
     * @notice Emitted when treasury is updated
     * @param oldTreasury Previous treasury address
     * @param newTreasury New treasury address
     */
    event TreasuryUpdated(address indexed oldTreasury, address indexed newTreasury);

    /**
     * @notice User deposits PLM
     */
    function deposit() external payable;

    /**
     * @notice Gateway deducts credits for inference usage
     * @param user User address
     * @param tokenCount Number of tokens processed
     */
    function useCredits(address user, uint256 tokenCount) external;

    /**
     * @notice User withdraws remaining balance
     * @param amount Amount to withdraw
     */
    function withdraw(uint256 amount) external;

    /**
     * @notice Get user tier
     * @param user User address
     * @return User tier (0 = Free, 1 = Pro)
     */
    function getUserTier(address user) external view returns (uint256);

    /**
     * @notice Get user balance
     * @param user User address
     * @return User balance in wei
     */
    function getUserBalance(address user) external view returns (uint256);

    /**
     * @notice Check if user is Pro tier
     * @param user User address
     * @return true if Pro tier
     */
    function isProTier(address user) external view returns (bool);

    /**
     * @notice Get user credit data
     * @param user User address
     * @return UserCredit struct
     */
    function getUserCredit(address user) external view returns (UserCredit memory);

    /**
     * @notice Set gateway address
     * @param gateway New gateway address
     */
    function setGateway(address gateway) external;

    /**
     * @notice Set cost per 1000 tokens
     * @param cost New cost in wei
     */
    function setCostPer1000Tokens(uint256 cost) external;

    /**
     * @notice Set treasury address
     * @param treasury New treasury address
     */
    function setTreasury(address treasury) external;
}
