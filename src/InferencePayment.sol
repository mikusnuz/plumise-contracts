// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./interfaces/IInferencePayment.sol";

/**
 * @title InferencePayment
 * @notice Manages payment for AI inference on Plumise chain
 * @dev Users deposit PLM to get Pro tier access
 *
 * SECURITY NOTES:
 * - Treasury must be a trusted contract/EOA that always accepts ETH
 * - If treasury rejects transfers, useCredits() will fail (DOS risk)
 * - Future improvement: Use pull pattern for treasury withdrawals
 * - Oracle address is single point of trust (consider multi-sig)
 */
contract InferencePayment is IInferencePayment, Ownable, ReentrancyGuard {
    /// @notice Pro tier requires minimum 100 PLM deposit
    uint256 public constant PRO_TIER_MINIMUM = 100 ether;

    /// @notice Cost per 1000 tokens (in wei)
    uint256 public costPer1000Tokens = 0.001 ether;

    /// @notice Gateway address authorized to deduct credits
    address public gateway;

    /// @notice User credits
    mapping(address => UserCredit) public userCredits;

    /// @notice Treasury for collected fees
    address public treasury;

    /**
     * @notice Constructor
     * @param _gateway Address of gateway
     * @param _treasury Address of treasury
     */
    constructor(address _gateway, address _treasury) Ownable(msg.sender) {
        require(_gateway != address(0), "Invalid gateway");
        require(_treasury != address(0), "Invalid treasury");

        gateway = _gateway;
        treasury = _treasury;
    }

    /**
     * @notice User deposits PLM
     */
    function deposit() external payable override nonReentrant {
        require(msg.value > 0, "Zero deposit");

        userCredits[msg.sender].balance += msg.value;
        userCredits[msg.sender].lastDeposit = block.timestamp;

        // Auto-upgrade to Pro if meets minimum
        if (userCredits[msg.sender].balance >= PRO_TIER_MINIMUM && userCredits[msg.sender].tier == 0) {
            userCredits[msg.sender].tier = 1;
            emit TierChanged(msg.sender, 0, 1);
        }

        emit Deposited(msg.sender, msg.value, userCredits[msg.sender].balance);
    }

    /**
     * @notice Gateway deducts credits for inference usage
     * @param user User address
     * @param tokenCount Number of tokens processed
     */
    function useCredits(address user, uint256 tokenCount) external override nonReentrant {
        require(msg.sender == gateway, "Only gateway");
        require(tokenCount > 0, "Zero tokens");

        uint256 cost = (tokenCount * costPer1000Tokens) / 1000;
        require(userCredits[user].balance >= cost, "Insufficient balance");

        // SECURITY: Effects before interactions (Checks-Effects-Interactions)
        userCredits[user].balance -= cost;
        userCredits[user].usedCredits += cost;

        // Downgrade from Pro if below minimum
        uint256 oldTier = userCredits[user].tier;
        if (userCredits[user].balance < PRO_TIER_MINIMUM && oldTier == 1) {
            userCredits[user].tier = 0;
        }

        // SECURITY: External call last to prevent reentrancy
        // Transfer fee to treasury
        (bool success,) = treasury.call{value: cost}("");
        require(success, "Treasury transfer failed");

        if (oldTier == 1 && userCredits[user].tier == 0) {
            emit TierChanged(user, 1, 0);
        }

        emit CreditUsed(user, tokenCount, cost);
    }

    /**
     * @notice User withdraws remaining balance
     * @param amount Amount to withdraw
     */
    function withdraw(uint256 amount) external override nonReentrant {
        require(amount > 0, "Zero amount");
        require(userCredits[msg.sender].balance >= amount, "Insufficient balance");

        userCredits[msg.sender].balance -= amount;

        // Check tier downgrade
        if (userCredits[msg.sender].balance < PRO_TIER_MINIMUM && userCredits[msg.sender].tier == 1) {
            userCredits[msg.sender].tier = 0;
            emit TierChanged(msg.sender, 1, 0);
        }

        (bool success,) = msg.sender.call{value: amount}("");
        require(success, "Transfer failed");

        emit Withdrawn(msg.sender, amount);
    }

    /**
     * @notice Get user tier
     * @param user User address
     * @return User tier (0 = Free, 1 = Pro)
     */
    function getUserTier(address user) external view override returns (uint256) {
        return userCredits[user].tier;
    }

    /**
     * @notice Get user balance
     * @param user User address
     * @return User balance in wei
     */
    function getUserBalance(address user) external view override returns (uint256) {
        return userCredits[user].balance;
    }

    /**
     * @notice Check if user is Pro tier
     * @param user User address
     * @return true if Pro tier
     */
    function isProTier(address user) external view override returns (bool) {
        return userCredits[user].tier == 1;
    }

    /**
     * @notice Get user credit data
     * @param user User address
     * @return UserCredit struct
     */
    function getUserCredit(address user) external view override returns (UserCredit memory) {
        return userCredits[user];
    }

    /**
     * @notice Set gateway address
     * @param _gateway New gateway address
     */
    function setGateway(address _gateway) external override onlyOwner {
        require(_gateway != address(0), "Invalid gateway");
        address oldGateway = gateway;
        gateway = _gateway;
        emit GatewayUpdated(oldGateway, _gateway);
    }

    /**
     * @notice Set cost per 1000 tokens
     * @param _cost New cost in wei
     */
    function setCostPer1000Tokens(uint256 _cost) external override onlyOwner {
        // SECURITY: Enforce minimum cost to prevent economic exploit
        require(_cost >= 0.0001 ether, "Cost too low");
        uint256 oldCost = costPer1000Tokens;
        costPer1000Tokens = _cost;
        emit CostUpdated(oldCost, _cost);
    }

    /**
     * @notice Set treasury address
     * @param _treasury New treasury address
     */
    function setTreasury(address _treasury) external override onlyOwner {
        require(_treasury != address(0), "Invalid treasury");
        address oldTreasury = treasury;
        treasury = _treasury;
        emit TreasuryUpdated(oldTreasury, _treasury);
    }
}
