// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./interfaces/IEcosystemFund.sol";

/**
 * @title EcosystemFund
 * @notice Manages ecosystem development funds with governance controls
 * @dev Total allocation: 55,664,000 PLM
 */
contract EcosystemFund is IEcosystemFund, Ownable, ReentrancyGuard {
    /// @notice Total PLM allocated to ecosystem
    uint256 public totalAllocation;

    /// @notice Rate limit: max 5% per transaction
    uint256 public constant RATE_LIMIT_PERCENT = 5;

    /// @notice Timelock: minimum 24 hours between transfers
    uint256 public constant TIMELOCK_DURATION = 24 hours;

    /// @notice Emergency rate limit: max 20% per transaction
    uint256 public constant EMERGENCY_RATE_LIMIT_PERCENT = 20;

    /// @notice Last transfer timestamp
    uint256 public lastTransferTimestamp;

    /// @notice Emergency mode (disables rate limit and timelock)
    bool public emergencyMode;

    /**
     * @notice Constructor
     * @dev In genesis deployment, state variables are set directly via storage slots
     */
    constructor() Ownable(msg.sender) {
        totalAllocation = 55_664_000 ether;
        lastTransferTimestamp = 0;
        emergencyMode = false;
    }

    /**
     * @notice Transfer funds to ecosystem project
     * @param to Recipient address
     * @param amount Amount to transfer
     */
    function transfer(address to, uint256 amount) external override onlyOwner nonReentrant {
        require(to != address(0), "Invalid recipient");
        require(amount > 0, "Amount must be positive");
        require(address(this).balance >= amount, "Insufficient balance");

        if (!emergencyMode) {
            uint256 maxAmount = (totalAllocation * RATE_LIMIT_PERCENT) / 100;
            require(amount <= maxAmount, "Exceeds rate limit");
            require(
                lastTransferTimestamp == 0 || block.timestamp >= lastTransferTimestamp + TIMELOCK_DURATION,
                "Timelock active"
            );
        } else {
            // Emergency: higher rate limit, no timelock
            uint256 emergencyMax = (totalAllocation * EMERGENCY_RATE_LIMIT_PERCENT) / 100;
            require(amount <= emergencyMax, "Exceeds emergency rate limit");
        }

        lastTransferTimestamp = block.timestamp;

        (bool success,) = to.call{value: amount}("");
        require(success, "Transfer failed");

        emit Transfer(to, amount);
    }

    /**
     * @notice Batch transfer to multiple recipients
     * @param recipients Array of recipient addresses
     * @param amounts Array of amounts
     */
    function transferBatch(address[] calldata recipients, uint256[] calldata amounts)
        external
        override
        onlyOwner
        nonReentrant
    {
        require(recipients.length == amounts.length, "Length mismatch");
        require(recipients.length > 0, "Empty arrays");

        uint256 totalAmount = 0;
        for (uint256 i = 0; i < amounts.length; i++) {
            totalAmount += amounts[i];
        }

        require(address(this).balance >= totalAmount, "Insufficient balance");

        if (!emergencyMode) {
            uint256 maxAmount = (totalAllocation * RATE_LIMIT_PERCENT) / 100;
            require(totalAmount <= maxAmount, "Exceeds rate limit");
            require(
                lastTransferTimestamp == 0 || block.timestamp >= lastTransferTimestamp + TIMELOCK_DURATION,
                "Timelock active"
            );
        } else {
            uint256 emergencyMax = (totalAllocation * EMERGENCY_RATE_LIMIT_PERCENT) / 100;
            require(totalAmount <= emergencyMax, "Exceeds emergency rate limit");
        }

        for (uint256 i = 0; i < recipients.length; i++) {
            require(recipients[i] != address(0), "Invalid recipient");
            require(amounts[i] > 0, "Amount must be positive");

            (bool success,) = recipients[i].call{value: amounts[i]}("");
            require(success, "Transfer failed");

            emit Transfer(recipients[i], amounts[i]);
        }

        lastTransferTimestamp = block.timestamp;
        emit BatchTransfer(recipients.length, totalAmount);
    }

    /**
     * @notice Enable/disable emergency mode
     * @param enabled Emergency mode status
     */
    function setEmergencyMode(bool enabled) external override onlyOwner {
        emergencyMode = enabled;
        emit EmergencyModeChanged(enabled);
    }

    /**
     * @notice Get remaining balance
     * @return Current balance
     */
    function getBalance() external view override returns (uint256) {
        return address(this).balance;
    }

    /**
     * @notice Get time until next transfer allowed
     * @return Seconds until timelock expires (0 if ready)
     */
    function getTimeUntilUnlock() external view override returns (uint256) {
        if (emergencyMode || lastTransferTimestamp == 0) {
            return 0;
        }

        uint256 unlockTime = lastTransferTimestamp + TIMELOCK_DURATION;
        if (block.timestamp >= unlockTime) {
            return 0;
        }

        return unlockTime - block.timestamp;
    }

    /**
     * @notice Receive PLM (for genesis allocation)
     */
    receive() external payable {
        emit Received(msg.sender, msg.value);
    }
}
