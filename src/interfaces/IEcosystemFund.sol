// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

/**
 * @title IEcosystemFund
 * @notice Interface for EcosystemFund contract
 */
interface IEcosystemFund {
    /**
     * @notice Emitted when funds are transferred
     * @param to Recipient address
     * @param amount Amount transferred
     */
    event Transfer(address indexed to, uint256 amount);

    /**
     * @notice Emitted when batch transfer is completed
     * @param count Number of recipients
     * @param totalAmount Total amount transferred
     */
    event BatchTransfer(uint256 count, uint256 totalAmount);

    /**
     * @notice Emitted when emergency mode is changed
     * @param enabled New emergency mode status
     */
    event EmergencyModeChanged(bool enabled);

    /**
     * @notice Emitted when PLM is received
     * @param from Sender address
     * @param amount Amount received
     */
    event Received(address indexed from, uint256 amount);

    /**
     * @notice Transfer funds to ecosystem project
     * @param to Recipient address
     * @param amount Amount to transfer
     */
    function transfer(address to, uint256 amount) external;

    /**
     * @notice Batch transfer to multiple recipients
     * @param recipients Array of recipient addresses
     * @param amounts Array of amounts
     */
    function transferBatch(
        address[] calldata recipients,
        uint256[] calldata amounts
    ) external;

    /**
     * @notice Enable/disable emergency mode
     * @param enabled Emergency mode status
     */
    function setEmergencyMode(bool enabled) external;

    /**
     * @notice Get remaining balance
     * @return Current balance
     */
    function getBalance() external view returns (uint256);

    /**
     * @notice Get time until next transfer allowed
     * @return Seconds until timelock expires
     */
    function getTimeUntilUnlock() external view returns (uint256);
}
